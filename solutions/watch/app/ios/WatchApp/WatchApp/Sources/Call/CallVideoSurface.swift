import UIKit

@MainActor
protocol CallVideoSurface: AnyObject {
    func bindRemote(using controller: CallMediaSession)
    func startLocalVideo(using controller: CallMediaSession)
    func setCameraEnabled(_ enabled: Bool, using controller: CallMediaSession)
}

/// iOS 页面到 IoT 媒体适配器的视频 View 适配。
@MainActor
final class UIKitCallVideoSurface: CallVideoSurface {
    private let view: UIView

    init(view: UIView) {
        self.view = view
    }

    func bindRemote(using controller: CallMediaSession) {
        controller.bindRemoteView(view)
    }

    func startLocalVideo(using controller: CallMediaSession) {
        controller.startLocalVideo(view)
    }

    func setCameraEnabled(_ enabled: Bool, using controller: CallMediaSession) {
        controller.setCameraEnabled(enabled, view: view)
    }
}
