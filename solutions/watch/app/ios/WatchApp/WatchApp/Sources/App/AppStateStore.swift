import Foundation

@MainActor
final class AppStateStore {
    enum Tab: Equatable {
        case messages
        case location
        case devices
        case profile
    }

    private(set) var isAuthenticated = false
    private(set) var selectedTab: Tab = .messages
    private let engine = IoTSession()
    let imService = ImService()
    var imManager: ImService { imService }
    private lazy var signalTransport = ImCallSignalTransport(manager: imService)
    private lazy var callCoordinator = CallCoordinator(signalTransport: signalTransport)
    var onLoginStateChange: ((IoTLoginState) -> Void)?
    private var isLoggingOut = false

    init() {
        IoTSignatureProviders.install(TrtcSignatureProvider())
        engine.onLoginStateChange = { [weak self] state in
            if case .loggedIn = state {
                self?.isAuthenticated = true
                self?.selectedTab = .messages
                #if canImport(TXLiteAVSDK_IOT)
                self?.callCoordinator.attach(session: self?.engine.callSession())
                #else
                self?.callCoordinator.attach(session: nil)
                #endif
            }
            self?.onLoginStateChange?(state)
        }
        imService.onLoginStateChange = { [weak self] state in
            switch state {
            case .loggingIn:
                self?.onLoginStateChange?(.loggingIn)
            case .failed(let code, _):
                self?.onLoginStateChange?(.failed(code: "IMSDK_\(code)", message: "IMSDK_LOGIN_FAILED"))
            case .loggedOut:
                self?.callCoordinator.transportUnavailable()
            case .loggedIn:
                break
            }
        }
        _ = callCoordinator
    }

    func authenticate() {
        isAuthenticated = true
        selectedTab = .messages
    }

    func login(channel: String, appID: String, appSecret: String) {
        imService.login(channel: channel)
        engine.login(config: IotSessionConfig(
            channel: channel.trimmingCharacters(in: .whitespacesAndNewlines),
            appID: appID.trimmingCharacters(in: .whitespacesAndNewlines),
            appSecret: appSecret
        ))
    }

    func logout() {
        guard !isLoggingOut else { return }
        isLoggingOut = true
        isAuthenticated = false
        selectedTab = .messages

        callCoordinator.logout()
        imService.logout { [weak self] in
            self?.isLoggingOut = false
        }
        engine.logout()
    }


    func select(_ tab: Tab) {
        guard isAuthenticated else { return }
        selectedTab = tab
    }

    @discardableResult
    func addCallStateObserver(_ observer: @escaping (CallUIState) -> Void) -> UUID {
        callCoordinator.addStateObserver(observer)
    }

    func removeCallStateObserver(_ id: UUID) {
        callCoordinator.removeStateObserver(id)
    }

    func startCall(target: CallTarget, mediaType: CallMediaType) -> Bool {
        callCoordinator.startCall(target: target, mediaType: mediaType)
    }

    func acceptIncoming() -> Bool {
        callCoordinator.acceptIncoming()
    }

    func rejectIncoming() -> Bool {
        callCoordinator.rejectIncoming()
    }

    func hangupCall() {
        callCoordinator.hangup()
    }
    func bindRemote(_ surface: CallVideoSurface) { callCoordinator.bindRemote(surface) }
    func startLocalVideo(_ surface: CallVideoSurface) { callCoordinator.startLocalVideo(surface) }
    func setMicrophoneEnabled(_ enabled: Bool) { callCoordinator.setMicrophoneEnabled(enabled) }
    func setCameraEnabled(_ enabled: Bool, surface: CallVideoSurface) { callCoordinator.setCameraEnabled(enabled, surface: surface) }
    func switchCamera() { callCoordinator.switchCamera() }
    func setSpeakerphoneEnabled(_ enabled: Bool) { callCoordinator.setSpeakerphoneEnabled(enabled) }
    func callState() -> CallUIState { callCoordinator.state }
}
