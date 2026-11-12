import Foundation
import TXLiteAVSDK_VoiceAI_iOS

enum RealtimeTTSEvent {
    case started
    case finished(ok: Bool, code: Int, message: String)
}

@MainActor
final class RealtimeTTSService {
    var onEvent: ((RealtimeTTSEvent) -> Void)?
    private(set) var isSpeaking = false

    private let engine = TXRealtimeTTS()
    private let bridge = TTSListenerBridge()
    private var sessionActive = false
    private var sessionStarted = false

    init() {
        bridge.owner = self
        engine.setListener(bridge)
    }

    func speak(_ text: String, language: Language? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if sessionActive { engine.stop() }
        if let language {
            _ = engine.callExperimentalAPI(#"{"api":"setOnlineTTSExtraParams","params":{"Language":"\#(language.trtcCode)"}}"#)
        }
        let userId = "tts_" + UUID().uuidString.prefix(8).lowercased()
        let params = TXRealtimeTTSParams()
        let online = TXRealtimeTTSOnlineCredential()
        online.appId = String(TRTCCredentials.sdkAppId)
        online.userId = userId
        online.userSig = TRTCCredentials.userSig(for: userId)
        params.online = online
        params.voiceName = Self.voiceName
        let code = engine.start(params)
        guard code == 0 else {
            onEvent?(.finished(ok: false, code: Int(code), message: "start failed"))
            return
        }
        engine.appendText(UUID().uuidString, text: trimmed, isEnd: true)
        sessionActive = true
        sessionStarted = false
        isSpeaking = true
    }

    func stop() {
        guard sessionActive else { return }
        sessionActive = false
        isSpeaking = false
        engine.stop()
    }

    fileprivate func handle(_ event: RealtimeTTSEvent) {
        switch event {
        case .started:
            sessionStarted = true
        case .finished(let ok, let code, let message):
            guard sessionActive else { return }
            if ok && !sessionStarted { return }
            sessionActive = false
            isSpeaking = false
            onEvent?(.finished(ok: ok, code: code, message: message))
        }
    }

    private static let voiceName = "v-male-s5NqE0rZ"
}

private final class TTSListenerBridge: NSObject, TXRealtimeTTSListener {
    weak var owner: RealtimeTTSService?

    private func forward(_ event: RealtimeTTSEvent) {
        MainActor.assumeIsolated { owner?.handle(event) }
    }

    func onStarted() {
        forward(.started)
    }

    func onCompleted(_ code: Int32, msg: String?) {
        forward(.finished(ok: code == 0, code: Int(code), message: msg ?? ""))
    }
}
