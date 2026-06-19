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
    }
    /// True while a music player is active — the idle notch shows flanking media.
    @Published var isMediaActive = false
    @Published var metrics: NotchMetrics

    /// Delay before collapsing after the cursor leaves, to avoid flicker when
    /// the pointer briefly crosses the rounded corners.
    private let collapseDelay: Duration = .milliseconds(180)
    private var collapseTask: Task<Void, Never>?
    private var peekTask: Task<Void, Never>?

    private let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8)
    private let closeAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0)

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

    /// Idle media size — album art + equalizer flanking the camera, at notch height.
    var collapsedMediaSize: CGSize {
        CGSize(width: metrics.notchSize.width + 96, height: metrics.notchSize.height)
    }

    /// The window is always sized to the largest state so content can animate
    /// inside it without resizing the window itself.
    var windowSize: CGSize {
        CGSize(width: expandedWidth, height: maxExpandedHeight)
    }

    var currentNotchSize: CGSize {
        if isExpanded { return expandedSize }
        if isPeeking { return peekSize }
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

    // MARK: Sneak peek / HUD

    /// Briefly show a just-captured clip in the collapsed notch.
    func showClipPeek(_ item: ClipItem) {
        presentPeek(.clip(item), duration: 1600)
    }

    /// Briefly show a system HUD (e.g. volume) in the collapsed notch.
    func showHUD(symbol: String, value: Double) {
        presentPeek(.hud(symbol: symbol, value: value), duration: 1200)
    }

    private func presentPeek(_ content: PeekContent, duration: Int) {
        // A fully open notch doesn't need a peek.
        guard !isExpanded else { return }
        peekTask?.cancel()
        peekContent = content
        withAnimation(openAnimation) { isPeeking = true }
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(duration))
            guard let self, !Task.isCancelled, !self.isExpanded else { return }
            withAnimation(self.closeAnimation) { self.isPeeking = false }
            self.peekContent = nil
        }
    }

    private func endPeek() {
        peekTask?.cancel()
        peekTask = nil
        if isPeeking { isPeeking = false }
        peekContent = nil
    }

    private func expand() {
        collapseTask?.cancel()
        collapseTask = nil
        endPeek()
        guard !isExpanded else { return }
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
