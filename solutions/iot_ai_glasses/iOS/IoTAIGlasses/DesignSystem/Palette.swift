import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(uiColor: UIColor(hex: hex, alpha: opacity))
    }

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    init(light: UInt32, lightAlpha: CGFloat, dark: UInt32, darkAlpha: CGFloat) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        })
    }
}

enum Palette {
    static let background = Color(light: 0xEEEEF3, dark: 0x070708)
    static let surface = Color(light: 0xFFFFFF, lightAlpha: 1, dark: 0x101010, darkAlpha: 1)
    static let surfaceRaised = Color(light: 0xFFFFFF, lightAlpha: 1, dark: 0x141513, darkAlpha: 1)
    static let glassStrong = Color(light: 0xFFFFFF, lightAlpha: 1, dark: 0x101010, darkAlpha: 1)
    static let glassStroke = Color(light: 0xFFFFFF, lightAlpha: 1, dark: 0x252822, darkAlpha: 1)
    static let line = Color(light: 0x1C1C28, lightAlpha: 0.08, dark: 0x252822, darkAlpha: 1)
    static let separator = Color(light: 0x1C1C28, lightAlpha: 0.06, dark: 0x252822, darkAlpha: 1)

    static let textPrimary = Color(light: 0x16161D, dark: 0xF4F6F0)
    static let textSecondary = Color(light: 0x8B8D98, dark: 0x9BA19B)

    static let accent = Color(light: 0xF2762E, dark: 0xD2EDAD)
    static let accentSoft = Color(light: 0xFDE7DA, dark: 0x1D2618)
    static let accentText = Color(light: 0xE0631F, dark: 0xD2EDAD)
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x172212)

    static let success = Color(light: 0x1F8A5A, dark: 0xD2EDAD)
    static let danger = Color(light: 0xE04B3A, dark: 0xEFB7AC)

    static let tabSelectedBackground = Color(light: 0xFDE7DA, dark: 0xD2EDAD)
    static let tabSelectedForeground = Color(light: 0xE0631F, dark: 0x172212)

    static let toggleOn = Color(light: 0xF2762E, dark: 0xAEC78D)
    static let toggleOff = Color(light: 0xDCDCE3, dark: 0x4A565D)
    static let toggleKnobOn = Color(light: 0xFFFFFF, dark: 0x172212)
    static let toggleKnobOff = Color(light: 0xFFFFFF, dark: 0xEAF2ED)

    static let primaryGradient = LinearGradient(
        colors: [Color(hex: 0xF5853F), Color(hex: 0xF06A24)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let primaryGlow = Color(hex: 0xF2762E, opacity: 0.3)
    static let shadow = Color(hex: 0x1C1C28)

    static let heroBackground = Color(light: 0xFAFAFA, dark: 0x0A0A0A)

    static let notice = Color(light: 0xFFFFFF, lightAlpha: 1, dark: 0x182013, darkAlpha: 1)
    static let noticeBorder = Color(light: 0xFFFFFF, lightAlpha: 1, dark: 0x3B4C2E, darkAlpha: 1)
    static let noticeText = Color(light: 0xE0631F, dark: 0xD2EDAD)
    static let noticeDot = Color(light: 0xF2762E, dark: 0xD2EDAD)

    static let scrim = Color(light: 0x16161D, lightAlpha: 0.25, dark: 0x000000, darkAlpha: 0.667)
    static let sheet = Color(light: 0xFFFFFF, dark: 0x181B16)
    static let sheetBorder = Color(light: 0xFFFFFF, dark: 0x394330)
    static let checkboxBorder = Color(light: 0xCACAD3, dark: 0x4A565D)
    static let iconMuted = Color(light: 0x9EA0AA, dark: 0x9BA19B)
}

enum CaptionPalette {
    static let card = Color(light: 0xFFFFFF, lightAlpha: 1, dark: 0x141715, darkAlpha: 1)
    static let border = Color(light: 0xFFFFFF, lightAlpha: 1, dark: 0x2A302A, darkAlpha: 1)
    static let latestActiveCard = Color(light: 0xFDE7DA, dark: 0x2E2418)
    static let latestActiveBorder = Color(light: 0xF5BFA0, dark: 0x5A4326)
    static let latestActiveTag = Color(light: 0xF2762E, dark: 0xE8A184)
    static let time = Color(light: 0x9EA0AA, dark: 0x929B8E)
    static let text = Color(light: 0x16161D, dark: 0xEEF1E9)
    static let source = Color(light: 0x6E717C, dark: 0xA4ADA1)

    static let returnBackground = Color(light: 0xFFFFFF, lightAlpha: 1, dark: 0x2A3521, darkAlpha: 1)
    static let returnBorder = Color(light: 0xFFFFFF, dark: 0x485C34)
    static let returnText = Color(light: 0xE0631F, dark: 0xD2EDAD)

    static let errorBackground = Color(light: 0xFDF1EF, dark: 0x241B18)
    static let errorBorder = Color(light: 0xF5CBC3, dark: 0x5B3F34)
    static let errorText = Color(light: 0xC04A35, dark: 0xEFBBAB)

    static let warnBackground = Color(light: 0xFDF6E8, dark: 0x272215)
    static let warnBorder = Color(light: 0xF0E2B8, dark: 0x584B2C)
    static let warnText = Color(light: 0x8A6D2A, dark: 0xE8D298)
}

enum PickerPalette {
    static let triggerOpen = Color(light: 0xF2762E, lightAlpha: 0.08, dark: 0x181A17, darkAlpha: 1)
    static let selectedBackground = Color(light: 0xFDE7DA, dark: 0x1D2618)
    static let selectedText = Color(light: 0xE0631F, dark: 0xD2EDAD)
    static let menuShadow = Color(light: 0x1C1C28, lightAlpha: 0.14, dark: 0x000000, darkAlpha: 0.22)
}

enum BadgePalette {
    static let onBackground = Color(light: 0xE5F7EE, lightAlpha: 0.85, dark: 0x0A0C07, darkAlpha: 0.62)
    static let onBorder = Color(light: 0x1E7A3C, lightAlpha: 0.08, dark: 0xF4F6F0, darkAlpha: 0.14)
    static let onText = Color(light: 0x1F8A5A, dark: 0xD2EDAD)

    static let neutralBackground = Color(light: 0xFFFFFF, lightAlpha: 0.9, dark: 0x0A0C07, darkAlpha: 0.62)
    static let neutralBorder = Color(light: 0xFFFFFF, lightAlpha: 0.9, dark: 0xF4F6F0, darkAlpha: 0.14)
    static let neutralText = Color(light: 0x3A3C46, dark: 0xD2EDAD)

    static let offBackground = Color(light: 0xFDEEE9, lightAlpha: 0.94, dark: 0x0A0C07, darkAlpha: 0.62)
    static let offBorder = Color(light: 0xC04A35, lightAlpha: 0.10, dark: 0xF4F6F0, darkAlpha: 0.14)
    static let offText = Color(light: 0xC04A35, dark: 0xEFB7AC)

    static let shadow = Color(light: 0x1C1C28, lightAlpha: 0.1, dark: 0x000000, darkAlpha: 0.38)
}
