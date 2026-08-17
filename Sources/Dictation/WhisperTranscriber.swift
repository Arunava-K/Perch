import Foundation
import whisper

enum DictationError: LocalizedError {
    case modelLoadFailed
    case notEnoughAudio
    case transcriptionFailed

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed: return "The speech model couldn't be loaded."
        case .notEnoughAudio: return "Too little audio captured."
        case .transcriptionFailed: return "Transcription failed."
        }
    }
}

/// One whisper segment with absolute timestamps in milliseconds.
struct WhisperSegment {
    let text: String
    let startMs: Double
    let endMs: Double
}

/// Thin wrapper around whisper.cpp. The whisper context (model weights) is
/// expensive to load, so it's cached across sessions and only reloaded when
/// the model file changes. All work runs on a private serial queue.
final class WhisperTranscriber: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.steinerco.perch.whisper", qos: .userInitiated)
    private var context: OpaquePointer?
    private var loadedPath: String?

    deinit {
        if let context { whisper_free(context) }
    }

    /// Drop the cached model (e.g. after the model file is replaced/deleted).
    func unload() {
        queue.sync {
            if let context { whisper_free(context) }
            context = nil
            loadedPath = nil
        }
    }

    /// Transcribe 16 kHz mono Float32 PCM into text. Async hop onto the
    /// private queue; whisper itself is synchronous and CPU/GPU bound.
    func transcribe(samples: [Float], modelPath: String, language: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    continuation.resume(returning: try run(samples: samples, modelPath: modelPath, language: language))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Segment-level transcription (streaming chunks). Timestamps are returned
    /// in absolute milliseconds relative to the sample window; `prompt` seeds
    /// the decoder with prior context so punctuation/case stay consistent
    /// across chunk boundaries.
    func transcribeSegments(samples: [Float], modelPath: String, language: String, prompt: String?) async throws -> [WhisperSegment] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    continuation.resume(returning: try runSegments(samples: samples, modelPath: modelPath, language: language, prompt: prompt))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func run(samples: [Float], modelPath: String, language: String) throws -> String {
        try join(segments: runSegments(samples: samples, modelPath: modelPath, language: language, prompt: nil))
    }

    private func join(segments: [WhisperSegment]) -> String {
        segments.map(\.text).joined(separator: " ").trimmed
    }

    private func runSegments(samples: [Float], modelPath: String, language: String, prompt: String?) throws -> [WhisperSegment] {
        // (Re)load the model if needed.
        if loadedPath != modelPath {
            if let context { whisper_free(context); self.context = nil; loadedPath = nil }
            var cparams = whisper_context_default_params()
            cparams.use_gpu = true
            cparams.flash_attn = true
            guard let ctx = modelPath.withCString({ whisper_init_from_file_with_params($0, cparams) }) else {
                throw DictationError.modelLoadFailed
            }
            context = ctx
            loadedPath = modelPath
        }
        guard let context else { throw DictationError.modelLoadFailed }
        guard samples.count >= 1_600 else { throw DictationError.notEnoughAudio }  // ~100 ms

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = Int32(min(8, max(4, ProcessInfo.processInfo.activeProcessorCount)))
        params.translate = false
        params.no_context = true
        params.no_timestamps = false   // streaming needs segment timestamps
        params.print_special = false
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.suppress_nst = true

        // The C strings must outlive whisper_full.
        let lang = strdup(language)
        defer { free(lang) }
        params.language = UnsafePointer(lang)

        var promptCopy: UnsafeMutablePointer<CChar>?
        if let prompt, !prompt.isEmpty {
            promptCopy = strdup(String(prompt.suffix(200)))
            params.initial_prompt = UnsafePointer(promptCopy)
        }
        defer { free(promptCopy) }

        let rc = samples.withUnsafeBufferPointer { buffer in
            whisper_full(context, params, buffer.baseAddress, Int32(samples.count))
        }
        guard rc == 0 else { throw DictationError.transcriptionFailed }

        var out: [WhisperSegment] = []
        let n = whisper_full_n_segments(context)
        for i in 0..<n {
            guard let cString = whisper_full_get_segment_text(context, i) else { continue }
            // whisper timestamps are centiseconds → ms.
            let startMs = Double(whisper_full_get_segment_t0(context, i)) * 10.0
            let endMs = Double(whisper_full_get_segment_t1(context, i)) * 10.0
            out.append(WhisperSegment(text: String(cString: cString).trimmed, startMs: startMs, endMs: endMs))
        }
        return out
    }
}

private extension String {
    /// whisper pads segment text with spaces; trim for stitching.
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
