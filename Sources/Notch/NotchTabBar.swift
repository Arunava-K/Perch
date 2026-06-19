import SwiftUI

/// Segmented tab selector for the expanded notch. The selection pill slides
/// between tabs via `matchedGeometryEffect` for a fluid, "alive" transition.
struct NotchTabBar: View {
    @Binding var selection: NotchTab
    var musicActive: Bool

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(NotchTab.allCases) { tab in
                tabButton(tab)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 24)
        .padding(.trailing, 14)
    }

    private func tabButton(_ tab: NotchTab) -> some View {
        let isSelected = selection == tab
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                selection = tab
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(tab.title)
                    .font(.system(size: 11, weight: .medium))
                if tab == .music && musicActive {
                    Circle().fill(.green).frame(width: 5, height: 5)
                }
            }
            .foregroundStyle(isSelected ? .white : .white.opacity(0.4))
            .padding(.horizontal, 8)
            .padding(.vertical, 4.5)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(.white.opacity(0.13))
                        .matchedGeometryEffect(id: "tabPill", in: namespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(pressedScale: 0.94))
    }
}
