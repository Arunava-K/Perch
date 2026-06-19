import SwiftUI
import Defaults

/// Owns the expand/collapse state and derives the geometry the view and the
/// window controller both depend on.
@MainActor
final class NotchViewModel: ObservableObject {
    @Published private(set) var isExpanded = false
    /// When pinned (e.g. via the toggle hotkey or a click) the notch stays open
    /// regardless of cursor position until explicitly closed.
    @Published private(set) var isPinnedOpen = false
    /// A transient "sneak peek": the collapsed notch briefly bulges to show a
    /// just-captured clip or a system HUD (volume, etc.).
    @Published private(set) var isPeeking = false
    @Published private(set) var peekContent: PeekContent?

    enum PeekContent: Equatable {
        case clip(ClipItem)
        case hud(symbol: String, value: Double)  // value 0...1
        case message(symbol: String, text: String)
        case notification(NotificationItem)
    }
    /// True while a music player is active — the idle notch shows flanking media.
    @Published var isMediaActive = false
    /// True while a countdown is running — the collapsed notch shows a live timer.
    @Published var isTimerActive = false
    @Published var metrics: NotchMetrics

    /// Delay before collapsing after the cursor leaves, to avoid flicker when
    /// the pointer briefly crosses the rounded corners.
    private let collapseDelay: Duration = .milliseconds(180)
    private var collapseTask: Task<Void, Never>?
    private var peekTask: Task<Void, Never>?

    /// Lower damping gives a subtle overshoot so the notch visibly springs open
    /// — it reads as content bulging *out of* the hardware notch.
    private let openAnimation = Animation.spring(response: 0.40, dampingFraction: 0.68, blendDuration: 0.1)
    /// Close is quicker and fully damped so it tucks away cleanly (no bounce).
    private let closeAnimation = Animation.spring(response: 0.30, dampingFraction: 0.92)
    /// Peek pop: a touch springier than open for a lively "emerge" feel.
    private let peekAnimation = Animation.spring(response: 0.34, dampingFraction: 0.66)

    init(metrics: NotchMetrics) {
        self.metrics = metrics
    }

    // MARK: Geometry

    /// Size of the notch shape when collapsed — hugs the hardware notch.
    var collapsedSize: CGSize { metrics.notchSize }

    /// Standard expanded height — constant across tabs for a stable UX.
    private let maxExpandedHeight: CGFloat = 180
    /// Slightly wider than before so the tab bar fits in the left "ear" beside
    /// the camera, letting the tabs pin to the very top.
    private var expandedWidth: CGFloat { max(metrics.notchSize.width + 520, 740) }

    /// Size of the notch shape when expanded — same height for every tab.
    var expandedSize: CGSize {
        CGSize(width: expandedWidth, height: maxExpandedHeight)
    }

    /// Size of the notch during a sneak-peek — a compact pill below the camera.
    var peekSize: CGSize {
        CGSize(width: max(metrics.notchSize.width + 200, 380), height: metrics.notchSize.height + 46)
    }

    /// Notifications get a roomier peek for the title + body lines.
    var notificationPeekSize: CGSize {
        CGSize(width: max(metrics.notchSize.width + 340, 480), height: metrics.notchSize.height + 66)
    }

    /// Idle media size — album art + equalizer flanking the camera, at notch height.
    var collapsedMediaSize: CGSize {
        CGSize(width: metrics.notchSize.width + 96, height: metrics.notchSize.height)
    }

    /// Live-timer size — countdown ring + remaining time flanking the camera.
    var timerSize: CGSize {
        CGSize(width: metrics.notchSize.width + 118, height: metrics.notchSize.height)
    }

    /// The window is always sized to the largest state so content can animate
    /// inside it without resizing the window itself.
    var windowSize: CGSize {
        CGSize(width: expandedWidth, height: maxExpandedHeight)
    }

    var currentNotchSize: CGSize {
        if isExpanded { return expandedSize }
        if isPeeking {
            if case .notification = peekContent { return notificationPeekSize }
            return peekSize
        }
        if isTimerActive { return timerSize }
        if isMediaActive { return collapsedMediaSize }
        return collapsedSize
    }

    /// The interactive (hit-testable) rect in window coordinates (bottom-left
    /// origin). Outside this rect the window is click-through so it never
    /// blocks the menu bar.
    var interactiveRect: CGRect {
        let size = currentNotchSize
        let win = windowSize
        return CGRect(
            x: (win.width - size.width) / 2,
            y: win.height - size.height,
            width: size.width,
            height: size.height
        )
    }

    // MARK: Hover handling

