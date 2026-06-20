import SwiftUI
import UniformTypeIdentifiers

/// The SwiftUI content hosted inside the notch panel. Top-aligned so the shape
/// hangs from the very top edge of the screen.
struct NotchRootView: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject var registry: ModuleRegistry
    /// Kept directly (not via a module) because it drives the *collapsed* idle
    /// media flank and the tab indicator.
    @ObservedObject var music: MusicManager
    /// Drives the *collapsed* live countdown flank.
    @ObservedObject var timer: TimerEngine
    /// Drives the *collapsed* meeting countdown flank.
    @ObservedObject var calendar: CalendarManager

    @State private var dropTargeted = false

    private func routeDropToModule() {
        guard let drop = registry.dropModule, registry.selectedID != drop.id else { return }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            registry.select(drop.id)
        }
    }

    /// Device-pure black so the panel is indistinguishable from the hardware
    /// notch / bezel. Any tint or translucency makes the camera housing stand
    /// out against it.
    private static let panelBlack = Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1)

    var body: some View {
        VStack(spacing: 0) {
            notch
            Spacer(minLength: 0)
        }
        .frame(
            width: model.windowSize.width,
            height: model.windowSize.height,
            alignment: .top
        )
        .ignoresSafeArea()
        .onChange(of: registry.selectedID) { _, _ in
            model.setExpandedHeight(registry.selected?.preferredExpandedHeight ?? 180)
        }
    }

    private var notchShape: NotchShape {
        NotchShape(
            topCornerRadius: model.isExpanded ? 16 : 6,
            bottomCornerRadius: model.isExpanded ? 18 : 14
        )
    }

    private var notch: some View {
        notchShape
            .fill(Self.panelBlack)
            // Clip content to the notch silhouette so cards never spill past the
            // rounded corners.
            .overlay(alignment: .top) { expandedContent.clipShape(notchShape) }
            .frame(
                width: model.currentNotchSize.width,
                height: model.currentNotchSize.height
            )
    }

    @ViewBuilder
    private var expandedContent: some View {
        if model.isExpanded {
            VStack(alignment: .leading, spacing: 0) {
                // Tabs sit in the top-left "ear", beside the camera.
                NotchTabBar(modules: registry.modules, selectedID: $registry.selectedID)
                    .frame(height: 26)
                    .padding(.top, 7)
                // Full-width content must clear the camera notch, then fill the
                // rest of the height (top-aligned).
                tabContent
                    .padding(.top, max(10, model.metrics.notchSize.height - 29))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.bottom, 12)
            // A drag anywhere over the open notch routes to the drop module (Shelf).
            .overlay {
                if dropTargeted {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.45), style: StrokeStyle(lineWidth: 2, dash: [7]))
                        .padding(7)
                }
            }
            .onDrop(of: [.fileURL, .url, .image, .plainText, .text], isTargeted: $dropTargeted) { providers in
                registry.dropModule?.handleDrop(providers)
                routeDropToModule()
                return true
            }
            .onChange(of: dropTargeted) { _, targeted in
                if targeted { routeDropToModule() }
            }
            .transition(.blurFade)
        } else if model.isPeeking, let peek = model.peekContent {
            peekView(peek)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, model.metrics.notchSize.height)
                .padding(.bottom, 8)
                // Pop from the top so the peek reads as emerging from the notch.
                .transition(.scale(scale: 0.86, anchor: .top).combined(with: .opacity))
        } else if model.isTimerActive {
            // Idle: countdown ring + remaining time flanking the camera.
            CollapsedTimerView(timer: timer)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
        } else if model.isCalendarActive {
            // Idle: calendar dot + meeting countdown flanking the camera.
            CollapsedCalendarView(calendar: calendar)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
        } else if model.isMediaActive {
            // Idle: album art + equalizer flanking the camera (no top padding —
            // this occupies the notch-height region itself).
            CollapsedMediaView(music: music)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        if let module = registry.selected {
            module.makeContent(ModuleContext(dismiss: { model.dismiss() }))
        }
    }

    @ViewBuilder
    private func peekView(_ peek: NotchViewModel.PeekContent) -> some View {
        switch peek {
        case .clip(let item):
            ClipPeekView(item: item)
        case .hud(let symbol, let value):
            HUDPeekView(symbol: symbol, value: value)
        case .message(let symbol, let text):
            MessagePeekView(symbol: symbol, text: text)
        case .notification(let item):
            NotificationPeekView(item: item)
        }
    }
}
