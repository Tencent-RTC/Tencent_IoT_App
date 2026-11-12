import SwiftUI

struct ProductHero: View {
    let isConnected: Bool
    let batteryLevel: Int?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let radius: CGFloat = colorScheme == .dark ? 16 : 26
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 176)
            .background(Palette.heroBackground)
            .overlay {
                Image("Product")
                    .resizable()
                    .scaledToFill()
                    .accessibilityLabel(colorScheme == .dark ? "石墨黑AI眼镜外观" : "AI眼镜外观")
            }
            .clipShape(shape)
            .overlay(alignment: .topLeading) {
                ConnectionBadge(isConnected: isConnected).padding(10)
            }
            .overlay(alignment: .topTrailing) {
                BatteryBadge(level: batteryLevel).padding(10)
            }
            .shadow(color: colorScheme == .dark ? .clear : Palette.shadow.opacity(0.08), radius: 14, x: 0, y: 10)
    }
}

struct ConnectionBadge: View {
    let isConnected: Bool

    var body: some View {
        GlassBadge(
            background: isConnected ? BadgePalette.onBackground : BadgePalette.offBackground,
            border: isConnected ? BadgePalette.onBorder : BadgePalette.offBorder,
            foreground: isConnected ? BadgePalette.onText : BadgePalette.offText
        ) {
            AppIconView(.signal, size: 11)
            Text(isConnected ? "已连接" : "未连接")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isConnected ? "眼镜已连接" : "眼镜未连接")
    }
}

struct BatteryBadge: View {
    let level: Int?

    var body: some View {
        GlassBadge(
            background: level == nil ? BadgePalette.offBackground : BadgePalette.neutralBackground,
            border: level == nil ? BadgePalette.offBorder : BadgePalette.neutralBorder,
            foreground: level == nil ? BadgePalette.offText : BadgePalette.neutralText
        ) {
            BatteryGlyph(level: level)
            Text(level.map { "\($0)%" } ?? "—")
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(level.map { "眼镜电量 \($0)%" } ?? "眼镜电量未知")
    }
}

private struct GlassBadge<Content: View>: View {
    let background: Color
    let border: Color
    let foreground: Color
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 4) {
            content
        }
        .font(.system(size: 9.5))
        .tracking(0.2)
        .foregroundStyle(foreground)
        .padding(.horizontal, 7)
        .frame(height: 25)
        .background(.ultraThinMaterial, in: Capsule())
        .background(background, in: Capsule())
        .overlay(Capsule().strokeBorder(border, lineWidth: 1))
        .compositingGroup()
        .shadow(color: BadgePalette.shadow, radius: 9, x: 0, y: 6)
    }
}

private struct BatteryGlyph: View {
    let level: Int?

    var body: some View {
        let fraction = CGFloat(level ?? 0) / 100
        HStack(spacing: 0.6) {
            RoundedRectangle(cornerRadius: 1.1, style: .continuous)
                .strokeBorder(lineWidth: 0.9)
                .frame(width: 8.4, height: 4.4)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 0.5, style: .continuous)
                        .frame(width: 5.4 * fraction, height: 2.2)
                        .padding(.leading, 1.5)
                }
            Capsule()
                .frame(width: 0.9, height: 1.8)
        }
        .frame(width: 11, height: 11)
    }
}
