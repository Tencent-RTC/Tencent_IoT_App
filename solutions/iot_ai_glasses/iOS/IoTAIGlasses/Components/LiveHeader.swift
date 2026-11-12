import SwiftUI

struct LiveHeader: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            BackButton(accessibilityLabel: "返回首页，保留当前会话", action: onBack)
            Text(title)
                .font(AppFont.navTitle)
                .tracking(-0.4)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityAddTraits(.isHeader)
            Color.clear
                .frame(width: CircleIconButton.size, height: CircleIconButton.size)
                .accessibilityHidden(true)
        }
        .frame(height: CircleIconButton.size)
    }
}

struct InlineHint<Action: View>: View {
    enum Tone {
        case error
        case warning
    }

    let tone: Tone
    let text: String
    @ViewBuilder let action: Action

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.system(size: 11))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            action
        }
        .foregroundStyle(tone == .error ? CaptionPalette.errorText : CaptionPalette.warnText)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone == .error ? CaptionPalette.errorBackground : CaptionPalette.warnBackground, in: shape)
        .overlay(shape.strokeBorder(tone == .error ? CaptionPalette.errorBorder : CaptionPalette.warnBorder, lineWidth: 1))
    }
}

extension InlineHint where Action == EmptyView {
    init(tone: Tone, text: String) {
        self.init(tone: tone, text: text) { EmptyView() }
    }
}

struct HintButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        configuration.label
            .font(AppFont.caption)
            .foregroundStyle(CaptionPalette.errorText)
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(Palette.surfaceRaised, in: shape)
            .overlay(shape.strokeBorder(Palette.line, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(shape)
    }
}
