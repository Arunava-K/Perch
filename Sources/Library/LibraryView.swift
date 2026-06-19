import SwiftUI

/// Full clipboard history browser: searchable, filterable grid with manage
/// actions. Double-click copies; context menu pins/deletes/quick-looks.
struct LibraryView: View {
    @ObservedObject var store: ClipStore
    var onCopyAndClose: () -> Void = {}

    @State private var search = ""
    @State private var typeFilter: TypeFilter = .all
    @State private var appFilter: String = LibraryView.allApps
    @State private var selection: Set<UUID> = []

    static let allApps = "All Apps"

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .frame(minWidth: 620, minHeight: 440)
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search clips…", text: $search)
                .textFieldStyle(.plain)
                .frame(maxWidth: 240)

            Picker("", selection: $typeFilter) {
                ForEach(TypeFilter.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .frame(width: 120)

            Picker("", selection: $appFilter) {
                Text(Self.allApps).tag(Self.allApps)
                ForEach(sourceApps, id: \.self) { Text($0).tag($0) }
            }
            .frame(width: 150)

            Spacer()
            Text("\(filtered.count) item\(filtered.count == 1 ? "" : "s")")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if filtered.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray").font(.system(size: 28, weight: .light))
                Text(store.items.isEmpty ? "No clips yet" : "No matches")
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
                            onSelect: { selection = [item.id] },
                            onCopy: { ClipboardWriter.copy(item); onCopyAndClose() },
                            onTogglePin: { store.setPinned(!item.isPinned, for: item.id) },
                            onDelete: { store.remove(item.id) },
                            onQuickLook: { QuickLookPreview.shared.show([item]) }
                        )
                    }
                }
                .padding(12)
            }
            .focusable()
            .onKeyPress(.space) {
                quickLookSelection()
                return .handled
            }
            .onKeyPress(.delete) {
                deleteSelection()
                return .handled
            }
        }
    }

    // MARK: Filtering

    private var sourceApps: [String] {
        Array(Set(store.items.compactMap { $0.sourceAppName })).sorted()
    }

    private var filtered: [ClipItem] {
        store.items.filter { item in
            typeFilter.matches(item) &&
            (appFilter == Self.allApps || item.sourceAppName == appFilter) &&
            (search.isEmpty || matchesSearch(item))
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
        for id in selection { store.remove(id) }
        selection.removeAll()
    }
}

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
