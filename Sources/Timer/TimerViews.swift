import SwiftUI

private extension TimerEngine.Phase {
    var color: Color { isBreak ? Color(red: 0.30, green: 0.82, blue: 0.50) : Color(red: 1.0, green: 0.58, blue: 0.18) }
}

/// A circular countdown progress indicator.
struct TimerRing: View {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: progress)
        }
    }
}

/// Countdown ring on the left, remaining time on the right, flanking the camera
/// while the notch is collapsed — the live timer activity.
struct CollapsedTimerView: View {
    @ObservedObject var timer: TimerEngine

    var body: some View {
        HStack(spacing: 0) {
            TimerRing(progress: timer.progress, color: timer.phase.color, lineWidth: 2.5)
                .frame(width: 18, height: 18)
                .opacity(timer.isPaused ? 0.5 : 1)
                .padding(.leading, 16)

            Spacer(minLength: 0)

            Text(timer.remainingString)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .opacity(timer.isPaused ? 0.55 : 1)
                .padding(.trailing, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A symbol + short message shown in the notch peek (e.g. "Break time").
struct MessagePeekView: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 22)
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The Timer tab: idle presets, or running controls with a big countdown ring.
struct TimerTab: View {
    @ObservedObject var timer: TimerEngine

    var body: some View {
        Group {
            if timer.isRunning {
                runningView
            } else {
                idleView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: timer.isRunning)
    }

    // MARK: Running

    private var runningView: some View {
        HStack(spacing: 24) {
            ZStack {
                TimerRing(progress: timer.progress, color: timer.phase.color, lineWidth: 5)
                    .frame(width: 92, height: 92)
                VStack(spacing: 1) {
                    Text(timer.remainingString)
                        .font(.system(size: 23, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    if timer.isPaused {
                        Text("Paused")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                            .textCase(.uppercase)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(timer.isPomodoro ? timer.phase.title : "Timer")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    if timer.isPomodoro {
                        Text(sessionLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }

                HStack(spacing: 10) {
                    iconButton(timer.isPaused ? "play.fill" : "pause.fill", primary: true) {
                        timer.toggle()
                    }
                    iconButton("stop.fill") { timer.stop() }
                    if timer.isPomodoro {
                        iconButton("forward.end.fill") { timer.skip() }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 30)
        .transition(.blurFade)
    }

    private var sessionLabel: String {
        let n = timer.completedFocusSessions
        if timer.phase.isBreak {
            return "After \(n) focus session\(n == 1 ? "" : "s")"
        }
        return "Session \(n + 1)"
    }

    // MARK: Idle

    private let quickPresets = [5, 15, 25, 45]

    private var idleView: some View {
        VStack(spacing: 14) {
            Button { timer.startPomodoro() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 16, weight: .semibold))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Pomodoro")
                            .font(.system(size: 13.5, weight: .semibold))
                        Text("25 min focus · 5 min break")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(
                    Capsule().fill(TimerEngine.Phase.focus.color.opacity(0.22))
                )
                .overlay(Capsule().strokeBorder(TimerEngine.Phase.focus.color.opacity(0.5), lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle())

            HStack(spacing: 9) {
                ForEach(quickPresets, id: \.self) { minutes in
                    Button { timer.startCustom(minutes: minutes) } label: {
                        Text("\(minutes)m")
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 32)
                            .background(Capsule().fill(.white.opacity(0.1)))
                            .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
        .transition(.blurFade)
    }

    // MARK: Controls

    private func iconButton(_ symbol: String, primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(.white.opacity(primary ? 0.2 : 0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
    }
}
