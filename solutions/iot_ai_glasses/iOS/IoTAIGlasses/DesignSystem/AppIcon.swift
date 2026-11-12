import SwiftUI

enum AppIcon: String, CaseIterable {
    case home = "menu-home"
    case records = "menu-record"
    case glasses = "menu-glasses"
    case listen = "menu-listen"
    case meeting = "menu-meeting"
    case interpret = "menu-translate"
    case callFeature = "menu-call"
    case chatFeature = "menu-chat"
    case language = "menu-language"
    case speaker = "menu-speaker"

    case arrow = "icon-arrow"
    case back = "icon-back"
    case mic = "icon-mic"
    case pause = "icon-pause"
    case play = "icon-play"
    case stop = "icon-stop"
    case swap = "icon-swap"
    case check = "icon-check"
    case close = "icon-close"
    case download = "icon-download"
    case more = "icon-more"
    case call = "icon-call"
    case chat = "icon-chat"
    case mute = "icon-mute"
    case sun = "icon-sun"
    case moon = "icon-moon"
    case chevronDown = "icon-chevron-down"
    case signal = "icon-signal"
}

struct AppIconView: View {
    let icon: AppIcon
    let size: CGFloat

    init(_ icon: AppIcon, size: CGFloat = 20) {
        self.icon = icon
        self.size = size
    }

    var body: some View {
        Image(icon.rawValue)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
