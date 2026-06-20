import AppKit
import SwiftUI

/// A Raycast-style clipboard palette: grouped results on the left, a live detail
/// preview on the right, a persistent action bar at the bottom, and a ⌘K actions
/// menu. Type to filter, ↑/↓ to move, ⏎ to paste, Esc to dismiss.
struct QuickSearchView: View {
    @ObservedObject var store: ClipStore
    /// Paste the item into the previously-active app. `forcePlain` strips formatting.
    var onPaste: (ClipItem, Bool) -> Void
    var onClose: () -> Void

    @State private var query = ""
    @State private var results: [ClipItem] = []
    @State private var selection = 0
    @State private var searchTask: Task<Void, Never>?
    @State private var actionsShown = false
    @State private var actionSelection = 0
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                searchField
                Divider()
                HStack(spacing: 0) {
                    resultsList
                        .frame(width: 320)
                    Divider()
                    detailPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Divider()
                actionBar
            }

            if actionsShown {
                actionsMenu
                    .padding(.trailing, 10)
                    .padding(.bottom, 50)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottomTrailing)))
            }
        }
        .frame(width: 720, height: 480)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .onAppear {
            focused = true
            runSearch(query, debounce: false)
        }
    }

    // MARK: Search

    /// Debounced, off-main FTS search via the shared engine.
    private func runSearch(_ text: String, debounce: Bool) {
        searchTask?.cancel()
        searchTask = Task {
            if debounce {
                try? await Task.sleep(for: .milliseconds(60))
                if Task.isCancelled { return }
            }
            let found = await store.search(text)
            if Task.isCancelled { return }
            results = found
            clampSelection()
        }
    }

    /// Re-read results from the store after a mutation (pin/delete) without
    /// touching the query, preserving the user's place where possible.
    private func refresh() { runSearch(query, debounce: false) }

    // MARK: Grouping

    /// Results split into titled sections. Empty query → Pinned / Recent;
    /// an active query → a single Results section.
    private var groups: [(title: String, items: [ClipItem])] {
        if query.isEmpty {
            let pinned = results.filter(\.isPinned)
            let recent = results.filter { !$0.isPinned }
            var g: [(String, [ClipItem])] = []
            if !pinned.isEmpty { g.append(("Pinned", pinned)) }
            if !recent.isEmpty { g.append(("Recent", recent)) }
            return g
        }
        return results.isEmpty ? [] : [("Results", results)]
    }

    /// Flattened, section-ordered items — the basis for keyboard selection.
    private var flatItems: [ClipItem] { groups.flatMap(\.items) }

    private var selectedItem: ClipItem? {
        flatItems.indices.contains(selection) ? flatItems[selection] : nil
    }

    // MARK: Search field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search clipboard…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .focused($focused)
                .onKeyPress(phases: .down) { handleKey($0) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .onChange(of: query) { _, newValue in
            selection = 0
            runSearch(newValue, debounce: true)
        }
    }

    // MARK: Results list

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if flatItems.isEmpty {
                    Text(query.isEmpty ? "No clips yet" : "No Results")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(groups, id: \.title) { group in
                            Text(group.title.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 14)
                                .padding(.top, 10)
                                .padding(.bottom, 2)
                            ForEach(group.items) { item in
                                let index = flatItems.firstIndex { $0.id == item.id } ?? 0
                                QuickSearchRow(item: item, selected: index == selection)
                                    .id(index)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selection = index; activatePrimary() }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }
            .onChange(of: selection) { _, new in
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(new, anchor: .center) }
            }
        }
    }

    // MARK: Detail pane

    @ViewBuilder
    private var detailPane: some View {
        if let item = selectedItem {
            VStack(alignment: .leading, spacing: 14) {
                ClipPreview(item: item, compact: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(maxHeight: 230)
                Divider()
                VStack(spacing: 8) {
                    ForEach(metadata(for: item), id: \.0) { row in
                        metaRow(row.0, row.1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Color.clear
        }
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing).lineLimit(2)
        }
        .font(.system(size: 12))
    }

    private func metadata(for item: ClipItem) -> [(String, String)] {
        var rows: [(String, String)] = [("Type", item.kind.typeName.capitalized)]
        switch item.kind {
        case .text(let s):
            rows.append(("Characters", "\(s.count)"))
        case .link(let url):
            if let host = url.host() { rows.append(("Host", host)) }
        case .image(_, _, let w, let h):
            rows.append(("Dimensions", "\(w) × \(h)"))
        case .file(_, let path, _):
            rows.append(("Path", path))
        default:
            break
        }
        if let app = item.sourceAppName { rows.append(("Source", app)) }
        rows.append(("Copied", item.timestamp.formatted(.relative(presentation: .numeric))))
        return rows
    }

    // MARK: Action bar

    private var actionBar: some View {
        HStack(spacing: 0) {
            if let item = selectedItem, let primary = actions(for: item).first {
                Button(action: activatePrimary) {
                    HStack(spacing: 6) {
                        Image(systemName: primary.symbol)
                        Text(primary.title)
                        KeyChip(primary.shortcut)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button { toggleActions() } label: {
                HStack(spacing: 6) {
                    Text("Actions")
                    KeyChip("⌘K")
                }
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: 40)
    }

    // MARK: Actions menu (⌘K)

    @ViewBuilder
    private var actionsMenu: some View {
        if let item = selectedItem {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(actions(for: item).enumerated()), id: \.element.id) { index, action in
                    Button { run(action) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: action.symbol).frame(width: 18)
                            Text(action.title)
                            Spacer(minLength: 24)
                            Text(action.shortcut).foregroundStyle(.secondary)
                        }
                        .font(.system(size: 13))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(width: 260, alignment: .leading)
                        .background(index == actionSelection ? Color.accentColor : .clear,
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .foregroundStyle(index == actionSelection ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
        }
    }

    // MARK: Actions model

    private struct PaletteAction: Identifiable {
        let id = UUID()
        let title: String
        let symbol: String
        let shortcut: String
        let perform: () -> Void
    }

    private func actions(for item: ClipItem) -> [PaletteAction] {
        var list: [PaletteAction] = [
            PaletteAction(title: "Paste", symbol: "doc.on.clipboard", shortcut: "⏎") {
                onPaste(item, false)
            }
        ]
        if item.richRTF != nil {
            list.append(PaletteAction(title: "Paste as Plain Text", symbol: "textformat", shortcut: "⇧⌘V") {
                onPaste(item, true)
            })
        }
        list.append(PaletteAction(title: "Copy", symbol: "square.on.square", shortcut: "⌘C") {
            ClipboardWriter.copy(item)
            onClose()
        })
        if case .link(let url) = item.kind {
            list.append(PaletteAction(title: "Open Link", symbol: "safari", shortcut: "⌘O") {
                NSWorkspace.shared.open(url)
                onClose()
            })
        }
        list.append(PaletteAction(title: item.isPinned ? "Unpin" : "Pin",
                                  symbol: item.isPinned ? "pin.slash" : "pin", shortcut: "⌘P") {
            store.setPinned(!item.isPinned, for: item.id)
            refresh()
        })
        list.append(PaletteAction(title: "Delete", symbol: "trash", shortcut: "⌘⌫") {
            store.remove(item.id)
            refresh()
        })
        return list
    }

    private func run(_ action: PaletteAction) {
        actionsShown = false
        action.perform()
    }

    private func activatePrimary() {
        guard let item = selectedItem else { return }
        actions(for: item).first?.perform()
    }

    private func toggleActions() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
            actionsShown.toggle()
            actionSelection = 0
        }
    }

    // MARK: Keyboard

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        let cmd = press.modifiers.contains(.command)
        let shift = press.modifiers.contains(.shift)

        // Menu mode: arrows/⏎ drive the action list; Esc/⌘K close it.
        if actionsShown {
            switch press.key {
            case .downArrow: moveAction(1); return .handled
            case .upArrow: moveAction(-1); return .handled
            case .return:
                if let item = selectedItem { run(actions(for: item)[actionSelection]) }
                return .handled
            case .escape: toggleActions(); return .handled
            default:
                if cmd, press.characters == "k" { toggleActions(); return .handled }
                return .ignored
            }
        }

        switch press.key {
        case .downArrow: move(1); return .handled
        case .upArrow: move(-1); return .handled
        case .escape: onClose(); return .handled
        case .return: activatePrimary(); return .handled
        case .delete where cmd:
            runShortcut("⌘⌫"); return .handled
        default: break
        }

        if cmd {
            switch press.characters.lowercased() {
            case "k": toggleActions(); return .handled
            case "c": runShortcut("⌘C"); return .handled
            case "p": runShortcut("⌘P"); return .handled
            case "o": runShortcut("⌘O"); return .handled
            case "v" where shift: runShortcut("⇧⌘V"); return .handled
            default: break
            }
        }
        return .ignored
    }

    /// Fire the action whose displayed shortcut matches (so the ⌘K labels and the
    /// direct keys stay in sync from a single source of truth).
    private func runShortcut(_ shortcut: String) {
        guard let item = selectedItem,
              let action = actions(for: item).first(where: { $0.shortcut == shortcut })
        else { return }
        action.perform()
    }

    private func move(_ delta: Int) {
        guard !flatItems.isEmpty else { return }
        selection = min(max(0, selection + delta), flatItems.count - 1)
    }

    private func moveAction(_ delta: Int) {
        guard let item = selectedItem else { return }
        let count = actions(for: item).count
        actionSelection = min(max(0, actionSelection + delta), count - 1)
    }

    private func clampSelection() {
        if selection >= flatItems.count { selection = max(0, flatItems.count - 1) }
    }
}

/// A small keycap chip for the action bar / hints.
private struct KeyChip: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

private struct QuickSearchRow: View {
    let item: ClipItem
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 20)
                .foregroundStyle(selected ? .white : .secondary)
            Text(item.kind.previewText.replacingOccurrences(of: "\n", with: " "))
                .lineLimit(1)
                .foregroundStyle(selected ? .white : .primary)
            Spacer()
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(selected ? .white.opacity(0.8) : .secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(selected ? Color.accentColor : .clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var symbol: String {
        switch item.kind {
        case .text: return "textformat"
        case .link: return "link"
        case .color: return "paintpalette"
        case .image: return "photo"
        case .file: return "doc"
        case .locked: return "lock.fill"
        }
    }
}
