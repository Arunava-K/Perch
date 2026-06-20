import SwiftUI

/// Timer / Pomodoro tab. The running countdown also surfaces as a live activity
/// in the collapsed notch (wired in the window controller, like music).
@MainActor
final class TimerModule: NotchModule {
    let id = "timer"
    let title = "Timer"
    let icon = "timer"

    let timer: TimerEngine

    init(timer: TimerEngine) { self.timer = timer }

    var indicator: Bool { timer.isRunning }

    /// Tall enough for the Pomodoro ring beside the quick-timer list.
    var preferredExpandedHeight: CGFloat { 230 }

    func makeContent(_ context: ModuleContext) -> AnyView {
        AnyView(TimerTab(timer: timer))
    }
}
