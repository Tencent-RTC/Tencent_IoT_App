import SwiftUI

struct SettingsGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(.horizontal, 18)
        .surface()
    }
}

struct SettingRow<Trailing: View>: View {
    let icon: AppIcon
    let title: String
    var showsDivider = false
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(icon, size: 21)
                .foregroundStyle(Palette.textSecondary)
            Text(title)
                .font(AppFont.callout)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 12)
            trailing
        }
        .frame(minHeight: 68)
        .overlay(alignment: .top) {
            if showsDivider {
                Rectangle()
                    .fill(Palette.separator)
                    .frame(height: 1)
            }
        }
    }
}

struct StatusDot: View {
    let text: String
    var color: Color = Palette.success

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(text)
                .font(AppFont.caption)
        }
        .foregroundStyle(color)
    }
}
