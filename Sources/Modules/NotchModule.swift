import SwiftUI

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
    /// Whether items dropped on the notch should route here.
    var acceptsDrops: Bool { get }
    func handleDrop(_ providers: [NSItemProvider])
    /// The content shown when this module's tab is selected.
    func makeContent(_ context: ModuleContext) -> AnyView
}

extension NotchModule {
    var indicator: Bool { false }
    var acceptsDrops: Bool { false }
    func handleDrop(_ providers: [NSItemProvider]) {}
}

/// Holds the registered modules and the current selection.
@MainActor
final class ModuleRegistry: ObservableObject {
    let modules: [any NotchModule]
    @Published var selectedID: String

    init(modules: [any NotchModule]) {
        self.modules = modules
        self.selectedID = modules.first?.id ?? ""
    }

    var selected: (any NotchModule)? { modules.first { $0.id == selectedID } }

    /// First module that accepts drops (the Shelf), if any.
    var dropModule: (any NotchModule)? { modules.first { $0.acceptsDrops } }

    func select(_ id: String) {
        guard selectedID != id else { return }
        selectedID = id
    }
}
