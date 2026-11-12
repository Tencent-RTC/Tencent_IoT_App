import SwiftUI

private struct ScrollShadowOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension View {
    func scrollShadowProbe() -> some View {
        background(alignment: .top) {
            GeometryReader { proxy in
                Color.clear.preference(key: ScrollShadowOffsetKey.self, value: proxy.frame(in: .scrollView).minY)
            }
        }
    }

    func topScrollShadow() -> some View {
        modifier(TopScrollShadow())
    }
}

private struct TopScrollShadow: ViewModifier {
    @State private var isScrolled = false
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(ScrollShadowOffsetKey.self) { offset in
                let scrolled = offset < -1
                if scrolled != isScrolled { isScrolled = scrolled }
            }
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [
                        colorScheme == .dark
                            ? Color.white.opacity(0.26)
                            : Color(hex: 0x1C1C28, opacity: 0.32),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 20)
                .padding(.horizontal, -Spacing.screenHorizontal)
                .opacity(isScrolled ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: isScrolled)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
    }
}
