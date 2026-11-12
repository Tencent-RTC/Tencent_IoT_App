import Foundation
import Observation
import TXLiteAVSDK_Professional

struct TRTCRoomConfig {
    enum RoomID {
        case numeric(UInt32)
        case string(String)
    }

    var sdkAppId: UInt32
    var userId: String
    var userSig: String
    var roomId: RoomID
    var role: TRTCRoleType = .anchor
    var scene: TRTCAppScene = .audioCall
}

struct TranscriberConfig {
    var source: String
    var targets: [Language]
    var robotId: String?
    var userIds: [String] = []
}

struct TranscriptSegment: Equatable {
    let id: String
    let speakerUserId: String
    let sourceText: String
    let translations: [String: String]
    let timestamp: Date
    let isCompleted: Bool

    func translation(_ language: Language) -> String? {
        translations[language.trtcCode]
    }
}

enum TRTCEvent {
    case enteredRoom(elapsedMs: Int)
    case enterRoomFailed(code: Int)
    case exitedRoom(reason: Int)
    case error(code: Int, message: String)
    case connectionLost
    case reconnecting
    case connectionRecovered
    case remoteUserEntered(String)
    case remoteUserLeft(String, reason: Int)
    case remoteAudioAvailable(String, Bool)
    case customMessage(userId: String, cmdID: Int, seq: UInt32, data: Data)
    case transcriberStarted(robotId: String)
    case transcript(TranscriptSegment)
    case transcriberStopped(robotId: String, reason: Int)
    case transcriberError(robotId: String, code: Int, message: String)
}

@MainActor
@Observable
final class TRTCService {
    enum RoomState {
        case idle
        case entering
        case inRoom
        case exiting
    }

    static let shared = TRTCService()

    private(set) var roomState: RoomState = .idle
    private(set) var isReconnecting = false
    private(set) var isLocalAudioStarted = false
    private(set) var isLocalAudioMuted = false
    private(set) var remoteAudioUsers: Set<String> = []
    private(set) var transcriberRobotId: String?
    private(set) var roomId: String?

    @ObservationIgnored private let cloud = TRTCCloud.sharedInstance()
    @ObservationIgnored private let bridge = DelegateBridge()
    @ObservationIgnored private var subscribers: [UUID: AsyncStream<TRTCEvent>.Continuation] = [:]

    private init() {
        bridge.owner = self
        cloud.addDelegate(bridge)
        cloud.getAITranscriberManager().add(bridge)
    }

    func events() -> AsyncStream<TRTCEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: TRTCEvent.self)
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.subscribers[id] = nil }
        }
        return stream
    }

    func enterRoom(_ config: TRTCRoomConfig) {
        guard roomState == .idle else { return }
        let params = TRTCParams()
        params.sdkAppId = config.sdkAppId
        params.userId = config.userId
        params.userSig = config.userSig
        params.role = config.role
        switch config.roomId {
        case .numeric(let id):
            params.roomId = id
            roomId = String(id)
        case .string(let id):
            params.strRoomId = id
            roomId = id
        }
        roomState = .entering
        cloud.enterRoom(params, appScene: config.scene)
    }

    func exitRoom() {
        guard roomState == .entering || roomState == .inRoom else { return }
        roomState = .exiting
        cloud.exitRoom()
    }

    func startLocalAudio(quality: TRTCAudioQuality = .speech) {
        guard !isLocalAudioStarted else { return }
        cloud.startLocalAudio(quality)
        isLocalAudioStarted = true
    }

    func stopLocalAudio() {
        cloud.stopLocalAudio()
        isLocalAudioStarted = false
    }

    func muteLocalAudio(_ mute: Bool) {
        cloud.muteLocalAudio(mute)
        isLocalAudioMuted = mute
    }

    func muteRemoteAudio(_ userId: String, mute: Bool) {
        cloud.muteRemoteAudio(userId, mute: mute)
    }

    func muteAllRemoteAudio(_ mute: Bool) {
        cloud.muteAllRemoteAudio(mute)
    }

    func startTranscriber(_ config: TranscriberConfig) {
        let params = TranscriberParams()
        if let robotId = config.robotId { params.transcriberRobotId = robotId }
        params.sourceLanguage = config.source
        params.translationLanguages = config.targets.map(\.trtcCode)
        params.userIdsToTranscribe = config.userIds
        cloud.getAITranscriberManager().startRealtimeTranscriber(params)
    }

    func stopTranscriber() {
        cloud.getAITranscriberManager().stopRealtimeTranscriber(transcriberRobotId ?? "")
    }

    fileprivate func handle(_ event: TRTCEvent) {
        switch event {
        case .enteredRoom:
            roomState = .inRoom
        case .enterRoomFailed, .exitedRoom:
            resetRoomState()
        case .connectionLost, .reconnecting:
            isReconnecting = true
        case .connectionRecovered:
            isReconnecting = false
        case .remoteAudioAvailable(let userId, let available):
            if available {
                remoteAudioUsers.insert(userId)
            } else {
                remoteAudioUsers.remove(userId)
            }
        case .remoteUserLeft(let userId, _):
            remoteAudioUsers.remove(userId)
        case .transcriberStarted(let robotId):
            transcriberRobotId = robotId
        case .transcriberStopped:
            transcriberRobotId = nil
        default:
            break
        }
        for continuation in subscribers.values {
            continuation.yield(event)
        }
    }

    private func resetRoomState() {
        roomState = .idle
        roomId = nil
        isReconnecting = false
        isLocalAudioStarted = false
        isLocalAudioMuted = false
        remoteAudioUsers = []
        transcriberRobotId = nil
    }
}

