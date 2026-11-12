import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 56
    var radius: CGFloat = Radius.button
    var font: Font = AppFont.button

    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration, height: height, radius: radius, font: font)
    }
}

private struct PrimaryButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let height: CGFloat
    let radius: CGFloat
    let font: Font
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        configuration.label
            .font(font)
            .tracking(0.3)
            .foregroundStyle(Palette.onAccent)
            .frame(maxWidth: .infinity, minHeight: height)
            .background {
                if colorScheme == .dark {
                    shape.fill(Palette.accent)
                } else {
                    shape.fill(Palette.primaryGradient)
                }
            }
            .shadow(color: glow, radius: 10, x: 0, y: 7)
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .contentShape(shape)
    }

    private var glow: Color {
        colorScheme == .dark || !isEnabled ? .clear : Palette.primaryGlow
    }
}

struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.captionMedium)
            .foregroundStyle(Palette.accentText)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(Palette.accentSoft, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

struct SheetButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        configuration.label
            .font(.system(size: 14))
            .foregroundStyle(Palette.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Palette.surfaceRaised, in: shape)
            .overlay(shape.strokeBorder(Palette.line, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(shape)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }

    static func primary(height: CGFloat, radius: CGFloat, font: Font = AppFont.button) -> PrimaryButtonStyle {
        PrimaryButtonStyle(height: height, radius: radius, font: font)
    }
}

struct DangerSheetButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Palette.danger, in: shape)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(shape)
    }
}

extension ButtonStyle where Self == DangerSheetButtonStyle {
    static var danger: DangerSheetButtonStyle { DangerSheetButtonStyle() }
}

extension ButtonStyle where Self == SheetButtonStyle {
    static var sheet: SheetButtonStyle { SheetButtonStyle() }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
}

struct BackButton: View {
    var accessibilityLabel = "返回"
    let action: () -> Void

    var body: some View {
        CircleIconButton(icon: .back, accessibilityLabel: accessibilityLabel, action: action)
    }
}

struct CircleIconButton: View {
    enum Style {
        case raised
        case plain
    }

    static let size: CGFloat = 40

    let icon: AppIcon
    var style: Style = .raised
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AppIconView(icon, size: 19)
                .foregroundStyle(Palette.textPrimary)
                .headerCircle(raised: style == .raised)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct CircleSymbolButton: View {
    let symbol: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Palette.textPrimary)
                .headerCircle(raised: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct HeaderCircle: ViewModifier {
    let raised: Bool

    func body(content: Content) -> some View {
        if raised {
            content
                .frame(width: CircleIconButton.size, height: CircleIconButton.size)
                .glass(Circle(), strong: true)
                .elevation(.raised)
                .contentShape(Circle())
        } else {
            content
                .frame(width: CircleIconButton.size, height: CircleIconButton.size)
                .contentShape(Circle())
        }
    }
}

extension View {
    func headerCircle(raised: Bool = true) -> some View {
        modifier(HeaderCircle(raised: raised))
    }
}
