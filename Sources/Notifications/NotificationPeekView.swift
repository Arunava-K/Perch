import SwiftUI

/// A macOS notification rendered in the notch peek — app icon, headline, and a
/// detail line, styled to match the copy sneak-peek.
struct NotificationPeekView: View {
    let item: NotificationItem

    var body: some View {
        HStack(spacing: 11) {
            icon
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.appName.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(item.date, format: .relative(presentation: .numeric))
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
                }
                Text(item.headline)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var icon: some View {
        if let appIcon = item.appIcon {
            Image(nsImage: appIcon).resizable().aspectRatio(contentMode: .fit)
        } else {
            ZStack {
                Color.white.opacity(0.12)
                Image(systemName: "bell.fill").font(.system(size: 13)).foregroundStyle(.white)
            }
        }
    }
}
