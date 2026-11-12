import SwiftUI

struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var backLabel = "返回"
    let onBack: () -> Void
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            BackButton(accessibilityLabel: backLabel, action: onBack)
            Spacer(minLength: 0)
            trailing
        }
        .frame(height: CircleIconButton.size)
        .overlay {
            VStack(spacing: 0) {
                Text(title)
                    .font(AppFont.navTitle)
                    .tracking(-0.4)
                    .foregroundStyle(Palette.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .lineLimit(1)
            .padding(.horizontal, CircleIconButton.size + 18)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
    }
}

extension PageHeader where Trailing == Color {
    init(title: String, subtitle: String? = nil, backLabel: String = "返回", onBack: @escaping () -> Void) {
        self.init(title: title, subtitle: subtitle, backLabel: backLabel, onBack: onBack) { Color.clear }
    }
}
