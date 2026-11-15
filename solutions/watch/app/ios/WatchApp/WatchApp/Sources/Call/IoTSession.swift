import Foundation
#if canImport(TXLiteAVSDK_IOT)
import TXLiteAVSDK_IOT
#endif

enum IoTLoginState: Equatable {
    case loggedOut
    case loggingIn
    case loggedIn(userId: String)
    case failed(code: String, message: String)
}

@MainActor
final class IoTSession {
    private(set) var loginState: IoTLoginState = .loggedOut {
        didSet { onLoginStateChange?(loginState) }
    }
    var onLoginStateChange: ((IoTLoginState) -> Void)?
    private var activeUserId: String?
    private var activeConfig: IotSessionConfig?

    #if canImport(TXLiteAVSDK_IOT)
    private let engine = TXIoTEngine.getInstance()
    private let delegateProxy = EngineDelegateProxy()
    #endif

    init() {
        #if canImport(TXLiteAVSDK_IOT)
        delegateProxy.loginSucceeded = { [weak self] in self?.loginSucceeded() }
        delegateProxy.loginFailed = { [weak self] code, message in
            self?.loginState = .failed(code: code, message: message)
        }
        delegateProxy.loggedOut = { [weak self] in
            self?.activeUserId = nil
            self?.loginState = .loggedOut
        }
        delegateProxy.signatureExpired = { [weak self] in
            guard let self, let config = self.activeConfig else { return }
            self.login(config: config)
        }
        engine.add(delegateProxy)
        #endif
    }

    func login(config: IotSessionConfig) {
        activeConfig = config
        if config.appSecret == "watch_local_secret" {
            loginState = .failed(code: "SDK_UNAVAILABLE", message: "LOCAL_UI_ONLY_CREDENTIALS")
            return
        }
        #if canImport(TXLiteAVSDK_IOT)
        loginState = .loggingIn
        do {
            let credentials = try IoTSignatureProviders.require().fetchSignature(config: config)
            activeUserId = credentials.requestId
            let signature = TXIoTUserSignature()
            signature.requestId = credentials.requestId
            signature.timestamp = credentials.timestamp
            signature.nonce = credentials.nonce
            signature.signature = credentials.signature
            engine.login(credentials.appKey, userId: credentials.loginId, userSignature: signature, region: .default)
            WatchLogger.ui.info("IoT login requested, room=\(credentials.loginId, privacy: .private(mask: .hash))")
        } catch {
            loginState = .failed(code: "SIGNATURE_UNAVAILABLE", message: error.localizedDescription)
        }
        #else
        loginState = .failed(code: "SDK_UNAVAILABLE", message: "TXLiteAVSDK_IOT unavailable")
        #endif
    }

    func logout() {
        #if canImport(TXLiteAVSDK_IOT)
        engine.logout()
        #endif
        activeUserId = nil
        activeConfig = nil
        loginState = .loggedOut
    }

    func release() {
        #if canImport(TXLiteAVSDK_IOT)
        engine.remove(delegateProxy)
        #endif
    }

    #if canImport(TXLiteAVSDK_IOT)
    func callSession() -> TXIoTCallSession? { engine.getCallSession() }

    private func loginSucceeded() {
        guard let activeUserId else { loginState = .loggedOut; return }
        loginState = .loggedIn(userId: activeUserId)
    }

    private final class EngineDelegateProxy: NSObject, TXIoTEngineDelegate {
        var loginSucceeded: (() -> Void)?
        var loginFailed: ((String, String) -> Void)?
        var loggedOut: (() -> Void)?
        var signatureExpired: (() -> Void)?

        func onLoginSuccess() { Task { @MainActor in self.loginSucceeded?() } }
        func onLoginFailure(_ errCode: TXIoTErrorCode, errMsg: String) { Task { @MainActor in self.loginFailed?("\(errCode.rawValue)", errMsg) } }
        func onLogout() { Task { @MainActor in self.loggedOut?() } }
        func onUserSignatureExpired() { Task { @MainActor in self.signatureExpired?() } }
    }
    #endif
}
