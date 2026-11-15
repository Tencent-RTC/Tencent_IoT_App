import Foundation
import UIKit

#if canImport(TXLiteAVSDK_IOT)
import UIKit
import TXLiteAVSDK_IOT
#endif

enum CallMediaEvent {
    case began(CallMediaType)
    case ended(CallEndReason)
    case remoteAudioAvailable(Bool)
    case remoteVideoAvailable(Bool)
}

@MainActor
final class CallMediaSession {
    var onEvent: ((CallMediaEvent) -> Void)?
    private var frontCamera = true

    #if canImport(TXLiteAVSDK_IOT)
    private var session: TXIoTCallSession?
    private var remoteUser: TXIoTCallUser?
    private weak var pendingRemoteView: UIView?
    private var delegateAttached = false
    private let delegate = CallDelegateProxy()
    #endif

    init() {
        #if canImport(TXLiteAVSDK_IOT)
        delegate.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        #endif
    }

    func attach(session: Any?) {
        #if canImport(TXLiteAVSDK_IOT)
        guard let session = session as? TXIoTCallSession else { return }
        if delegateAttached {
            self.session?.remove(delegate)
        }
        self.session = session
        self.session?.add(delegate)
        delegateAttached = true
        #endif
    }

    func detach() {
        #if canImport(TXLiteAVSDK_IOT)
        session?.remove(delegate)
        session = nil
        remoteUser = nil
        pendingRemoteView = nil
        delegateAttached = false
        #endif
    }

    func startCall(target: CallTarget, mediaType: CallMediaType) -> Bool {
        frontCamera = true
        #if canImport(TXLiteAVSDK_IOT)
        guard let session else { return false }
        let device = TXIoTDeviceId()
        device.productId = target.productId
        device.deviceName = target.deviceName
        if remoteUser == nil {
            let user = TXIoTCallUser()
            user.deviceId = device
            remoteUser = user
        }
        session.callDevice(device, call: mediaType.sdkValue)
        if let pendingRemoteView { bindRemoteViewIfPossible(pendingRemoteView) }
        #else
        #endif
        return true
    }

    /// 新版 Framework 不再提供 IoT 层 acceptCall；来电确认由 IMSDK 信令完成，这里只准备媒体用户。
    func prepareIncomingMedia(target: CallTarget? = nil) -> Bool {
#if canImport(TXLiteAVSDK_IOT)
        guard session != nil else { return false }
        let user = target?.toCallUser()
        guard let user else { return false }
        remoteUser = user
        return true
#else
        return true
#endif
    }

    func hangup() {
        #if canImport(TXLiteAVSDK_IOT)
        session?.hangup()
        #endif
        finish()
    }

    func bindRemoteView(_ view: UIView) {
        #if canImport(TXLiteAVSDK_IOT)
        pendingRemoteView = view
        bindRemoteViewIfPossible(view)
        #endif
    }

    func startLocalVideo(_ view: UIView) {
#if canImport(TXLiteAVSDK_IOT)
        configureVideoEncoder()
        session?.open(frontCamera ? .front : .back, view: view)
#endif
    }

    func setMicrophoneEnabled(_ enabled: Bool) {
#if canImport(TXLiteAVSDK_IOT)
        if enabled { session?.openMicrophone() } else { session?.closeMicrophone() }
#endif
    }

    func setCameraEnabled(_ enabled: Bool, view: UIView? = nil) {
#if canImport(TXLiteAVSDK_IOT)
        if enabled, let view { session?.open(frontCamera ? .front : .back, view: view) } else if !enabled { session?.closeCamera() }
#endif
    }

    func switchCamera() {
#if canImport(TXLiteAVSDK_IOT)
        frontCamera.toggle()
        session?.switch(frontCamera ? .front : .back)
#endif
    }

    func setSpeakerphoneEnabled(_ enabled: Bool) {
#if canImport(TXLiteAVSDK_IOT)
        session?.select(enabled ? .speakerphone : .earpiece)
#endif
    }

    func finish() {
#if canImport(TXLiteAVSDK_IOT)
        if let session, let remoteUser { session.stopRemoteView(remoteUser) }
        session?.closeCamera()
        session?.closeMicrophone()
        remoteUser = nil
        pendingRemoteView = nil
#endif
        frontCamera = true
    }

