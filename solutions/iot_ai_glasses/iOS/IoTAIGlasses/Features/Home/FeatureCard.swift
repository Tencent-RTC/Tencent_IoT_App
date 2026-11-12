import SwiftUI

enum Feature: CaseIterable, Identifiable {
    case listen
    case meeting
    case interpret
    case call
    case chat

    var id: Self { self }

    var title: String {
        switch self {
        case .listen: "实时翻译"
        case .meeting: "会议转录"
        case .interpret: "双向传译"
        case .call: "语音通话"
        case .chat: "AI 对话"
        }
    }

    var subtitle: String {
        switch self {
        case .listen: "跨语言即时互译"
        case .meeting: "每句话都不遗漏"
        case .interpret: "面对面，自在聊"
        case .call: "用眼镜轻松接听"
        case .chat: "随时问一句"
        }
    }

    var icon: AppIcon {
        switch self {
        case .listen: .language
        case .meeting: .meeting
        case .interpret: .interpret
        case .call: .callFeature
        case .chat: .chatFeature
        }
    }

    var iconTint: (fg: UInt32, bg: UInt32) {
        switch self {
        case .listen: (0x5B4CF0, 0xEEEBFE)
        case .meeting: (0x2F6BD8, 0xE9F1FE)
        case .interpret: (0x1F8A5A, 0xE4F5EC)
        case .call: (0x1F8A5A, 0xE4F5EC)
        case .chat: (0xE8722C, 0xFFF0E4)
        }
    }

    var route: AppRoute {
        switch self {
        case .listen: .live(.translation)
        case .meeting: .live(.meeting)
        case .interpret: .interpretPrep
        case .call: .calls
        case .chat: .chat
        }
    }

    var sessionKind: SessionKind? {
        switch self {
        case .listen: .translation
        case .meeting: .meeting
        case .interpret: .interpret
        case .call: .call
        case .chat: nil
        }
    }

    fileprivate var tint: CardTint {
        switch self {
        case .listen:
            CardTint(stops: [(0xFFF0E4, 0x432925), (0xFFDFC9, 0x55352C), (0xFFC5A8, 0x664134)], text: (0x653D2E, 0xFFE4D2))
        case .meeting:
            CardTint(stops: [(0xF1EDFF, 0x302C49), (0xE1DBFF, 0x3D3759), (0xC9C4F5, 0x4A4269)], text: (0x443966, 0xECE6FF))
        case .interpret:
            CardTint(stops: [(0xE8F7EF, 0x233E3A), (0xCDE9DD, 0x33524B)], text: (0x355B50, 0xDDF5ED))
        case .call:
            CardTint(stops: [(0xECF3FF, 0x29374B), (0xD4E5F7, 0x3C536B)], text: (0x395474, 0xE2EDFF))
        case .chat:
            CardTint(stops: [(0xF4EDFC, 0x392E4A), (0xE4D9F5, 0x514365)], text: (0x5A4776, 0xF0E5FF))
        }
    }
}

private struct CardTint {
    let stops: [(UInt32, UInt32)]
    let text: (UInt32, UInt32)

    var gradient: LinearGradient {
        LinearGradient(colors: stops.map { Color(light: $0.0, dark: $0.1) }, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var foreground: Color { Color(light: text.0, dark: text.1) }
}

private struct FeatureCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct FeatureCard: View {
    let feature: Feature
    var compact = false
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        Button(action: action) {
            HStack(spacing: 12) {
                iconTile(dark)
                VStack(alignment: .leading, spacing: 2) {
                    Text(feature.title)
                        .font(.system(size: compact ? 14 : 15, weight: .semibold))
                        .foregroundStyle(dark ? feature.tint.foreground : Palette.textPrimary)
                        .lineLimit(1)
                    Text(feature.subtitle)
                        .font(.system(size: compact ? 10 : 11))
                        .foregroundStyle(dark ? feature.tint.foreground.opacity(0.7) : Palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, compact ? 12 : 14)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .background {
                if dark {
                    feature.tint.gradient
                } else {
                    shape.fill(Palette.surfaceRaised)
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(dark ? Color.white.opacity(0.1) : Palette.glassStroke, lineWidth: 1))
            .shadow(color: dark ? Color.black.opacity(0.12) : Palette.shadow.opacity(0.05), radius: 7, x: 0, y: 5)
            .contentShape(shape)
        }
        .buttonStyle(FeatureCardButtonStyle())
        .accessibilityLabel(feature.title)
        .accessibilityHint(feature.subtitle)
    }

    private func iconTile(_ dark: Bool) -> some View {
        let (fg, bg) = feature.iconTint
        return AppIconView(feature.icon, size: 22)
            .foregroundStyle(dark ? feature.tint.foreground : Color(hex: fg))
            .frame(width: 44, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(dark ? Color.white.opacity(0.12) : Color(hex: bg))
            )
            .accessibilityHidden(true)
    }
}
