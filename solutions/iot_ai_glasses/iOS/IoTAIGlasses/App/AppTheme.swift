import SwiftUI

enum AppTheme: String {
    case soft
    case dark

    static let storageKey = "appTheme"

    var colorScheme: ColorScheme {
        self == .dark ? .dark : .light
    }

    var toggled: AppTheme {
        self == .dark ? .soft : .dark
    }
}
