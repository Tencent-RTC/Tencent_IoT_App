import SwiftUI

struct BottomTabBar: View {
    static let reservedHeight: CGFloat = 76

    let selection: AppTab
    let onSelect: (AppTab) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                item(tab)
            }
        }
        .padding(4)
        .frame(height: 60)
        .glass(Capsule(), strong: true)
        .elevation(.floating)
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }

    private func item(_ tab: AppTab) -> some View {
        let selected = tab == selection
        return Button {
            onSelect(tab)
        } label: {
            VStack(spacing: 2) {
                AppIconView(tab.icon, size: 23)
                Text(tab.title)
                    .font(AppFont.tabLabel)
                    .tracking(0.4)
            }
            .foregroundStyle(selected ? Palette.tabSelectedForeground : Palette.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background {
                if selected {
                    Capsule().fill(Palette.tabSelectedBackground)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
