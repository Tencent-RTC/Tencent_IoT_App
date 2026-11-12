import SwiftUI

struct AppBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if colorScheme == .dark {
            Palette.background
        } else {
            LinearGradient(stops: [
                .init(color: Color(hex: 0xFCE4D6), location: 0),
                .init(color: Color(hex: 0xF3E9E6), location: 0.1),
                .init(color: Color(hex: 0xEEEEF3), location: 0.2)
            ], startPoint: .top, endPoint: .bottom)
        }
    }
}

private struct GlassFill<S: InsettableShape>: ViewModifier {
    let shape: S
    let strong: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if colorScheme == .dark {
            content
                .background((strong ? Palette.glassStrong : Palette.surface), in: shape)
                .overlay(shape.strokeBorder(Palette.line, lineWidth: 1))
        } else {
            content
                .background(Color.white, in: shape)
        }
    }
}

extension View {
    func glass<S: InsettableShape>(_ shape: S, strong: Bool = false) -> some View {
        modifier(GlassFill(shape: shape, strong: strong))
    }

    func glass(radius: CGFloat, strong: Bool = false) -> some View {
        glass(RoundedRectangle(cornerRadius: radius, style: .continuous), strong: strong)
    }
}
