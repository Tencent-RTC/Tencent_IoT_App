import SwiftUI

struct SentenceCard: View {
    let index: Int
    let line: TranscriptLine
    let isLatest: Bool
    var showSpeaker: Bool = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let isActive = isLatest && line.translated.isEmpty
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                if showSpeaker {
                    Text(line.speaker == .me ? "我说" : "对方说")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(line.speaker == .me ? Palette.accentText : Palette.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(line.speaker == .me ? Palette.accentSoft : Color(light: 0xF3F3F6, dark: 0x2A302A))
                        )
                        .accessibilityHidden(true)
                }
                if isActive {
                    Circle()
                        .fill(CaptionPalette.latestActiveTag)
                        .frame(width: 5, height: 5)
                    Text("识别并翻译中")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CaptionPalette.latestActiveTag)
                } else {
                    Text(Clock.text(line.time))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(CaptionPalette.time)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 16)
            .padding(.bottom, 8)

            Text(line.original)
                .font(.system(size: 13.5))
                .lineSpacing(4)
                .foregroundStyle(CaptionPalette.source)
                .fixedSize(horizontal: false, vertical: true)

            Text(line.translated.isEmpty ? "翻译中…" : line.translated)
                .font(.system(size: 16, weight: .semibold))
                .lineSpacing(5)
                .foregroundStyle(line.translated.isEmpty ? CaptionPalette.time : CaptionPalette.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isActive ? CaptionPalette.latestActiveCard : CaptionPalette.card, in: shape)
        .overlay(shape.strokeBorder(isActive ? CaptionPalette.latestActiveBorder : CaptionPalette.border, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.translated.isEmpty ? "第 \(index + 1) 句，\(line.original)" : "第 \(index + 1) 句，\(line.translated)。原文：\(line.original)")
        .accessibilityValue(isLatest ? "最新" : "")
    }
}
