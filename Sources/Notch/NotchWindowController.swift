import AppKit
import SwiftUI
import Combine

/// Creates the notch panel, positions it under the hardware notch, and keeps
/// the click-through hit region in sync with the expand/collapse state.
@MainActor
final class NotchWindowController {
    private var panel: NotchPanel?
    private var container: NotchContainerView?
    private let model: NotchViewModel
    private let registry: ModuleRegistry
    private let music: MusicManager
    private let timer: TimerEngine
    private var hoverTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(registry: ModuleRegistry, music: MusicManager, timer: TimerEngine) {
        self.model = NotchViewModel(metrics: .current())
        self.registry = registry
        self.music = music
        self.timer = timer
    }

    func show() {
        let panel = NotchPanel(contentRect: .zero)

        let container = NotchContainerView()
        container.interactiveRectProvider = { [weak model] in
            model?.interactiveRect ?? .zero
        }

        let hosting = FirstMouseHostingView(rootView: NotchRootView(model: model, registry: registry, music: music, timer: timer))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting)
        panel.contentView = container

        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        self.panel = panel
        self.container = container

        positionPanel()
        panel.orderFrontRegardless()

        startHoverTracking()

        // Drive the idle media-flank state from the music player.
        music.$hasActivePlayer
            .removeDuplicates()
            .sink { [weak self] active in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    self?.model.isMediaActive = active
                }
            }
            .store(in: &cancellables)

        // Drive the collapsed live-timer flank from the running countdown.
        timer.$isRunning
            .removeDuplicates()
            .sink { [weak self] running in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    self?.model.isTimerActive = running
                }
            }
            .store(in: &cancellables)

        // Announce phase completions ("Break time", "Time's up") in the notch.
        timer.onActivity = { [weak self] symbol, text in
            self?.model.showMessage(symbol: symbol, text: text)
        }
    }

    // MARK: Hover via cursor polling
    //
    // SwiftUI's `.onHover` and global event monitors are both unreliable
    // through a non-activating panel, so we poll the cursor location and drive
    // expand/collapse from it. A short interval keeps it responsive and cheap.

    private func startHoverTracking() {
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.evaluateHover()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
        evaluateHover()
    }

    private func evaluateHover() {
        let point = NSEvent.mouseLocation  // global, bottom-left origin
        let target = notchScreenRect(expanded: model.isExpanded)
        model.setHover(target.contains(point))
    }

    /// The notch rect in global screen coordinates for the given state.
    private func notchScreenRect(expanded: Bool) -> CGRect {
        let size = expanded ? model.expandedSize : model.collapsedSize
        let screen = model.metrics.screenFrame
        return CGRect(
            x: screen.midX - size.width / 2,
            y: screen.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    deinit {
        hoverTimer?.invalidate()
    }

    /// Toggle the notch open/closed (from the status bar item or hotkey).
    func toggle() {
        model.toggleManually()
    }

    /// Briefly peek a freshly captured clip in the collapsed notch.
    func peek(_ item: ClipItem) {
        model.showClipPeek(item)
    }

    /// Show a system HUD (volume, brightness) in the collapsed notch.
    func showHUD(symbol: String, value: Double) {
        model.showHUD(symbol: symbol, value: value)
    }

    /// Announce a short message in the collapsed notch (charging, Low Power, …).
    func showMessage(symbol: String, text: String) {
        model.showMessage(symbol: symbol, text: text)
    }

    /// Re-reads screen metrics and repositions. Call on screen changes.
    func relayout() {
        model.metrics = .current()
        positionPanel()
    }

    private func positionPanel() {
        guard let panel else { return }
        let size = model.windowSize
        let screen = model.metrics.screenFrame
        let origin = CGPoint(
            x: screen.midX - size.width / 2,
            y: screen.maxY - size.height
        )
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
    }
}
