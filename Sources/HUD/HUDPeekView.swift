import SwiftUI

/// A compact system-HUD shown in the notch peek: an icon and a level bar.
struct HUDPeekView: View {
    let symbol: String
    let value: Double  // 0...1

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 22)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.22))
                    Capsule().fill(.white)
                        .frame(width: max(4, geo.size.width * value.clamped))
                }
            }
            .frame(height: 6)

            Text("\(Int((value.clamped) * 100))")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .monospacedDigit()
                .frame(width: 26, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension Double {
    var clamped: Double { Swift.min(1, Swift.max(0, self)) }
}
