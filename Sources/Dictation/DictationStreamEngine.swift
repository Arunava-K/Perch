import Foundation

/// Chunked streaming transcription: every ~1.6s of new audio, transcribe the
/// un-finalized tail plus a short acoustic overlap. Segments that end before
/// the volatile overlap zone are *finalized* (their text never changes); the
/// rest stay provisional. The decoder is seeded with the finalized text so
/// punctuation/case stay consistent across chunk boundaries.
///
/// Unlike a rolling-window re-run (whisper.cpp's `stream` example), finalized
/// words never flicker or get rewritten, and each run only covers new audio.
@MainActor
final class DictationStreamEngine {
    struct Config {
        /// New audio (ms) required before a chunk run is scheduled.
        var stepMs: Double = 1_600
        /// Acoustic overlap re-transcribed with each chunk. Segments ending
        /// within this zone of the window end stay provisional.
        var overlapMs: Double = 700
        /// A chunk run may take a while on slow models — pace the next step to
        /// `lastRun × factor` so runs never queue up.
        var runTimeFactor: Double = 1.6
        /// Windows quieter than this (RMS) contain no speech — skip the GPU run.
        var minWindowRms: Float = 0.006
        /// Whisper processes 30s windows internally; cap ours lower.
        var maxWindowMs: Double = 24_000
    }

    private let config: Config
    private let sampleRate: Double = 16_000

    /// Text finalized so far (never revised).
    private(set) var finalText: String = ""
    /// Provisional text for the volatile tail — may change until finalized.
    private(set) var partialText: String = ""
    /// Capture-buffer index (in samples) up to which transcription is final.
    private(set) var committedSamples: Int = 0
    /// True once any chunk run has completed (enables the tail-finalize path).
    private(set) var hasStreamed = false

    private var generation = 0
    private var inFlight = false
    private var lastRunSeconds: Double = 0

    init(config: Config = Config()) {
        self.config = config
    }

    func reset() {
        generation += 1
        inFlight = false
        finalText = ""
        partialText = ""
        committedSamples = 0
        hasStreamed = false
        lastRunSeconds = 0
    }

    /// Called periodically while recording. Kicks off a chunk run when enough
    /// un-finalized audio has accumulated and no run is in flight.
    /// `read(from, to)` returns the capture-buffer samples in that range.
    func tickIfReady(
        totalSamples: Int,
        read: (Int, Int) -> [Float],
        transcriber: WhisperTranscriber,
        modelPath: String,
        language: String
    ) async {
        guard !inFlight else { return }
        let effectiveStepMs = max(config.stepMs, lastRunSeconds * 1000 * config.runTimeFactor)
        let pendingMs = Double(totalSamples - committedSamples) / sampleRate * 1000
        guard pendingMs >= effectiveStepMs else { return }

        // Window: from just before the commit point (acoustic overlap) to now,
        // capped so a mid-dictation pause can't grow the window unboundedly.
        let overlapSamples = Int(config.overlapMs / 1000 * sampleRate)
        let maxWindowSamples = Int(config.maxWindowMs / 1000 * sampleRate)
        let from = max(committedSamples - overlapSamples, totalSamples - maxWindowSamples, 0)
        guard totalSamples - from >= Int(0.6 * sampleRate) else { return }  // ≥ ~600 ms

        let window = read(from, totalSamples)
        guard window.count > 0 else { return }

        // Pure silence can't contain speech — skip the run (also dodges
        // whisper's silence hallucinations).
        guard Self.rms(window) >= config.minWindowRms else { return }

        inFlight = true
        let gen = generation
        let startedAt = Date()
        let prompt = finalText
        do {
            let segments = try await transcriber.transcribeSegments(
                samples: window, modelPath: modelPath, language: language, prompt: prompt)
            lastRunSeconds = Date().timeIntervalSince(startedAt)
            // Discard results from a cancelled/reset session (or a run that
            // outlived the take).
            guard gen == generation else { return }

            let windowStartMs = Double(from) / sampleRate * 1000
            let windowEndMs = Double(totalSamples) / sampleRate * 1000
            let result = Self.stitch(
                existingFinal: finalText,
                segments: segments,
                windowStartMs: windowStartMs,
                windowEndMs: windowEndMs,
                overlapMs: config.overlapMs,
                commitMs: Double(committedSamples) / sampleRate * 1000,
                sampleRate: sampleRate)
            finalText = result.finalText
            partialText = result.partialText
            committedSamples = max(committedSamples, result.commitSamples)
            hasStreamed = true
        } catch {
            // A failed chunk isn't fatal — the next tick (or the final tail
            // run) will cover the same audio.
            lastRunSeconds = 0
        }
        inFlight = false
    }

