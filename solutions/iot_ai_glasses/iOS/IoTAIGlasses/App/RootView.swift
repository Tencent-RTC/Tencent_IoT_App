import SwiftUI

struct RootView: View {
    @State private var router = AppRouter()
    @State private var state = AppState()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                tab(.home) {
                    NavigationStack(path: $router.homePath) { HomeView().appRouteDestinations() }
                }
                tab(.records) {
                    NavigationStack(path: $router.recordsPath) { RecordsView().appRouteDestinations() }
                }
                tab(.device) {
                    NavigationStack(path: $router.devicePath) { DeviceView().appRouteDestinations() }
                }
            }
            .overlay(alignment: .bottom) {
                if router.showsTabBar {
                    BottomTabBar(selection: router.selectedTab, onSelect: router.select)
                        .padding(.bottom, proxy.safeAreaInsets.bottom > 0 ? 0 : 10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .overlay {
                DialogHost()
            }
            .overlay(alignment: .bottom) {
                if let toast = state.toast {
                    ToastView(text: toast.text)
                        .padding(.bottom, router.showsTabBar ? 84 : 150)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .id(toast.id)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: router.showsTabBar)
            .animation(.easeOut(duration: 0.2), value: state.toast)
        }
        .background(AppBackdrop().ignoresSafeArea())
        .environment(router)
        .environment(state)
        .onChange(of: state.toast) { _, toast in
            if let toast {
                AccessibilityNotification.Announcement(toast.text).post()
            }
        }
    }

    private func tab<Content: View>(_ tab: AppTab, @ViewBuilder content: () -> Content) -> some View {
        let active = router.selectedTab == tab
        return content()
            .opacity(active ? 1 : 0)
            .allowsHitTesting(active)
            .accessibilityHidden(!active)
    }
}
