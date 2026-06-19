import AppKit

/// A countdown timer with a Pomodoro mode (focus → break cycles). Drives the
/// collapsed-notch live activity and the Timer tab.
@MainActor
final class TimerEngine: ObservableObject {
    enum Phase: Equatable {
        case focus, shortBreak, longBreak

        var title: String {
            switch self {
            case .focus: return "Focus"
            case .shortBreak: return "Short Break"
            case .longBreak: return "Long Break"
            }
        }
        var isBreak: Bool { self != .focus }
        var symbol: String { isBreak ? "cup.and.saucer.fill" : "brain.head.profile" }
    }

    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var total: TimeInterval = 0
    @Published private(set) var phase: Phase = .focus
    @Published private(set) var isPomodoro = false
    @Published private(set) var completedFocusSessions = 0

    /// Fired when a phase finishes (symbol, message) — wired to a notch peek.
    var onActivity: ((String, String) -> Void)?

    // Pomodoro durations (minutes).
    private let focusMinutes = 25
    private let shortBreakMinutes = 5
    private let longBreakMinutes = 15
    private let sessionsBeforeLongBreak = 4

    private var ticker: Timer?

    var progress: Double { total > 0 ? min(1, 1 - remaining / total) : 0 }

    var remainingString: String {
        let t = max(0, Int(ceil(remaining)))
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    // MARK: Controls

    func startCustom(minutes: Int) {
        isPomodoro = false
        phase = .focus
        begin(Double(minutes) * 60)
    }

    func startPomodoro() {
        isPomodoro = true
        phase = .focus
        completedFocusSessions = 0
        begin(Double(focusMinutes) * 60)
    }

    func toggle() { isPaused ? resume() : pause() }

    func pause() {
        guard isRunning, !isPaused else { return }
        isPaused = true
        ticker?.invalidate()
    }

    func resume() {
        guard isRunning, isPaused else { return }
        isPaused = false
        startTicker()
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        isRunning = false
        isPaused = false
        remaining = 0
        total = 0
    }

    /// Skip to the next phase (Pomodoro) without the completion chime.
    func skip() {
        guard isRunning else { return }
        advance(announce: false)
    }

    // MARK: Internals

    private func begin(_ duration: TimeInterval) {
        total = duration
        remaining = duration
        isRunning = true
        isPaused = false
        startTicker()
    }

    private func startTicker() {
        ticker?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        guard isRunning, !isPaused else { return }
        remaining = max(0, remaining - 0.25)
        if remaining <= 0 {
            NSSound(named: "Glass")?.play()
            advance(announce: true)
        }
    }

    private func advance(announce: Bool) {
        ticker?.invalidate()
        guard isPomodoro else {
            if announce { onActivity?("timer", "Time's up!") }
            stop()
            return
        }
        if phase == .focus {
            completedFocusSessions += 1
            let long = completedFocusSessions % sessionsBeforeLongBreak == 0
            phase = long ? .longBreak : .shortBreak
            if announce { onActivity?(phase.symbol, long ? "Long break" : "Break time") }
            begin(Double((long ? longBreakMinutes : shortBreakMinutes)) * 60)
        } else {
            phase = .focus
            if announce { onActivity?(phase.symbol, "Back to focus") }
            begin(Double(focusMinutes) * 60)
        }
    }
}
