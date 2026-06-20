import AppKit
import SwiftUI

/// A Raycast-style command palette: grouped results on the left (app Commands +
/// clipboard), a live detail preview on the right, a persistent action bar, and
/// a ⌘K actions menu. Type to filter, ↑/↓ to move, ⏎ to run/paste, Esc to close.
struct QuickSearchView: View {
    @ObservedObject var store: ClipStore
    /// App commands shown in the Commands section.
    var commands: [PaletteCommand]
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

    /// A palette row is either a clipboard clip or an app command.
    enum Entry: Identifiable {
        case clip(ClipItem)
        case command(PaletteCommand)

        var id: String {
            switch self {
            case .clip(let c): return "clip-\(c.id)"
            case .command(let c): return "cmd-\(c.id)"
            }
        }
    }

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

    private var matchedCommands: [PaletteCommand] {
        query.isEmpty ? commands : commands.filter { $0.matches(query) }
    }

    /// Results split into titled sections. Idle → Pinned / Recent / Commands;
    /// an active query → matched Commands first, then Clipboard.
    private var groups: [(title: String, entries: [Entry])] {
        var g: [(String, [Entry])] = []
        if query.isEmpty {
            let pinned = results.filter(\.isPinned)
            let recent = results.filter { !$0.isPinned }
            if !pinned.isEmpty { g.append(("Pinned", pinned.map(Entry.clip))) }
            if !recent.isEmpty { g.append(("Recent", recent.map(Entry.clip))) }
            if !commands.isEmpty { g.append(("Commands", commands.map(Entry.command))) }
        } else {
            let cmds = matchedCommands
            if !cmds.isEmpty { g.append(("Commands", cmds.map(Entry.command))) }
            if !results.isEmpty { g.append(("Clipboard", results.map(Entry.clip))) }
        }
        return g
    }

    /// Flattened, section-ordered entries — the basis for keyboard selection.
    private var flatEntries: [Entry] { groups.flatMap(\.entries) }

    private var selectedEntry: Entry? {
        flatEntries.indices.contains(selection) ? flatEntries[selection] : nil
    }

    /// A header or an entry, numbered with its flat index in one pass so the
    /// rendered rows and keyboard selection always share the same numbering.
    private enum DisplayRow: Identifiable {
        case header(String)
        case entry(Int, Entry)

        var id: String {
            switch self {
            case .header(let title): return "h-\(title)"
            case .entry(_, let entry): return entry.id
            }
        }
    }

    private var displayRows: [DisplayRow] {
        var rows: [DisplayRow] = []
        var i = 0
        for group in groups {
            rows.append(.header(group.title))
            for entry in group.entries {
                rows.append(.entry(i, entry))
                i += 1
            }
        }
        return rows
    }

    // MARK: Search field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search clips and commands…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .focused($focused)
                // Targeted nav keys intercept reliably over the focused field;
                // the general handler covers ⌘-combos only (so typing still works).
                .onKeyPress(keys: [.upArrow, .downArrow, .return, .escape], phases: .down) { handleKey($0) }
                .onKeyPress(phases: .down) { press in
                    press.modifiers.contains(.command) ? handleKey(press) : .ignored
                }
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
                if flatEntries.isEmpty {
                    Text("No Results")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(displayRows) { row in
                            switch row {
                            case .header(let title):
                                Text(title.uppercased())
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14)
                                    .padding(.top, 10)
                                    .padding(.bottom, 2)
                            case .entry(let index, let entry):
                                PaletteRow(entry: entry, selected: index == selection)
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
        switch selectedEntry {
        case .clip(let item):
            clipDetail(item)
        case .command(let cmd):
            commandDetail(cmd)
        case nil:
            Color.clear
        }
    }

    private func clipDetail(_ item: ClipItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ClipPreview(item: item, compact: false, imageContentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: 230)
                .clipped()
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
    }

    private func commandDetail(_ cmd: PaletteCommand) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: cmd.icon)
                    .font(.system(size: 26))
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(cmd.title).font(.system(size: 15, weight: .semibold))
                    Text("Command").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Divider()
            Text(cmd.subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            if let entry = selectedEntry, let primary = actions(for: entry).first {
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
        if let entry = selectedEntry {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(actions(for: entry).enumerated()), id: \.element.id) { index, action in
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

    private func actions(for entry: Entry) -> [PaletteAction] {
        switch entry {
        case .command(let cmd):
            return [PaletteAction(title: "Run Command", symbol: cmd.icon, shortcut: "⏎") {
                cmd.perform()
                onClose()
            }]
        case .clip(let item):
            return clipActions(item)
        }
    }

    private func clipActions(_ item: ClipItem) -> [PaletteAction] {
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
        guard let entry = selectedEntry else { return }
        actions(for: entry).first?.perform()
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
                if let entry = selectedEntry {
                    let list = actions(for: entry)
                    if list.indices.contains(actionSelection) { run(list[actionSelection]) }
                }
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

    /// Fire the selected entry's action whose displayed shortcut matches (so the
    /// ⌘K labels and the direct keys stay in sync from one source of truth).
    private func runShortcut(_ shortcut: String) {
        guard let entry = selectedEntry,
              let action = actions(for: entry).first(where: { $0.shortcut == shortcut })
        else { return }
        action.perform()
    }

    private func move(_ delta: Int) {
        guard !flatEntries.isEmpty else { return }
        selection = min(max(0, selection + delta), flatEntries.count - 1)
    }

    private func moveAction(_ delta: Int) {
        guard let entry = selectedEntry else { return }
        let count = actions(for: entry).count
        actionSelection = min(max(0, actionSelection + delta), count - 1)
    }

    private func clampSelection() {
        if selection >= flatEntries.count { selection = max(0, flatEntries.count - 1) }
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

/// One palette row — a clip or a command.
private struct PaletteRow: View {
    let entry: QuickSearchView.Entry
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 20)
                .foregroundStyle(selected ? .white : .secondary)
            Text(title)
                .lineLimit(1)
                .foregroundStyle(selected ? .white : .primary)
            Spacer()
            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(selected ? Color.accentColor : .clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var trailing: some View {
        switch entry {
        case .command:
            Text("Command")
                .font(.caption)
                .foregroundStyle(selected ? .white.opacity(0.7) : .secondary)
        case .clip(let item):
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(selected ? .white.opacity(0.8) : .secondary)
            }
        }
    }

    private var title: String {
        switch entry {
        case .command(let c): return c.title
        case .clip(let c): return c.kind.previewText.replacingOccurrences(of: "\n", with: " ")
        }
    }

    private var symbol: String {
        switch entry {
        case .command(let c): return c.icon
        case .clip(let c):
            switch c.kind {
            case .text: return "textformat"
            case .link: return "link"
            case .color: return "paintpalette"
            case .image: return "photo"
            case .file: return "doc"
            case .locked: return "lock.fill"
            }
        }
    }
}
