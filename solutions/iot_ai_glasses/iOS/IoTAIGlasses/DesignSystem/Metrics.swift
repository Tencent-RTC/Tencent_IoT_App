import SwiftUI

enum Radius {
    static let card: CGFloat = 20
    static let button: CGFloat = 18
}

enum Spacing {
    static let screenHorizontal: CGFloat = 22
    static let screenTop: CGFloat = 8
    static let screenBottom: CGFloat = 24
    static let section: CGFloat = 20
}

enum Elevation {
    case none
    case card
    case raised
    case floating

    fileprivate var opacity: Double {
        switch self {
        case .none: 0
        case .card: 0.04
        case .raised: 0.07
        case .floating: 0.14
        }
    }

    fileprivate var radius: CGFloat {
        switch self {
        case .none: 0
        case .card: 12
        case .raised: 11
        case .floating: 15
        }
    }

    fileprivate var y: CGFloat {
        switch self {
        case .none: 0
        case .card: 5
        case .raised: 6
        case .floating: 10
        }
    }
}

private struct ElevationModifier: ViewModifier {
    let level: Elevation
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.shadow(
            color: colorScheme == .dark ? .clear : Palette.shadow.opacity(level.opacity),
            radius: level.radius,
            x: 0,
            y: level.y
        )
    }
}

private struct SurfaceModifier: ViewModifier {
    let radius: CGFloat
    let elevation: Elevation

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .glass(shape)
            .modifier(ElevationModifier(level: elevation))
    }
}

extension View {
    func elevation(_ level: Elevation) -> some View {
        modifier(ElevationModifier(level: level))
    }

    func surface(radius: CGFloat = Radius.card, elevation: Elevation = .card) -> some View {
        modifier(SurfaceModifier(radius: radius, elevation: elevation))
    }
}
