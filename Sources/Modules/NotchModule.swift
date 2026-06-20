import SwiftUI
import Defaults

/// What the host gives a module's content view.
@MainActor
struct ModuleContext {
    /// Close the notch (e.g. after a clip is picked).
    let dismiss: () -> Void
}

/// A self-contained feature surface in the notch: a tab (when open) and, later,
/// a live activity (when collapsed). Adding a feature = one module + registering
/// it; the tab bar and (soon) Settings populate from the registry.
@MainActor
protocol NotchModule: AnyObject {
    /// Stable identifier (also persisted for tab order/selection).
    var id: String { get }
    var title: String { get }
    /// SF Symbol name.
    var icon: String { get }
    /// A live dot on the tab (e.g. music playing).
    var indicator: Bool { get }
    /// Preferred height of the expanded notch while this module's tab is shown.
    var preferredExpandedHeight: CGFloat { get }
    /// Whether items dropped on the notch should route here.
    var acceptsDrops: Bool { get }
    func handleDrop(_ providers: [NSItemProvider])
    /// The content shown when this module's tab is selected.
    func makeContent(_ context: ModuleContext) -> AnyView
}

extension NotchModule {
    var indicator: Bool { false }
    var preferredExpandedHeight: CGFloat { 180 }
    var acceptsDrops: Bool { false }
    func handleDrop(_ providers: [NSItemProvider]) {}
}

/// Holds the registered modules, their display order / enabled state (persisted),
/// and the current selection.
@MainActor
final class ModuleRegistry: ObservableObject {
    /// Every registered module.
    let allModules: [any NotchModule]
    /// Module ids in display order.
    @Published var order: [String] { didSet { Defaults[.moduleOrder] = order } }
    /// Hidden module ids.
    @Published var disabled: Set<String> {
        didSet { Defaults[.disabledModules] = Array(disabled); fixSelection() }
    }
    @Published var selectedID: String

    init(modules: [any NotchModule]) {
        self.allModules = modules
        let ids = modules.map(\.id)

        // Start from the saved order, drop removed modules, append new ones.
        var saved = Defaults[.moduleOrder].filter { ids.contains($0) }
        for id in ids where !saved.contains(id) { saved.append(id) }
        let disabledSet = Set(Defaults[.disabledModules].filter { ids.contains($0) })
        self.order = saved
        self.disabled = disabledSet
        self.selectedID = saved.first { !disabledSet.contains($0) } ?? ids.first ?? ""
    }

    /// Visible modules: enabled, in display order.
    var modules: [any NotchModule] {
        order.compactMap { id in
            disabled.contains(id) ? nil : allModules.first { $0.id == id }
        }
    }

    func module(_ id: String) -> (any NotchModule)? { allModules.first { $0.id == id } }
    var selected: (any NotchModule)? { modules.first { $0.id == selectedID } ?? modules.first }
    var dropModule: (any NotchModule)? { modules.first { $0.acceptsDrops } }

    func select(_ id: String) {
        guard selectedID != id else { return }
        selectedID = id
    }

    func move(from: IndexSet, to: Int) {
        order.move(fromOffsets: from, toOffset: to)
    }

    func setEnabled(_ enabled: Bool, _ id: String) {
        // Keep at least one tab visible.
        if !enabled && modules.count <= 1 { return }
        if enabled { disabled.remove(id) } else { disabled.insert(id) }
    }

    func isEnabled(_ id: String) -> Bool { !disabled.contains(id) }

    private func fixSelection() {
        if !modules.contains(where: { $0.id == selectedID }) {
            selectedID = modules.first?.id ?? selectedID
        }
    }
}
