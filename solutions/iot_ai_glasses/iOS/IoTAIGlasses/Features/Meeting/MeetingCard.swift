import SwiftUI

struct SpeakerTonePalette {
    let text: Color
    let border: Color
    let background: Color

    static func tone(_ index: Int) -> SpeakerTonePalette {
        switch ((index % 5) + 5) % 5 {
        case 0:
            Self(
                text: Color(light: 0x4D6F2A, dark: 0xD2EDAD),
                border: Color(light: 0x7A9C3C, lightAlpha: 0.45, dark: 0xD2EDAD, darkAlpha: 0.38),
                background: Color(light: 0xD2EDAD, lightAlpha: 0.35, dark: 0xD2EDAD, darkAlpha: 0.10)
            )
        case 1:
            Self(
                text: Color(light: 0x3D6A99, dark: 0xA9CBE8),
                border: Color(light: 0x5E85B0, lightAlpha: 0.45, dark: 0xA9CBE8, darkAlpha: 0.38),
                background: Color(light: 0xA9CBE8, lightAlpha: 0.30, dark: 0xA9CBE8, darkAlpha: 0.10)
            )
        case 2:
            Self(
                text: Color(light: 0x9A7425, dark: 0xE8CFA9),
                border: Color(light: 0xBA9858, lightAlpha: 0.45, dark: 0xE8CFA9, darkAlpha: 0.38),
                background: Color(light: 0xE8CFA9, lightAlpha: 0.30, dark: 0xE8CFA9, darkAlpha: 0.10)
            )
        case 3:
            Self(
                text: Color(light: 0xA94A68, dark: 0xE8A9BD),
                border: Color(light: 0xC4718B, lightAlpha: 0.45, dark: 0xE8A9BD, darkAlpha: 0.38),
                background: Color(light: 0xE8A9BD, lightAlpha: 0.30, dark: 0xE8A9BD, darkAlpha: 0.10)
            )
        default:
            Self(
                text: Color(light: 0x6B4AA0, dark: 0xC4A9E8),
                border: Color(light: 0x8F71BF, lightAlpha: 0.45, dark: 0xC4A9E8, darkAlpha: 0.38),
                background: Color(light: 0xC4A9E8, lightAlpha: 0.30, dark: 0xC4A9E8, darkAlpha: 0.10)
            )
        }
    }
}

struct MeetingCard: View {
    let index: Int
    let line: TranscriptLine
    let isLatest: Bool
    let speakerIndex: Int
    var isSpeaking = false

    private static let dots: [UInt32] = [0xF2762E, 0x2F6BD8, 0x1F8A5A, 0x8B5CF6, 0xD9488B]

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let dot = Self.dots[((speakerIndex % Self.dots.count) + Self.dots.count) % Self.dots.count]
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: dot))
                    .frame(width: 7, height: 7)
                Text(line.speakerLabel ?? "发言人")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CaptionPalette.text)
                if isSpeaking {
                    Text("正在说话…")
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
            .frame(height: 20)
            .padding(.bottom, 6)

            Text(line.original)
                .font(.system(size: 15))
                .lineSpacing(5)
                .foregroundStyle(CaptionPalette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSpeaking ? CaptionPalette.latestActiveCard : CaptionPalette.card, in: shape)
        .overlay(shape.strokeBorder(isSpeaking ? CaptionPalette.latestActiveBorder : CaptionPalette.border, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("第 \(index + 1) 段，\(line.speakerLabel ?? "发言人")，\(line.original)")
        .accessibilityValue(isSpeaking ? "正在说话" : (isLatest ? "最新" : ""))
    }
}

enum MeetingSpeakerIndex {
    static func map(_ lines: [TranscriptLine]) -> [String: Int] {
        var order: [String] = []
        for line in lines {
            guard let label = line.speakerLabel, !order.contains(label) else { continue }
            order.append(label)
        }
        return Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
    }
}
