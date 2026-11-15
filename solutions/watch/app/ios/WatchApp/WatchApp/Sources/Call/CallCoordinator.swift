import Foundation

@MainActor
final class CallCoordinator {
    private let signalTransport: CallSignalTransport
    private let stateStore = CallStateStore()
    private let mediaSession = CallMediaSession()
    private lazy var signaling: CallSignaling = CallSignaling(
        transport: signalTransport,
        onStateChange: { [weak self] state in self?.handleSignalState(state) }
    )
    private var callObservers: [UUID: (CallUIState) -> Void] = [:]

    init(signalTransport: CallSignalTransport) {
        self.signalTransport = signalTransport
        stateStore.onChange = { [weak self] state in
            self?.callObservers.values.forEach { $0(state) }
        }
        mediaSession.onEvent = { [weak self] event in
            self?.handleMediaEvent(event)
        }
    }

    var state: CallUIState {
        stateStore.state
    }

    func attach(session: Any?) {
        mediaSession.attach(session: session)
    }

    func detach() {
        mediaSession.detach()
    }

    func transportUnavailable() {
        signaling.onTransportUnavailable()
    }

    func logout() {
        signaling.onTransportUnavailable()
        signaling.hangup()
        callObservers.removeAll()
        mediaSession.hangup()
        stateStore.finish(reason: .localHangup)
        mediaSession.detach()
    }

    @discardableResult
    func addStateObserver(_ observer: @escaping (CallUIState) -> Void) -> UUID {
        let id = UUID()
        callObservers[id] = observer
        observer(stateStore.state)
        return id
    }

    func removeStateObserver(_ id: UUID) {
        callObservers.removeValue(forKey: id)
    }

    @discardableResult
    func startCall(target: CallTarget, mediaType: CallMediaType) -> Bool {
        stateStore.startOutgoing(target: target, mediaType: mediaType)
        guard signaling.startOutgoing(target: target, mediaType: mediaType) else {
            stateStore.finish(reason: .unknown)
            return false
        }
        guard mediaSession.startCall(target: target, mediaType: mediaType) else {
            signaling.markMediaEnded(reason: "media_start_failed")
            stateStore.finish(reason: .unknown)
            return false
        }
        return true
    }

    @discardableResult
    func acceptIncoming() -> Bool {
        let target = stateStore.state.target
        guard mediaSession.prepareIncomingMedia(target: target) else { return false }
        return signaling.acceptIncoming()
    }

    @discardableResult
    func rejectIncoming() -> Bool {
        let result = signaling.rejectIncoming()
        if result {
            mediaSession.finish()
            stateStore.finish(reason: .localHangup)
        }
        return result
    }

    func hangup() {
        signaling.hangup()
        mediaSession.hangup()
        stateStore.finish(reason: .localHangup)
    }

    func bindRemote(_ surface: CallVideoSurface) {
        surface.bindRemote(using: mediaSession)
    }

    func startLocalVideo(_ surface: CallVideoSurface) {
        surface.startLocalVideo(using: mediaSession)
    }

    func setMicrophoneEnabled(_ enabled: Bool) {
        mediaSession.setMicrophoneEnabled(enabled)
    }

    func setCameraEnabled(_ enabled: Bool, surface: CallVideoSurface) {
        surface.setCameraEnabled(enabled, using: mediaSession)
    }

    func switchCamera() {
        mediaSession.switchCamera()
    }

    func setSpeakerphoneEnabled(_ enabled: Bool) {
        mediaSession.setSpeakerphoneEnabled(enabled)
    }

    private func handleSignalState(_ state: CallSignalState) {
        switch state.phase {
        case .outgoing:
            break
        case .incoming:
            let userID = signalTransport.localUserID ?? ""
            let bound = WatchBindingStore.all(userID: userID).first { $0.deviceName == state.peerID }
            let targetName = bound?.deviceName ?? state.peerID
            let target = CallTarget(
                productId: bound?.productId ?? WatchSdkConfig.boundWatchProductId,
                deviceName: targetName,
                displayName: targetName,
                avatarID: targetName
            )
            stateStore.incoming(target: target, mediaType: state.mediaType, sessionID: state.sessionID)
        case .active:
            stateStore.active(mediaType: state.mediaType)
        case .idle:
            if stateStore.state.phase != .idle {
                mediaSession.finish()
                stateStore.finish(reason: .remoteHangup)
            }
        }
    }

    private func handleMediaEvent(_ event: CallMediaEvent) {
        switch event {
        case .began(let mediaType):
            signaling.markMediaActive()
            stateStore.active(mediaType: mediaType)
        case .remoteAudioAvailable(let available):
            if available { signaling.markMediaActive(); stateStore.active() }
        case .remoteVideoAvailable(let available):
            if available { signaling.markMediaActive(); stateStore.active() }
            stateStore.remoteVideoAvailable(available)
        case .ended(let reason):
            signaling.markMediaEnded()
            mediaSession.finish()
            stateStore.finish(reason: reason)
        }
    }
}
