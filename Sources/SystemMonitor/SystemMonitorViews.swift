import SwiftUI

/// Control Center–style system monitor: equal metric tiles, monochrome tracks,
/// color only under load. No rainbow charts, no empty dual cards.
struct SystemMonitorTab: View {
    @ObservedObject var monitor: SystemMonitorManager

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                metricTile(
                    title: "CPU",
                    value: "\(pct(monitor.stats.cpuUsage))",
                    unit: "%",
                    detail: cpuDetail,
                    fraction: monitor.stats.cpuUsage,
                    tint: loadTint(monitor.stats.cpuUsage, warn: 0.55, crit: 0.85)
                )
                metricTile(
                    title: "Memory",
                    value: shortGB(monitor.stats.memoryUsed),
                    unit: "GB",
                    detail: "of \(shortGB(monitor.stats.memoryTotal)) GB",
                    fraction: monitor.stats.memoryPressure,
                    tint: loadTint(monitor.stats.memoryPressure, warn: 0.7, crit: 0.9)
                )
                metricTile(
                    title: "Disk",
                    value: shortGB(monitor.stats.diskUsed),
                    unit: "GB",
                    detail: "of \(shortGB(monitor.stats.diskTotal)) GB",
                    fraction: monitor.stats.diskFraction,
                    tint: loadTint(monitor.stats.diskFraction, warn: 0.85, crit: 0.95)
                )
                metricTile(
                    title: "GPU",
                    value: "\(pct(monitor.stats.gpuUsage))",
                    unit: "%",
                    detail: thermalDetail,
                    fraction: monitor.stats.gpuUsage,
                    tint: loadTint(monitor.stats.gpuUsage, warn: 0.55, crit: 0.85)
                )
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: Tile

    private func metricTile(
        title: String,
        value: String,
        unit: String,
        detail: String,
        fraction: Double,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))

            Spacer(minLength: 6)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.bottom, 2)
            }

            Text(detail)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
                .lineLimit(1)
                .padding(.top, 2)

            Spacer(minLength: 10)

            // Hairline track — monochrome fill, tint only when elevated
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.08))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(3, geo.size.width * min(1, max(0, fraction))))
                }
            }
            .frame(height: 3)
            .animation(.easeOut(duration: 0.25), value: fraction)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.045))
        )
    }

    // MARK: Copy helpers

    private var cpuDetail: String {
        let p = pct(monitor.stats.pCoreAvg)
        let e = pct(monitor.stats.eCoreAvg)
        if monitor.eCoreCount > 0 {
            return "P \(p)%  ·  E \(e)%"
        }
        return "\(monitor.pCoreCount) cores"
    }

    private var thermalDetail: String {
        switch monitor.stats.thermalState {
        case .nominal: return "Cool"
        case .fair: return "Warm"
        case .serious: return "Hot"
        case .critical: return "Critical"
        @unknown default: return "—"
        }
    }

    private func pct(_ v: Double) -> Int { Int((v * 100).rounded()) }

    private func shortGB(_ bytes: Double) -> String {
        let gb = bytes / 1_073_741_824
        if gb >= 100 { return String(format: "%.0f", gb) }
        if gb >= 10 { return String(format: "%.0f", gb) }
        if gb >= 1 { return String(format: "%.1f", gb) }
        return String(format: "%.1f", gb)
    }

    /// Rest state is soft white; warn/crit only when the number actually matters.
    private func loadTint(_ v: Double, warn: Double, crit: Double) -> Color {
        if v >= crit { return Color(red: 0.95, green: 0.38, blue: 0.32) }
        if v >= warn { return Color(red: 0.98, green: 0.72, blue: 0.28) }
        return .white.opacity(0.55)
    }
}

// MARK: - Ear badge

struct SystemLoadBadge: View {
    @ObservedObject var monitor: SystemMonitorManager
    let registry: ModuleRegistry

    var body: some View {
        let load = max(monitor.stats.cpuUsage, monitor.stats.memoryPressure)
        let pct = Int((load * 100).rounded())
        let color: Color = load > 0.8 ? .red : load > 0.5 ? .yellow : .green

        Button {
            registry.select("system")
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .font(.system(size: 10, weight: .semibold))
                Text("\(pct)%")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: load))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule(style: .continuous).fill(color.opacity(0.12)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(pressedScale: 0.94))
    }
}
