import AVFoundation
import AppKit
import Combine
import Defaults

/// WhisperFlow-style dictation: press the hotkey, speak, press again — the
/// transcript is pasted at the cursor. All local (whisper.cpp, no network
/// after the one-time model download).
@MainActor
final class DictationManager: ObservableObject {
    enum State: Equatable {
        case idle
        case recording
        case transcribing
    }

    @Published private(set) var state: State = .idle
    /// Smoothed mic loudness 0…1, driving the live waveform in the notch.
    @Published private(set) var level: Double = 0
    /// When the current take started (drives the elapsed time in the pill).
    @Published private(set) var startedAt: Date?

    /// Fires with the final transcript (paste target: the frontmost app).
    var onTranscript: ((String) -> Void)?
    /// Notch announcements: (SF Symbol, message).
    var onEvent: ((String, String) -> Void)?
    /// First press with no model installed → open Settings.
    var onNeedsSetup: (() -> Void)?

    var isActive: Bool { state != .idle }

    private let engine = AVAudioEngine()
    private let transcriber = WhisperTranscriber()
    /// Audio thread storage — guarded by `sampleLock`, not the main actor.
    private let sampleLock = NSLock()
    private nonisolated(unsafe) var sampleStorage: [Float] = []
    private nonisolated(unsafe) var converter: AVAudioConverter?

    // MARK: Public control

    func toggle() {
        switch state {
        case .idle:
            start()
        case .recording:
            stopAndTranscribe()
        case .transcribing:
            break  // whisper is already running; wait for the result
        }
    }

    /// Abort without transcribing (click on the notch pill).
    func cancel() {
        guard state == .recording else { return }
        stopEngine()
        state = .idle
        level = 0
        startedAt = nil
    }

    // MARK: Start

    private func start() {
        guard Defaults[.dictationEnabled] else {
            onEvent?("waveform.slash", "Dictation is off — enable it in Settings")
            return
        }
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            beginRecording()
        case .undetermined:
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted {
                        self.beginRecording()
                    } else {
                        self.onEvent?("mic.slash", "Microphone access denied")
                    }
                }
            }
        default:
            onEvent?("mic.slash", "Microphone access denied — see Settings › Dictation")
        }
    }

    private func beginRecording() {
        let modelID = Defaults[.dictationModelID]
        guard DictationModelStore.isDownloaded(modelID) else {
            onEvent?("arrow.down.circle", "No speech model — grab one in Settings")
            onNeedsSetup?()
            return
        }
        do {
            try startEngine()
        } catch {
            onEvent?("mic.slash", "Microphone unavailable")
            return
        }
        state = .recording
        startedAt = Date()
        playSound("Tink")
    }

    // MARK: Engine

    private func startEngine() throws {
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0,
              let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                            sampleRate: 16_000,
                                            channels: 1,
                                            interleaved: false)
        else {
            throw NSError(domain: "perch.dictation", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No audio input device"])
        }

        sampleLock.lock()
        sampleStorage.removeAll(keepingCapacity: true)
        sampleLock.unlock()
        converter = AVAudioConverter(from: inFormat, to: outFormat)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4_096, format: inFormat) { [weak self] buffer, _ in
            self?.ingest(buffer: buffer, to: outFormat)
        }
        engine.prepare()
        try engine.start()
    }

    /// Runs on the audio render thread: meters the raw input, converts it to
    /// 16 kHz mono Float32, and appends it to the capture buffer.
    nonisolated private func ingest(buffer: AVAudioPCMBuffer, to outFormat: AVAudioFormat) {
        // Level: RMS on channel 0.
        if let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 {
            let n = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<n { let v = channel[i]; sum += v * v }
            let rms = sqrt(sum / Float(n))
            let normalized = min(1, Double(rms) / 0.30)
            DispatchQueue.main.async { [weak self] in
                self?.smoothLevel(normalized)
            }
        }

        // Convert to 16 kHz mono.
        guard let converter else { return }
        let ratio = outFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }
        var fed = false
        var conversionError: NSError?
        let status = converter.convert(to: out, error: &conversionError) { _, inputStatus in
            if fed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, conversionError == nil, out.frameLength > 0,
              let channel = out.floatChannelData?[0]
        else { return }

        sampleLock.lock()
        sampleStorage.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
        sampleLock.unlock()
    }

    private func smoothLevel(_ raw: Double) {
        let shaped = sqrt(max(0, min(1, raw)))  // perceptual curve
        level = level * 0.55 + shaped * 0.45
    }

    private func stopEngine() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
    }

    /// Drains the capture buffer (audio thread storage → caller-owned array).
    private func collectSamples() -> [Float] {
        sampleLock.lock()
        defer { sampleLock.unlock() }
        let samples = sampleStorage
        sampleStorage.removeAll(keepingCapacity: true)
        return samples
    }

    // MARK: Stop → transcribe → deliver

    private func stopAndTranscribe() {
        stopEngine()
        let audio = collectSamples()
        level = 0

        guard audio.count >= 1_600 else {  // < ~100 ms of speech
            state = .idle
            startedAt = nil
            return
        }

        state = .transcribing
        playSound("Pop")

        let modelPath = DictationModelStore.modelURL(for: Defaults[.dictationModelID]).path
        let language = Defaults[.dictationLanguage]
        let transcriber = self.transcriber

        Task.detached(priority: .userInitiated) { [weak self] in
            let text: String
            do {
                text = Self.postProcess(try await transcriber.transcribe(
                    samples: audio, modelPath: modelPath, language: language))
            } catch {
                await MainActor.run { [weak self] in
                    self?.state = .idle
                    self?.startedAt = nil
                    self?.onEvent?("exclamationmark.triangle", "Transcription failed")
                }
                return
            }
            let final = text
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.state = .idle
                self.startedAt = nil
                if final.isEmpty {
                    self.onEvent?("waveform.slash", "Nothing heard")
                } else {
                    self.onTranscript?(final)
                }
            }
        }
    }

    // MARK: Post-processing

    /// Common whisper hallucinations on silence/keyboard noise. If the entire
    /// output is one of these, treat the take as empty rather than pasting junk.
    nonisolated private static let hallucinations: Set<String> = [
        "Thank you.", "Thanks.", "Thank you for watching.", "Thanks for watching!",
        "Thank you.", "Bye.", "Bye bye.", "Okay.", "Mm-hmm.", "Hmm.",
        "Subtitles by the Amara.org community", "[Music]", "(music)", "♪♪", "...",
    ]

    nonisolated static func postProcess(_ text: String) -> String {
        var t = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("♪") || t.hasSuffix("♪") { t = "" }  // music hallucination
        if hallucinations.contains(t) { return "" }
        return t
    }

    // MARK: Feedback

    private func playSound(_ name: String) {
        guard Defaults[.dictationSoundFeedback] else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}
