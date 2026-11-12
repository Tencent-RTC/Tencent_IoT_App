import SwiftUI

struct RouteDestination: View {
    let route: AppRoute

    @Environment(AppState.self) private var state

    var body: some View {
        switch route {
        case .interpretPrep:
            InterpretPrepView()
        case .calls:
            CallJoinView()
        case .chat:
            ChatView()
        case .live(.translation):
            TranslationLiveView()
        case .live(.interpret):
            InterpretLiveView()
        case .live(.meeting):
            MeetingLiveView()
        case .live(.call):
            CallLiveView()
        case .recordDetail(let id):
            if state.records.first(where: { $0.id == id })?.kind == .meeting {
                MeetingDetailView(recordID: id)
            } else {
                TranslationDetailView(recordID: id)
            }
        }
    }
}

extension View {
    func appRouteDestinations() -> some View {
        navigationDestination(for: AppRoute.self) { RouteDestination(route: $0) }
    }
}
