import SwiftUI

/// Full clipboard browser: a sidebar of collections, a keyword/semantic search
/// bar, and a filterable grid. Double-click copies (or reveals a locked clip /
/// restores a trashed one); the context menu manages each clip.
struct LibraryView: View {
    @ObservedObject var store: ClipStore
    var onCopyAndClose: () -> Void = {}

    @State private var search = ""
    @State private var searchMode: SearchMode = .keyword
    @State private var typeFilter: TypeFilter = .all
    @State private var appFilter: String = LibraryView.allApps
    @State private var selection: Set<UUID> = []
    @State private var sidebarSelection: SidebarItem? = .all

    static let allApps = "All Apps"

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)]

    private var scope: SidebarItem { sidebarSelection ?? .all }
    private var isTrashMode: Bool { scope == .trash }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            VStack(spacing: 0) {
                toolbar
                Divider()
                content
            }
        }
        .frame(minWidth: 760, minHeight: 460)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $sidebarSelection) {
            Section("Library") {
                row(.all, count: store.items.count)
                row(.pinned, count: store.items.filter(\.isPinned).count)
                row(.locked, count: store.items.filter(\.isLocked).count)
            }
            Section {
                row(.trash, count: store.trashedItems.count)
            }
        }
        .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        .onChange(of: sidebarSelection) { _, _ in selection.removeAll() }
    }

    private func row(_ item: SidebarItem, count: Int) -> some View {
        Label(item.title, systemImage: item.icon)
            .badge(count)
            .tag(item)
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: searchMode == .semantic ? "sparkle.magnifyingglass" : "magnifyingglass")
                .foregroundStyle(searchMode == .semantic ? Color.accentColor : .secondary)
            TextField(searchPlaceholder, text: $search)
                .textFieldStyle(.plain)
                .frame(maxWidth: 220)

            if !isTrashMode && store.semanticSearchAvailable {
                Picker("", selection: $searchMode) {
                    ForEach(SearchMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 168)
                .help("Keyword matches text exactly; Semantic finds clips by meaning.")
            }

            Picker("", selection: $typeFilter) {
                ForEach(TypeFilter.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .frame(width: 110)

            Picker("", selection: $appFilter) {
                Text(Self.allApps).tag(Self.allApps)
                ForEach(sourceApps, id: \.self) { Text($0).tag($0) }
            }
            .frame(width: 130)

            Spacer()

            Button { store.restoreLast() } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .help("Undo last delete")
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!store.canUndo)

            if isTrashMode {
                Button(role: .destructive) { store.emptyTrash() } label: {
                    Text("Empty Trash")
                }
                .disabled(store.trashedItems.isEmpty)
            }

            Text("\(filtered.count)")
                .font(.caption).foregroundStyle(.secondary)
                .frame(minWidth: 28, alignment: .trailing)
        }
        .padding(10)
    }

    private var searchPlaceholder: String {
        if isTrashMode { return "Search trash…" }
        return searchMode == .semantic ? "Find by meaning…" : "Search clips…"
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if filtered.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: scope.icon).font(.system(size: 28, weight: .light))
                Text(emptyMessage)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(filtered) { item in
                        LibraryItemCell(
                            item: item,
                            isSelected: selection.contains(item.id),
                            isTrashMode: isTrashMode,
                            canLock: store.canLock(item),
                            isRevealed: store.isRevealed(item.id),
                            hasRichText: item.richRTF != nil,
                            onSelect: { selection = [item.id] },
                            onCopy: { primaryAction(item) },
                            onTogglePin: { store.setPinned(!item.isPinned, for: item.id) },
                            onDelete: { deleteAction(item) },
                            onQuickLook: { QuickLookPreview.shared.show([item]) },
                            onLock: { store.lock(item.id) },
                            onReveal: { store.reveal(item.id) },
                            onRemoveLock: { store.removeLock(item.id) },
                            onCopyPlain: { ClipboardWriter.copy(item, asPlainText: true); onCopyAndClose() }
                        )
                    }
                }
                .padding(12)
            }
            .focusable()
            .onKeyPress(.space) { quickLookSelection(); return .handled }
            .onKeyPress(.delete) { deleteSelection(); return .handled }
        }
    }

    private var emptyMessage: String {
        if !search.isEmpty { return "No matches" }
        switch scope {
        case .all: return "No clips yet"
        case .pinned: return "No pinned clips"
        case .locked: return "No locked clips"
        case .trash: return "Trash is empty"
        }
    }

    /// Primary click/double-click action: restore in trash, reveal a sealed
    /// clip, otherwise copy.
    private func primaryAction(_ item: ClipItem) {
        if isTrashMode {
            store.restore(item.id)
        } else if item.isLocked && !store.isRevealed(item.id) {
            store.reveal(item.id)
        } else {
            ClipboardWriter.copy(item)
            onCopyAndClose()
        }
    }

    private func deleteAction(_ item: ClipItem) {
        if isTrashMode { store.deleteTrashedPermanently(item.id) } else { store.remove(item.id) }
    }

    // MARK: Filtering

    private var scopedItems: [ClipItem] {
        switch scope {
        case .all: return store.items
        case .pinned: return store.items.filter(\.isPinned)
        case .locked: return store.items.filter(\.isLocked)
        case .trash: return store.trashedItems
        }
    }

    private var sourceApps: [String] {
        Array(Set(scopedItems.compactMap { $0.sourceAppName })).sorted()
    }

    private var filtered: [ClipItem] {
        // Semantic ranking applies only to active scopes with a query.
        let useSemantic = searchMode == .semantic && !isTrashMode && !search.isEmpty
        let base: [ClipItem]
        if useSemantic {
            let scopeIDs = Set(scopedItems.map(\.id))
            base = store.semanticResults(for: search).filter { scopeIDs.contains($0.id) }
        } else {
            base = scopedItems
        }
        return base.filter { item in
            typeFilter.matches(item) &&
            (appFilter == Self.allApps || item.sourceAppName == appFilter) &&
            (useSemantic || search.isEmpty || matchesSearch(item))
        }
    }

    private func matchesSearch(_ item: ClipItem) -> Bool {
        item.searchText.lowercased().contains(search.lowercased())
    }

    private func quickLookSelection() {
        let items = filtered.filter { selection.contains($0.id) }
        QuickLookPreview.shared.show(items.isEmpty ? Array(filtered.prefix(1)) : items)
    }

    private func deleteSelection() {
        for id in selection {
            if isTrashMode { store.deleteTrashedPermanently(id) } else { store.remove(id) }
        }
        selection.removeAll()
    }
}

// MARK: - Sidebar items

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case all, pinned, locked, trash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All Clips"
        case .pinned: return "Pinned"
        case .locked: return "Locked"
        case .trash: return "Trash"
        }
    }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .pinned: return "pin"
        case .locked: return "lock"
        case .trash: return "trash"
        }
    }
}

enum SearchMode: String, CaseIterable, Hashable {
    case keyword, semantic
    var label: String { self == .keyword ? "Keyword" : "Semantic" }
}

// MARK: - Type filter

enum TypeFilter: CaseIterable, Hashable {
    case all, text, link, color, image, file

    var label: String {
        switch self {
        case .all: return "All Types"
        case .text: return "Text"
        case .link: return "Links"
        case .color: return "Colors"
        case .image: return "Images"
        case .file: return "Files"
        }
    }

    func matches(_ item: ClipItem) -> Bool {
        switch self {
        case .all: return true
        case .text: if case .text = item.kind { return true }; return false
        case .link: if case .link = item.kind { return true }; return false
        case .color: if case .color = item.kind { return true }; return false
        case .image: if case .image = item.kind { return true }; return false
        case .file: if case .file = item.kind { return true }; return false
        }
    }
}
