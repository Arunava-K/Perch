import SwiftUI

/// Live dictation pill in the collapsed notch, laid out like a peek (below the
/// camera line). Recording: breathing red dot + live waveform + elapsed time.
/// Transcribing: the waveform hands off to a quiet "Transcribing…" cadence.
/// Click anywhere on the pill to discard the take.
struct DictationLiveView: View {
    @ObservedObject var dictation: DictationManager

    /// Voice-memos red — reads as "recording" without shouting.
    static let tint = Color(red: 1.0, green: 0.31, blue: 0.27)

    var body: some View {
        HStack(spacing: 12) {
            dot
            if dictation.state == .recording {
                waveform
                elapsedTime
            } else {
                transcribingLabel
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { dictation.cancel() }
        .help(dictation.state == .recording
              ? "Click to discard · press the shortcut to finish"
              : "Transcribing…")
        .animation(.easeOut(duration: 0.2), value: dictation.state)
    }

    // MARK: Recording

    @ViewBuilder private var dot: some View {
        if dictation.state == .recording {
            BreathingDot()
        } else {
            Circle()
                .fill(.white.opacity(0.35))
                .frame(width: 7, height: 7)
        }
    }

    /// Per-bar weights give the bars a wave feel even for a single level value.
    private static let barWeights: [CGFloat] = [0.35, 0.6, 0.85, 1.0, 0.8, 0.55, 0.35]

    private var waveform: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<Self.barWeights.count, id: \.self) { i in
                Capsule(style: .continuous)
                    .fill(Self.tint.opacity(0.5 + 0.5 * dictation.level))
                    .frame(width: 3, height: barHeight(i))
            }
        }
        // Fast, interruptible springs so bars track speech rhythm.
        .animation(.spring(response: 0.16, dampingFraction: 0.62), value: dictation.level)
    }

    private func barHeight(_ i: Int) -> CGFloat {
        let base: CGFloat = 4
        let span: CGFloat = 15
        return base + span * CGFloat(dictation.level) * Self.barWeights[i]
    }

    /// Ticks via TimelineView — no owned timer, no retain cycle risk.
    private var elapsedTime: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(Self.elapsedString(from: dictation.startedAt, now: context.date))
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 38, alignment: .trailing)
                .contentTransition(.numericText())
        }
        .fixedSize()
    }

    static func elapsedString(from start: Date?, now: Date) -> String {
        guard let start else { return "0:00" }
        let secs = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", secs / 60, secs % 60)
    }

    // MARK: Transcribing

    private var transcribingLabel: some View {
        HStack(spacing: 7) {
            Text("Transcribing")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(.white.opacity([0.9, 0.55, 0.3][i]))
                        .frame(width: 2.5, height: 2.5)
                }
            }
        }
    }
}

/// Recording indicator: a red dot that gently breathes (glow + scale). Lives
/// only while recording, so the repeatForever animation can't leak past the
/// recording state.
private struct BreathingDot: View {
    @State private var up = false

    var body: some View {
        Circle()
            .fill(DictationLiveView.tint)
            .frame(width: 7, height: 7)
            .shadow(color: DictationLiveView.tint.opacity(0.75), radius: up ? 6 : 2.5)
            .scaleEffect(up ? 1.12 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    up = true
                }
            }
    }
}