    func setHover(_ hovering: Bool) {
        if hovering {
            collapseTask?.cancel()
            collapseTask = nil
            guard !isExpanded, Defaults[.openNotchOnHover] else { return }
            expand()
        } else {
            // Pinned-open notches ignore the cursor leaving.
            guard !isPinnedOpen else { return }
            scheduleCollapse()
        }
    }

    /// Dismiss the notch after a clip is picked (unpin + collapse).
    func dismiss() {
        isPinnedOpen = false
        collapse()
    }

    /// Manually toggle the notch (status-bar item or global hotkey). Pins it
    /// open so the hover poll won't immediately collapse it.
    func toggleManually() {
        if isPinnedOpen || isExpanded {
            isPinnedOpen = false
            collapse()
        } else {
            isPinnedOpen = true
            expand()
        }
    }

    // MARK: Live-activity queue (collapsed-notch peeks)

    /// One thing to surface in the collapsed notch.
    private struct LiveActivity {
        let content: PeekContent
        let duration: Int          // ms
        let priority: Int          // higher preempts lower
        let coalesceKey: String?   // same key updates in place instead of queuing
    }

    private var activityQueue: [LiveActivity] = []
    private var currentActivity: LiveActivity?

    /// Briefly show a just-captured clip in the collapsed notch.
    func showClipPeek(_ item: ClipItem) {
        post(LiveActivity(content: .clip(item), duration: 1600, priority: 0, coalesceKey: nil))
    }

    /// Show a system HUD (volume, etc.). HUDs coalesce (rapid changes update in
    /// place) and preempt clip peeks.
    func showHUD(symbol: String, value: Double) {
        post(LiveActivity(content: .hud(symbol: symbol, value: value),
                          duration: 1200, priority: 1, coalesceKey: "hud"))
    }

    /// Announce a short message in the collapsed notch (e.g. "Break time").
    func showMessage(symbol: String, text: String) {
        post(LiveActivity(content: .message(symbol: symbol, text: text),
                          duration: 2400, priority: 2, coalesceKey: "message"))
    }

    /// Mirror a macOS notification in the collapsed notch.
    func showNotification(_ item: NotificationItem) {
        post(LiveActivity(content: .notification(item),
                          duration: 4200, priority: 3, coalesceKey: nil))
    }

    private func post(_ activity: LiveActivity) {
        // A fully open notch doesn't peek.
        guard !isExpanded else { return }

        // Coalesce: a same-key activity replaces the current/pending one.
        if let key = activity.coalesceKey {
            if currentActivity?.coalesceKey == key {
                present(activity)
                return
            }
            activityQueue.removeAll { $0.coalesceKey == key }
        }

        if currentActivity == nil {
            present(activity)
        } else if activity.priority > (currentActivity?.priority ?? 0) {
            activityQueue.insert(currentActivity!, at: 0)  // requeue the preempted one
            present(activity)
        } else {
            activityQueue.append(activity)
        }
    }

    private func present(_ activity: LiveActivity) {
        currentActivity = activity
        peekContent = activity.content
        withAnimation(peekAnimation) { isPeeking = true }
        peekTask?.cancel()
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(activity.duration))
            guard let self, !Task.isCancelled, !self.isExpanded else { return }
            self.advanceQueue()
        }
    }

    private func advanceQueue() {
        if activityQueue.isEmpty {
            currentActivity = nil
            withAnimation(closeAnimation) { isPeeking = false }
            peekContent = nil
        } else {
            present(activityQueue.removeFirst())
        }
    }

    private func endPeek() {
        peekTask?.cancel()
        peekTask = nil
        activityQueue.removeAll()
        currentActivity = nil
        if isPeeking { isPeeking = false }
        peekContent = nil
    }

    private func expand() {
        collapseTask?.cancel()
        collapseTask = nil
        endPeek()
        guard !isExpanded else { return }
        Haptics.tap()
        withAnimation(openAnimation) { isExpanded = true }
    }

    private func collapse() {
        collapseTask?.cancel()
        collapseTask = nil
        guard isExpanded else { return }
        withAnimation(closeAnimation) { isExpanded = false }
    }

    private func scheduleCollapse() {
        // Nothing to collapse, or a collapse is already pending. Returning early
        // is essential: the hover poll calls setHover(false) every tick, and
        // restarting the task each time would reset the debounce forever.
        guard isExpanded, collapseTask == nil else { return }
        collapseTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: collapseDelay)
            guard !Task.isCancelled, !self.isPinnedOpen else { return }
            withAnimation(self.closeAnimation) {
                self.isExpanded = false
            }
            self.collapseTask = nil
        }
    }
}