    /// After recording stops: transcribe the un-finalized tail (with the
    /// finalized text as prompt) and return the complete transcript.
    func finalizeTail(
        audio: [Float],
        transcriber: WhisperTranscriber,
        modelPath: String,
        language: String
    ) async throws -> String {
        guard hasStreamed else { return "" }
        let gen = generation
        let overlapSamples = Int(config.overlapMs / 1000 * sampleRate)
        let from = max(committedSamples - overlapSamples, 0)
        guard audio.count - from >= Int(0.6 * sampleRate) else {
            return Self.joinText(finalText, partialText)
        }
        let tail = Array(audio[from...])
        // Trailing silence — nothing new to transcribe.
        guard Self.rms(tail) >= config.minWindowRms else {
            return finalText.isEmpty ? partialText : finalText
        }
        let segments = try await transcriber.transcribeSegments(
            samples: tail, modelPath: modelPath, language: language, prompt: finalText)
        guard gen == generation else { return Self.joinText(finalText, partialText) }

        // Everything in the tail is final now (no volatile zone anymore).
        let windowStartMs = Double(from) / sampleRate * 1000
        let commitMs = Double(committedSamples) / sampleRate * 1000
        let tailText = segments
            .filter { windowStartMs + $0.endMs > commitMs + 10 }
            .map(\.text)
            .joined(separator: " ")
        return Self.joinText(finalText, tailText)
    }

    // MARK: Stitching (pure — harness-testable)

    struct StitchResult {
        let finalText: String
        let partialText: String
        let commitSamples: Int
    }

    /// A segment is final iff it ends at least `overlapMs` before the end of
    /// the transcribed window — earlier endings can no longer be revised by
    /// the acoustic context of future chunks.
    nonisolated static func stitch(
        existingFinal: String,
        segments: [WhisperSegment],
        windowStartMs: Double,
        windowEndMs: Double,
        overlapMs: Double,
        commitMs: Double,
        sampleRate: Double
    ) -> StitchResult {
        var finals: [String] = []
        var provisionals: [String] = []
        var lastFinalEndMs = commitMs

        for segment in segments {
            let absStart = windowStartMs + segment.startMs
            let absEnd = windowStartMs + segment.endMs
            let alreadyCommitted = absEnd <= commitMs + 10
            let inVolatileZone = windowEndMs - absEnd < overlapMs
            if !alreadyCommitted, !inVolatileZone, absEnd > lastFinalEndMs {
                finals.append(segment.text)
                lastFinalEndMs = absEnd
            } else if !alreadyCommitted {
                provisionals.append(segment.text)
            }
        }

        let mergedFinal = joinText(existingFinal, finals.joined(separator: " "))
        let commitSamples = Int(lastFinalEndMs / 1000 * sampleRate)
        return StitchResult(
            finalText: mergedFinal,
            partialText: provisionals.joined(separator: " "),
            commitSamples: commitSamples)
    }

    nonisolated static func rms(_ samples: [Float]) -> Float {
        guard samples.count > 0 else { return 0 }
        var sum: Float = 0
        for v in samples { sum += v * v }
        return sqrt(sum / Float(samples.count))
    }

    nonisolated static func joinText(_ a: String, _ b: String) -> String {
        let left = a.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = b.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (left.isEmpty, right.isEmpty) {
        case (true, true): return ""
        case (true, false): return right
        case (false, true): return left
        case (false, false): return left + " " + right
        }
    }
}
