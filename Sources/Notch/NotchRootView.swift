import SwiftUI
import UniformTypeIdentifiers

/// The SwiftUI content hosted inside the notch panel. Top-aligned so the shape
/// hangs from the very top edge of the screen.
struct NotchRootView: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject var store: ClipStore
    @ObservedObject var shelf: ShelfStore
    @ObservedObject var music: MusicManager

    @State private var dropTargeted = false

    private func switchToShelf() {
        guard model.selectedTab != .shelf else { return }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            model.selectedTab = .shelf
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
                NotchTabBar(selection: $model.selectedTab, musicActive: music.hasActivePlayer)
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
            // A drag anywhere over the open notch always targets the Shelf.
            .overlay {
                if dropTargeted {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.45), style: StrokeStyle(lineWidth: 2, dash: [7]))
                        .padding(7)
                }
            }
            .onDrop(of: [.fileURL, .url, .image, .plainText, .text], isTargeted: $dropTargeted) { providers in
                DropImporter.importProviders(providers, add: { shelf.add($0) })
                switchToShelf()
                return true
            }
            .onChange(of: dropTargeted) { _, targeted in
                if targeted { switchToShelf() }
            }
            .transition(.blurFade)
        } else if model.isPeeking, let peek = model.peekContent {
            peekView(peek)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, model.metrics.notchSize.height)
                .padding(.bottom, 8)
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
        switch model.selectedTab {
        case .clipboard:
            CardStripView(
                items: store.items,
                emptyTitle: "No clips yet — copy something",
                emptySymbol: "tray",
                onPick: { _ in model.dismiss() },
                onTogglePin: { store.setPinned(!$0.isPinned, for: $0.id) },
                onDelete: { store.remove($0.id) }
            )
        case .pinned:
            CardStripView(
                items: store.items.filter { $0.isPinned },
                emptyTitle: "Pin clips to keep them here",
                emptySymbol: "pin",
                onPick: { _ in model.dismiss() },
                onTogglePin: { store.setPinned(!$0.isPinned, for: $0.id) },
                onDelete: { store.remove($0.id) }
            )
        case .shelf:
            CardStripView(
                items: shelf.items,
                emptyTitle: "Drag files here to stage them",
                emptySymbol: "tray.and.arrow.down",
                onPick: { _ in model.dismiss() },
                onTogglePin: { _ in },
                onDelete: { shelf.remove($0.id) }
            )
        case .music:
            NowPlayingDetailView(music: music)
        }
    }

    @ViewBuilder
    private func peekView(_ peek: NotchViewModel.PeekContent) -> some View {
        switch peek {
        case .clip(let item):
            ClipPeekView(item: item)
        case .hud(let symbol, let value):
            HUDPeekView(symbol: symbol, value: value)
        }
    }
}
