import SwiftUI

struct ToastView: View {
    let text: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Text(text)
            .font(AppFont.footnote)
            .foregroundStyle(Palette.noticeText)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Palette.notice, in: shape)
            .overlay(shape.strokeBorder(Palette.noticeBorder, lineWidth: 1))
            .shadow(color: Palette.shadow.opacity(0.12), radius: 12, x: 0, y: 8)
            .padding(.horizontal, 22)
            .allowsHitTesting(false)
            .accessibilityAddTraits(.updatesFrequently)
    }
}
