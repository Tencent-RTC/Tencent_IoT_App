import Foundation
import TXLiteAVSDK_VoiceAI_iOS

struct ASRSegment {
    let segmentId: String
    let text: String
    let isCompleted: Bool
    let speakerId: Int
}

enum RealtimeASREvent {
    case started(voiceId: String)
    case segment(ASRSegment)
    case stopped
    case failed(code: Int, message: String)
    case volume(Int)
}

@MainActor
final class RealtimeASRService {
    var onEvent: ((RealtimeASREvent) -> Void)?
    private(set) var isRunning = false

    private let engine = TXRealtimeASR()
    private let bridge = ASRListenerBridge()

    init() {
        bridge.owner = self
        engine.addListener(bridge)
    }

    func start(language: Language?, sdkAppId: Int, secretKey: String, speakerDiarization: Bool = false, denoiseStrategy: Int? = nil) {
        guard !isRunning else { return }
        var extra: [String: Any] = ["extraRequestParams": speakerDiarization ? "speaker_diarization=1" : ""]
        if let denoiseStrategy { extra["clientDenoiseStrategy"] = denoiseStrategy }
        if let data = try? JSONSerialization.data(withJSONObject: ["api": "setExtraParams", "params": extra]),
           let json = String(data: data, encoding: .utf8) {
            _ = engine.callExperimentalAPI(json)
        }
        let voiceId = UUID().uuidString
        let params = TXRealtimeASRParams()
        params.sdkAppId = String(sdkAppId)
        params.userSig = GenerateTestUserSig.genTestUserSig(sdkAppId: sdkAppId, userId: voiceId, secrectkey: secretKey)
        params.voiceId = voiceId
        params.sourceLanguage = language?.trtcCode ?? ""
        params.enableCustomCapture = false
        isRunning = true
        engine.startRealtimeASR(params)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        engine.stopRealtimeASR()
    }

    fileprivate func handle(_ event: RealtimeASREvent) {
        if case .failed = event { isRunning = false }
        onEvent?(event)
    }
}

private final class ASRListenerBridge: NSObject, TXRealtimeASRListener {
    weak var owner: RealtimeASRService?

    private func forward(_ event: RealtimeASREvent) {
        MainActor.assumeIsolated { owner?.handle(event) }
    }

    func onRealtimeASRStarted(_ voiceId: String) {
        forward(.started(voiceId: voiceId))
    }

    func onReceiveRealtimeASRMessage(_ message: TXRealtimeASRMessage) {
        forward(.segment(ASRSegment(
            segmentId: message.segmentId,
            text: message.sourceText,
            isCompleted: message.isCompleted,
            speakerId: Int(message.speakerId)
        )))
    }

    func onRealtimeASRStopped() {
        forward(.stopped)
    }

    func onRealtimeASRError(_ errorCode: Int32, errorMsg: String) {
        forward(.failed(code: Int(errorCode), message: errorMsg))
    }

    func onRealtimeASRVolume(_ volume: Int32) {
        forward(.volume(Int(volume)))
    }
}
