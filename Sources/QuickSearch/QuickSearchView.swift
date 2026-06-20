import SwiftUI

/// Spotlight-style palette: type to filter clips, ↑/↓ to move, ⏎ to paste into
/// the previously-active app, Esc to dismiss.
struct QuickSearchView: View {
    @ObservedObject var store: ClipStore
    var onPaste: (ClipItem) -> Void
    var onClose: () -> Void

    @State private var query = ""
    @State private var results: [ClipItem] = []
    @State private var selection = 0
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            resultsList
        }
        .frame(width: 580, height: 420)
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
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search clipboard…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .focused($focused)
                .onSubmit(activateSelection)
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.escape) { onClose(); return .handled }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .onChange(of: query) { _, newValue in
            selection = 0
            runSearch(newValue, debounce: true)
        }
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                        QuickSearchRow(item: item, selected: index == selection)
                            .id(index)
                            .contentShape(Rectangle())
                            .onTapGesture { selection = index; activateSelection() }
                    }
                }
                .padding(8)
            }
            .onChange(of: selection) { _, new in
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(new, anchor: .center) }
            }
        }
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = min(max(0, selection + delta), results.count - 1)
    }

    private func activateSelection() {
        guard results.indices.contains(selection) else { return }
        onPaste(results[selection])
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
            if let app = item.sourceAppName {
                Text(app).font(.caption).foregroundStyle(selected ? .white.opacity(0.8) : .secondary)
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
