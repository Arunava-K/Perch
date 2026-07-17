import SwiftUI

struct SystemMonitorTab: View {
    @ObservedObject var monitor: SystemMonitorManager

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                cpuGauge
                gauge(value: monitor.stats.memoryFraction, label: "Memory",
                      color: memColor(monitor.stats.memoryFraction))
                gauge(value: monitor.stats.diskFraction, label: "Disk",
                      color: diskColor(monitor.stats.diskFraction))
            }
            .padding(.horizontal, 20)

            if let level = monitor.stats.batteryLevel {
                batteryRow(level: level, charging: monitor.stats.batteryCharging)
                    .padding(.horizontal, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: CPU gauge

    private var cpuGauge: some View {
        let p = monitor.stats.pCoreAvg
        let e = monitor.stats.eCoreAvg
        let combined = (p + e) / 2
        let pct = Int(combined * 100)
        let color = cpuColor(combined)

        return GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height - 16)
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.07), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: combined)
                        .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 1) {
                        HStack(spacing: 4) {
                            Text("\(Int(p * 100))")
                                .font(.system(size: size * 0.17, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(pCoreColor(p))
                            Image(systemName: "circle.fill")
                                .font(.system(size: 4))
                                .foregroundStyle(.white.opacity(0.15))
                            Text("\(Int(e * 100))")
                                .font(.system(size: size * 0.17, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(eCoreColor(e))
                        }
                        HStack(spacing: 3) {
                            Text("P")
                                .font(.system(size: size * 0.09, weight: .semibold))
                                .foregroundStyle(pCoreColor(p).opacity(0.6))
                            Text("E")
                                .font(.system(size: size * 0.09, weight: .semibold))
                                .foregroundStyle(eCoreColor(e).opacity(0.6))
                        }
                    }
                }
                .frame(width: size, height: size)
                .animation(.spring(response: 0.3), value: combined)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.04))
            )
        }
        .frame(height: 140)
    }

    // MARK: Generic gauge

    private func gauge(value: Double, label: String, color: Color) -> some View {
        let pct = Int(value * 100)
        return GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height - 16)
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.07), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: value)
                        .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 1) {
                        Text("\(pct)")
                            .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .contentTransition(.numericText(value: Double(pct)))
                        Text(label)
                            .font(.system(size: size * 0.1, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                .frame(width: size, height: size)
                .animation(.spring(response: 0.3), value: value)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.04))
            )
        }
        .frame(height: 140)
    }

    // MARK: Battery

    private func batteryRow(level: Double, charging: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: charging ? "bolt.fill" : "battery.100")
                .font(.system(size: 11))
                .foregroundStyle(charging ? .yellow : .white.opacity(0.55))
            Text("\(Int(level * 100))%")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
            if charging {
                Text("· Charging")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.yellow.opacity(0.7))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.04))
        )
    }

    // MARK: Colors

    private func cpuColor(_ v: Double) -> Color {
        v < 0.5 ? Color(red: 0.4, green: 0.9, blue: 0.5) : v < 0.8 ? Color(red: 0.95, green: 0.7, blue: 0.2) : Color(red: 0.95, green: 0.3, blue: 0.25)
    }

    private func pCoreColor(_ v: Double) -> Color {
        v < 0.5 ? Color(red: 0.4, green: 0.9, blue: 0.5) : v < 0.8 ? Color(red: 0.95, green: 0.7, blue: 0.2) : Color(red: 0.95, green: 0.3, blue: 0.25)
    }

    private func eCoreColor(_ v: Double) -> Color {
        v < 0.5 ? Color(red: 0.2, green: 0.7, blue: 0.95) : v < 0.8 ? Color(red: 0.7, green: 0.5, blue: 0.95) : Color(red: 0.95, green: 0.3, blue: 0.5)
    }

    private func memColor(_ v: Double) -> Color {
        v < 0.7 ? Color(red: 0.4, green: 0.9, blue: 0.5) : v < 0.85 ? Color(red: 0.95, green: 0.7, blue: 0.2) : Color(red: 0.95, green: 0.3, blue: 0.25)
    }

    private func diskColor(_ v: Double) -> Color {
        v < 0.8 ? Color(red: 0.4, green: 0.9, blue: 0.5) : v < 0.92 ? Color(red: 0.95, green: 0.7, blue: 0.2) : Color(red: 0.95, green: 0.3, blue: 0.25)
    }
}

// MARK: - Ear badge

struct SystemLoadBadge: View {
    @ObservedObject var monitor: SystemMonitorManager
    let registry: ModuleRegistry

    var body: some View {
        let avg = (monitor.stats.cpuUsage + monitor.stats.memoryFraction) / 2
        let pct = Int(avg * 100)
        let color: Color = avg > 0.8 ? .red : avg > 0.5 ? .yellow : .green

        Button {
            registry.select("system")
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .font(.system(size: 10, weight: .semibold))
                Text("\(pct)%")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: avg))
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
