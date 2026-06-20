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

/// The Timer tab: a Pomodoro hero + quick-timer grid when idle, or a big
/// countdown ring with controls (and Pomodoro cycle dots) while running.
struct TimerTab: View {
    @ObservedObject var timer: TimerEngine

    private let quickPresets = [5, 15, 25, 45]
    private var focusColor: Color { TimerEngine.Phase.focus.color }

    var body: some View {
        Group {
            if timer.isRunning {
                runningView
            } else {
                idleView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: timer.isRunning)
    }

    // MARK: Idle

    private var idleView: some View {
        HStack(spacing: 22) {
            pomodoroStarter
                .frame(maxWidth: .infinity)

            Rectangle()
                .fill(.white.opacity(0.07))
                .frame(width: 1)
                .padding(.vertical, 6)

            quickTimer
                .frame(maxWidth: .infinity)
        }
        .transition(.blurFade)
    }

    /// A ring with a play button — tap to start a Pomodoro. Echoes the running
    /// ring so idle and active states share one visual language.
    private var pomodoroStarter: some View {
        Button { timer.startPomodoro() } label: {
            VStack(spacing: 11) {
                ZStack {
                    Circle()
                        .stroke(focusColor.opacity(0.18), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: 0.28)
                        .stroke(focusColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "play.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                        .offset(x: 1)
                }
                .frame(width: 78, height: 78)

                VStack(spacing: 2) {
                    Text("Pomodoro")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("25 min focus · 5 min break")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    private var quickTimer: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Quick Timer")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.4))
                .padding(.leading, 2)

            ForEach(quickPresets, id: \.self) { minutes in
                Button { timer.startCustom(minutes: minutes) } label: {
                    HStack(spacing: 11) {
                        Image(systemName: "timer")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(focusColor)
                            .frame(width: 16)
                        Text("\(minutes) min")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                        Spacer(minLength: 0)
                        Image(systemName: "play.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.25))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(.white.opacity(0.05))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(PressableStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Running

    private var runningView: some View {
        HStack(spacing: 34) {
            ZStack {
                TimerRing(progress: timer.progress, color: timer.phase.color, lineWidth: 6)
                    .frame(width: 120, height: 120)
                VStack(spacing: 3) {
                    Text(timer.remainingString)
                        .font(.system(size: 31, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text(phaseTagline)
                        .font(.system(size: 9.5, weight: .bold))
                        .tracking(0.6)
                        .textCase(.uppercase)
                        .foregroundStyle(timer.isPaused ? .white.opacity(0.45) : timer.phase.color)
                }
            }

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 7) {
                        Image(systemName: timer.phase.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(timer.phase.color)
                        Text(timer.isPomodoro ? timer.phase.title : "Timer")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    if timer.isPomodoro {
                        cycleDots
                    }
                }

                HStack(spacing: 12) {
                    Button { timer.toggle() } label: {
                        Image(systemName: timer.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 46, height: 46)
                            .background(Circle().fill(timer.phase.color))
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressableStyle())

                    iconButton("stop.fill") { timer.stop() }
                    if timer.isPomodoro {
                        iconButton("forward.end.fill") { timer.skip() }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .transition(.blurFade)
    }

    private var phaseTagline: String {
        if timer.isPaused { return "Paused" }
        return timer.isPomodoro ? timer.phase.title : "Focus"
    }

    /// Four dots tracking progress through the focus → long-break cycle.
    private var cycleDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .fill(i < completedInCycle ? timer.phase.color : .white.opacity(0.18))
                    .frame(width: 7, height: 7)
            }
            Text(sessionLabel)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.leading, 4)
        }
    }

    /// Focus sessions completed within the current 4-session cycle (4 on the long break).
    private var completedInCycle: Int {
        let n = timer.completedFocusSessions % 4
        return (n == 0 && timer.completedFocusSessions > 0) ? 4 : n
    }

    private var sessionLabel: String {
        if timer.phase.isBreak {
            return "Break"
        }
        return "Session \(timer.completedFocusSessions + 1)"
    }

    // MARK: Controls

    private func iconButton(_ symbol: String, primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(.white.opacity(primary ? 0.2 : 0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
    }
}
