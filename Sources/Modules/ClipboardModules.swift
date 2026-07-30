import SwiftUI

/// The Clipboard tab: All / Pinned filter above the card strip. Long-press a card
/// to enter multi-select (drag several clips out together).
struct ClipStripTab: View {
    @ObservedObject var store: ClipStore
    var dismiss: () -> Void

    @State private var pinnedOnly = false
    @State private var selectionMode = false
    @State private var selectedIDs: Set<UUID> = []
    @Namespace private var seg

    private static let recentLimit = 20

    private var items: [ClipItem] {
        if pinnedOnly { return store.items.filter { $0.isPinned } }
        let recent = store.items.prefix(Self.recentLimit)
        let olderPinned = store.items.dropFirst(Self.recentLimit).filter { $0.isPinned }
        return Array(recent) + Array(olderPinned)
    }

    private var selectedItems: [ClipItem] {
        items.filter { selectedIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 8) {
            filterBar
                .padding(.horizontal, 28)

            CardStripView(
                items: items,
                emptyTitle: pinnedOnly ? "Pin clips to keep them here" : "No clips yet — copy something",
                emptySymbol: pinnedOnly ? "pin" : "tray",
                onPick: { _ in
                    if !selectionMode { dismiss() }
                },
                onTogglePin: { store.setPinned(!$0.isPinned, for: $0.id) },
                onDelete: { store.remove($0.id) },
                selectionMode: selectionMode,
                selectedIDs: $selectedIDs,
                onEnterSelection: { id in
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        selectionMode = true
                        selectedIDs = [id]
                    }
                    Haptics.tap()
                }
            )
        }
        .onChange(of: pinnedOnly) { _, _ in
            selectedIDs = selectedIDs.intersection(Set(items.map(\.id)))
        }
    }

    private var filterBar: some View {
        HStack(spacing: 2) {
            if selectionMode {
                selectionBar
            } else {
                segment("All", selected: !pinnedOnly) { pinnedOnly = false }
                segment("Pinned", selected: pinnedOnly) { pinnedOnly = true }
                Spacer(minLength: 0)
            }
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 8) {
            Button {
                exitSelection()
            } label: {
                Text("Done")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.white.opacity(0.14)))
            }
            .buttonStyle(.plain)

            Text(selectedIDs.isEmpty ? "Select clips" : "\(selectedIDs.count) selected")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .contentTransition(.numericText(value: Double(selectedIDs.count)))

            Spacer(minLength: 8)

            if !selectedIDs.isEmpty {
                chromeButton("Paste", systemImage: "doc.on.clipboard") {
                    pasteSelected()
                }
                if PasteService.canCombine(selectedItems) {
                    chromeButton("Combine", systemImage: "text.append") {
                        combineSelected()
                    }
                }
                chromeButton("Copy", systemImage: "doc.on.doc") {
                    ClipDragExporter.copyToPasteboard(selectedItems)
                    Haptics.tap()
                }
                chromeButton("Delete", systemImage: "trash", destructive: true) {
                    deleteSelected()
                }
            } else {
                Text("Tap · drag out")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
    }

    private func exitSelection() {
        withAnimation(Motion.snappy) {
            selectionMode = false
            selectedIDs.removeAll()
        }
    }

    /// Multi-file paste into the frontmost app (great for several screenshots).
    private func pasteSelected() {
        let batch = selectedItems
        guard !batch.isEmpty else { return }
        Haptics.tap()
        _ = PasteService.pasteItems(batch)
        exitSelection()
        dismiss()
    }

    /// Join text-like clips into one plain-text paste.
    private func combineSelected() {
        let batch = selectedItems
        guard PasteService.canCombine(batch) else { return }
        Haptics.tap()
        _ = PasteService.pasteCombined(batch)
        exitSelection()
        dismiss()
    }

    /// Staggered Apple-like dismiss: cards shrink/fade, then neighbors close gaps.
    private func deleteSelected() {
        let ordered = selectedItems
        guard !ordered.isEmpty else { return }
        Haptics.tap()
        let remainingAfter = items.count - ordered.count

        Task { @MainActor in
            for (i, item) in ordered.enumerated() {
                withAnimation(ClipStripAnimation.delete) {
                    selectedIDs.remove(item.id)
                    store.remove(item.id)
                }
                if i < ordered.count - 1 {
                    try? await Task.sleep(for: .milliseconds(45))
                }
            }
            if remainingAfter <= 0 {
                try? await Task.sleep(for: .milliseconds(200))
                exitSelection()
            }
        }
    }

    private func chromeButton(
        _ title: String,
        systemImage: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(destructive ? Color(red: 1, green: 0.45, blue: 0.4) : .white.opacity(0.75))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(destructive ? Color.red.opacity(0.18) : .white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }

    private func segment(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { action() }
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(selected ? .white : .white.opacity(0.45))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background {
                    if selected {
                        Capsule().fill(.white.opacity(0.14))
                            .matchedGeometryEffect(id: "segpill", in: seg)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

@MainActor
final class ClipboardModule: NotchModule {
    let id = "clipboard"
    let title = "Clipboard"
    let icon = "doc.on.clipboard.fill"

    var preferredExpandedHeight: CGFloat { 210 }

    private let store: ClipStore
    init(store: ClipStore) { self.store = store }

    func makeContent(_ context: ModuleContext) -> AnyView {
        AnyView(ClipStripTab(store: store, dismiss: context.dismiss))
    }
}
