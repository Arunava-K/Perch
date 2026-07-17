import SwiftUI

@MainActor
final class SystemMonitorModule: NotchModule {
    let id = "system"
    let title = "System"

    let monitor: SystemMonitorManager

    init(monitor: SystemMonitorManager) { self.monitor = monitor }

    var icon: String {
        let avg = (monitor.stats.cpuUsage + monitor.stats.memoryFraction) / 2
        if avg < 0.35 { return "chart.bar.fill" }
        if avg < 0.65 { return "chart.bar" }
        return "chart.bar.doc.horizontal.fill"
    }

    var indicator: Bool { true }

    var indicatorColor: Color? {
        let avg = (monitor.stats.cpuUsage + monitor.stats.memoryFraction) / 2
        if avg > 0.8 { return .red }
        if avg > 0.5 { return .yellow }
        return .green
    }

    var hiddenFromTabBar: Bool { true }

    var preferredExpandedHeight: CGFloat { 200 }

    func makeContent(_ context: ModuleContext) -> AnyView {
        AnyView(SystemMonitorTab(monitor: monitor))
    }
}