extension Language {
    var trtcCode: String {
        switch self {
        case .english: "en"
        case .chinese: "zh"
        }
    }
}

private final class DelegateBridge: NSObject, TRTCCloudDelegate, AITranscriberListener {
    weak var owner: TRTCService?

    private func onMain(_ event: TRTCEvent) {
        MainActor.assumeIsolated { owner?.handle(event) }
    }

    private func hopToMain(_ event: TRTCEvent) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.owner?.handle(event) }
        }
    }

    func onEnterRoom(_ result: Int) {
        onMain(result > 0 ? .enteredRoom(elapsedMs: result) : .enterRoomFailed(code: result))
    }

    func onExitRoom(_ reason: Int) {
        onMain(.exitedRoom(reason: reason))
    }

    func onError(_ errCode: TXLiteAVError, errMsg: String?, extInfo: [AnyHashable: Any]?) {
        onMain(.error(code: Int(errCode.rawValue), message: errMsg ?? ""))
    }

    func onConnectionLost() {
        onMain(.connectionLost)
    }

    func onTryToReconnect() {
        onMain(.reconnecting)
    }

    func onConnectionRecovery() {
        onMain(.connectionRecovered)
    }

    func onRemoteUserEnterRoom(_ userId: String) {
        onMain(.remoteUserEntered(userId))
    }

    func onRemoteUserLeaveRoom(_ userId: String, reason: Int) {
        onMain(.remoteUserLeft(userId, reason: reason))
    }

    func onUserAudioAvailable(_ userId: String, available: Bool) {
        onMain(.remoteAudioAvailable(userId, available))
    }

    func onRecvCustomCmdMsgUserId(_ userId: String, cmdID: Int, seq: UInt32, message: Data) {
        onMain(.customMessage(userId: userId, cmdID: cmdID, seq: seq, data: message))
    }

    func onRealtimeTranscriberStarted(_ roomId: String, transcriberRobotId: String) {
        hopToMain(.transcriberStarted(robotId: transcriberRobotId))
    }

    func onReceiveTranscriberMessage(_ roomId: String, message: TranscriberMessage) {
        let translations = (message.translationTexts as? [String: String]) ?? [:]
        hopToMain(.transcript(TranscriptSegment(
            id: message.segmentId,
            speakerUserId: message.speakerUserId,
            sourceText: message.sourceText,
            translations: translations,
            timestamp: Date(timeIntervalSince1970: TimeInterval(message.timestamp) / 1000),
            isCompleted: message.isCompleted
        )))
    }

    func onRealtimeTranscriberStopped(_ roomId: String, transcriberRobotId: String, reason: Int) {
        hopToMain(.transcriberStopped(robotId: transcriberRobotId, reason: reason))
    }

    func onRealtimeTranscriberError(_ roomId: String, transcriberRobotId: String, error: Int, errorInfo: String) {
        hopToMain(.transcriberError(robotId: transcriberRobotId, code: error, message: errorInfo))
    }
}
