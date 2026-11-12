import SwiftUI

struct SessionBanner: View {
    let status: String
    let seconds: Int
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let radius: CGFloat = colorScheme == .dark ? 10 : 16
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Palette.noticeDot)
                    .frame(width: 6, height: 6)
                Text("\(status) · \(Clock.text(seconds))")
                    .monospacedDigit()
                Spacer(minLength: 8)
                AppIconView(.arrow, size: 18)
            }
            .font(AppFont.caption)
            .foregroundStyle(Palette.noticeText)
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(Palette.notice, in: shape)
            .overlay(shape.strokeBorder(Palette.noticeBorder, lineWidth: 1))
            .elevation(.raised)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(status)，已进行 \(Clock.text(seconds))")
        .accessibilityHint("返回当前任务")
    }
}
