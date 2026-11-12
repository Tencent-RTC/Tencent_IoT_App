import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case records
    case device

    var id: Self { self }

    var title: String {
        switch self {
        case .home: "首页"
        case .records: "记录"
        case .device: "设备"
        }
    }

    var icon: AppIcon {
        switch self {
        case .home: .home
        case .records: .records
        case .device: .glasses
        }
    }
}

enum AppRoute: Hashable {
    case interpretPrep
    case calls
    case chat
    case live(SessionKind)
    case recordDetail(UUID)
}

@Observable
final class AppRouter {
    var selectedTab: AppTab = .home
    var homePath = NavigationPath()
    var recordsPath = NavigationPath()
    var devicePath = NavigationPath()

    var showsTabBar: Bool {
        switch selectedTab {
        case .home: homePath.isEmpty
        case .records: recordsPath.isEmpty
        case .device: devicePath.isEmpty
        }
    }

    func select(_ tab: AppTab) {
        if selectedTab == tab {
            popToRoot(tab)
        } else {
            selectedTab = tab
        }
    }

    func push(_ route: AppRoute) {
        switch selectedTab {
        case .home: homePath.append(route)
        case .records: recordsPath.append(route)
        case .device: devicePath.append(route)
        }
    }

    func replaceTop(with route: AppRoute) {
        pop()
        push(route)
    }

    func popToRoot() {
        popToRoot(selectedTab)
    }

    func pop() {
        switch selectedTab {
        case .home: if !homePath.isEmpty { homePath.removeLast() }
        case .records: if !recordsPath.isEmpty { recordsPath.removeLast() }
        case .device: if !devicePath.isEmpty { devicePath.removeLast() }
        }
    }

    func popToRoot(_ tab: AppTab) {
        switch tab {
        case .home: homePath = NavigationPath()
        case .records: recordsPath = NavigationPath()
        case .device: devicePath = NavigationPath()
        }
    }
}