    /// TXIoTCallSession 没有独立的视频编码参数接口；它与当前 IoT SDK 共用 TRTC 主路编码器。
    /// 640×360 + Portrait 的实际编码方向为 360×640。
    #if canImport(TXLiteAVSDK_IOT)
    private func configureVideoEncoder() {
        let params = TRTCVideoEncParam()
        params.videoResolution = TRTCVideoResolution(rawValue: 108)!
        params.resMode = TRTCVideoResolutionMode(rawValue: 1)!
        params.videoFps = 15
        params.videoBitrate = 500
        params.minVideoBitrate = 0
        params.enableAdjustRes = false
        TRTCCloud.sharedInstance().setVideoEncoderParam(params)
        WatchLogger.ui.info("IoT video encoder configured: 360x640, fps=15, bitrate=500kbps")
    }
    #endif

        #if canImport(TXLiteAVSDK_IOT)
    private enum Event {
        case begin(TXIoTCallMediaType)
        case end
        case rejected
        case noResponse
        case busy
        case offline
        case video(TXIoTCallUser, Bool)
        case audio(TXIoTCallUser, Bool)
        case error
    }

    private func handle(_ event: Event) {
        switch event {
        case .begin(let mediaType):
            onEvent?(.began(mediaType.appValue))
            session?.openMicrophone()
        case let .video(user, available):
            remoteUser = user
            if let pendingRemoteView { bindRemoteViewIfPossible(pendingRemoteView) }
            onEvent?(.remoteVideoAvailable(available))
            if available {
                onEvent?(.began(.video))
                session?.openMicrophone()
            }
        case let .audio(user, available):
            remoteUser = user
            if let pendingRemoteView { bindRemoteViewIfPossible(pendingRemoteView) }
            onEvent?(.remoteAudioAvailable(available))
            if available {
                onEvent?(.began(.audio))
                session?.openMicrophone()
            }
        case .end, .rejected, .noResponse, .busy, .offline, .error:
            onEvent?(.ended(.remoteHangup))
            finish()
        }
    }

    private func bindRemoteViewIfPossible(_ view: UIView) {
        if let session, let remoteUser { session.startRemoteView(remoteUser, view: view) }
    }

    private final class CallDelegateProxy: NSObject, TXIoTCallDelegate {
        var onEvent: ((Event) -> Void)?
        func onError(_ errorCode: TXIoTErrorCode, errorMessage: String) { onEvent?(.error) }
        func onCallBegin(_ mediaType: TXIoTCallMediaType) { onEvent?(.begin(mediaType)) }
        func onCallEnd(_ mediaType: TXIoTCallMediaType, reason: TXIoTCallEndReason) { onEvent?(.end) }
        func onCallRejected(_ callUser: TXIoTCallUser) { onEvent?(.rejected) }
        func onCallNoResponse(_ callUser: TXIoTCallUser) { onEvent?(.noResponse) }
        func onCallLineBusy(_ callUser: TXIoTCallUser) { onEvent?(.busy) }
        func onCallUserOffline(_ callUser: TXIoTCallUser) { onEvent?(.offline) }
        func onCallUserAudioAvailable(_ callUser: TXIoTCallUser, available: Bool) { onEvent?(.audio(callUser, available)) }
        func onCallUserVideoAvailable(_ callUser: TXIoTCallUser, available: Bool) { onEvent?(.video(callUser, available)) }
    }
#endif
}

#if canImport(TXLiteAVSDK_IOT)
private extension CallMediaType {
    var sdkValue: TXIoTCallMediaType { self == .audio ? .audio : .video }
}

private extension TXIoTCallMediaType {
    var appValue: CallMediaType { self == .audio ? .audio : .video }
}

private extension CallTarget {
    #if canImport(TXLiteAVSDK_IOT)
    func toCallUser() -> TXIoTCallUser? {
        guard !productId.isEmpty || !deviceName.isEmpty else { return nil }
        let device = TXIoTDeviceId()
        device.productId = productId
        device.deviceName = deviceName
        let user = TXIoTCallUser()
        user.deviceId = device
        return user
    }
    #endif
}
#endif
