import SwiftUI

/// Segmented tab selector for the expanded notch. Only the selected tab shows
/// its label (others collapse to icons) so the bar fits beside the camera and
/// scales to many modules. The selection pill slides via `matchedGeometryEffect`.
struct NotchTabBar: View {
    @Binding var selection: NotchTab
    var musicActive: Bool

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 3) {
            ForEach(NotchTab.allCases) { tab in
                tabButton(tab)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 22)
        .padding(.trailing, 12)
    }

    private func tabButton(_ tab: NotchTab) -> some View {
        let isSelected = selection == tab
        return Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                selection = tab
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 13)
                if isSelected {
                    Text(tab.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .fixedSize()
                }
                if tab == .music && musicActive {
                    Circle().fill(.green).frame(width: 5, height: 5)
                }
            }
            .foregroundStyle(isSelected ? .white : .white.opacity(0.42))
            .padding(.horizontal, isSelected ? 11 : 7)
            .padding(.vertical, 5)
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
