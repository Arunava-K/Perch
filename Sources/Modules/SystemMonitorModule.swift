import SwiftUI
import Defaults

@MainActor
final class SystemMonitorModule: NotchModule {
    let id = "system"
    let title = "System"

    let monitor: SystemMonitorManager

    init(monitor: SystemMonitorManager) { self.monitor = monitor }

    var icon: String {
        let load = monitor.stats.load(for: Defaults[.systemMonitorBadgeMetric])
        if load < 0.35 { return "chart.bar.fill" }
        if load < 0.65 { return "chart.bar" }
        return "chart.bar.doc.horizontal.fill"
    }

    var indicator: Bool { true }

    var indicatorColor: Color? {
        let load = monitor.stats.load(for: Defaults[.systemMonitorBadgeMetric])
        if load > 0.8 { return .red }
        if load > 0.5 { return .yellow }
        return .green
    }

    var hiddenFromTabBar: Bool { true }

    var preferredExpandedHeight: CGFloat { 230 }

    func makeContent(_ context: ModuleContext) -> AnyView {
        AnyView(SystemMonitorTab(monitor: monitor))
    }
}
