import SwiftUI

struct SessionHeader: View {
    let title: String
    var showsStatus = true
    var backLabel = "返回首页，保留当前会话"
    let onBack: () -> Void
    var onSettings: (() -> Void)?

    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 10) {
            BackButton(accessibilityLabel: backLabel, action: onBack)
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                if showsStatus {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(state.isConnected ? Palette.success : Palette.textSecondary)
                            .frame(width: 5, height: 5)
                        Text(state.isConnected ? "AI 眼镜已连接" : "眼镜未连接")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity)
            if let onSettings {
                CircleSymbolButton(symbol: "gearshape", accessibilityLabel: "设置", action: onSettings)
            } else {
                Color.clear
                    .frame(width: CircleIconButton.size, height: CircleIconButton.size)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: max(CircleIconButton.size, 44))
    }
}

struct LiveBarButton {
    enum Glyph {
        case app(AppIcon)
        case symbol(String)
    }

    let glyph: Glyph
    var tint: Color = Palette.textPrimary
    let label: String
    var isEnabled = true
    let action: () -> Void
}

struct LiveControlBar: View {
    let leading: LiveBarButton
    let pillIcon: AppIcon
    let pillText: String
    let pillLabel: String
    var pillEnabled = true
    let onPill: () -> Void
    let trailing: LiveBarButton

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
        HStack(spacing: 10) {
            circle(leading, dark)
            Button(action: onPill) {
                HStack(spacing: 8) {
                    AppIconView(pillIcon, size: 16)
                    Text(pillText)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Capsule().fill(Palette.accent))
                .opacity(pillEnabled ? 1 : 0.5)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!pillEnabled)
            .accessibilityLabel(pillLabel)
            circle(trailing, dark)
        }
        .padding(7)
        .background {
            if dark {
                shape.fill(Palette.surfaceRaised)
                    .overlay(shape.strokeBorder(Palette.line, lineWidth: 1))
            } else {
                shape.fill(Color.white)
                    .shadow(color: Palette.shadow.opacity(0.08), radius: 14, x: 0, y: 6)
            }
        }
        .padding(.top, 8)
    }

    private func circle(_ item: LiveBarButton, _ dark: Bool) -> some View {
        Button(action: item.action) {
            Group {
                switch item.glyph {
                case .app(let icon):
                    AppIconView(icon, size: 20)
                case .symbol(let name):
                    Image(systemName: name)
                        .font(.system(size: 16, weight: .medium))
                }
            }
            .foregroundStyle(item.tint)
            .frame(width: 48, height: 48)
            .background(Circle().fill(dark ? CaptionPalette.card : Color(hex: 0xF3F3F6)))
            .opacity(item.isEnabled ? 1 : 0.4)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!item.isEnabled)
        .accessibilityLabel(item.label)
    }
}

struct SessionSettingsSheet<Rows: View>: View {
    let title: String
    var height: CGFloat = 220
    @ViewBuilder let rows: Rows

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Button("完成") { dismiss() }
                    .font(AppFont.callout)
                    .foregroundStyle(Palette.accentText)
            }
            VStack(spacing: 0) { rows }
                .padding(.horizontal, 16)
                .surface(radius: 18)
            Spacer(minLength: 0)
        }
        .padding(20)
        .presentationDetents([.height(height)])
        .presentationBackground(Palette.background)
    }
}
