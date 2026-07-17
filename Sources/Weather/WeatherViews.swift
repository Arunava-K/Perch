import SwiftUI

/// Compact temperature + condition badge in the top-right ear.
struct WeatherBadge: View {
    @ObservedObject var weather: WeatherManager

    var body: some View {
        if let data = weather.data {
            HStack(spacing: 3) {
                Text(data.conditionIcon)
                    .font(.system(size: 10))
                Text(data.temperatureDisplay)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .contentShape(Capsule())
        }
    }
}
