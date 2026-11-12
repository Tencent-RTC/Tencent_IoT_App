import Foundation

enum LiveTranscriberEvent {
    case segment(id: String, source: String, translations: [String: String], isCompleted: Bool)
    case failed(code: Int, message: String)
}

@MainActor
final class LiveTranscriber {
    private static let retryableCodes: Set<Int> = [3000, 5000, -102009, -102005]
    private static let ignoredCodes: Set<Int> = [2000, 2002, 4003]
    private static let maxRetries = 3

    var onEvent: ((LiveTranscriberEvent) -> Void)?
    private(set) var isRunning = false

    private let trtc: TRTCService
    private var source: String = "en"
    private var targets: [Language] = [.chinese]
    private var capturing = true
    private var retries = 0
    private var retryTask: Task<Void, Never>?

    init(trtc: TRTCService? = nil) {
        let trtc = trtc ?? .shared
        self.trtc = trtc
        Task { [weak self] in
            for await event in trtc.events() {
                self?.handle(event)
            }
        }
    }

    func start(source: String, targets: [Language]?) {
        guard !isRunning else { return }
        self.source = source
        self.targets = targets ?? []
        isRunning = true
        retries = 0
        capturing = true
        let userId = TRTCCredentials.userId
        trtc.enterRoom(TRTCRoomConfig(
            sdkAppId: UInt32(TRTCCredentials.sdkAppId),
            userId: userId,
            userSig: TRTCCredentials.userSig(),
            roomId: .string("room_\(userId)")
        ))
    }

    func setCapturing(_ capturing: Bool) {
        self.capturing = capturing
        guard isRunning, trtc.roomState == .inRoom else { return }
        trtc.muteLocalAudio(!capturing)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        retryTask?.cancel()
        retryTask = nil
        trtc.stopTranscriber()
        trtc.stopLocalAudio()
        trtc.exitRoom()
    }

    private func startTranscriber() {
        trtc.startTranscriber(TranscriberConfig(
            source: source,
            targets: targets,
            userIds: [TRTCCredentials.userId]
        ))
    }

    private func handle(_ event: TRTCEvent) {
        guard isRunning else { return }
        switch event {
        case .enteredRoom:
            trtc.startLocalAudio()
            trtc.muteLocalAudio(!capturing)
            startTranscriber()
        case .enterRoomFailed(let code):
            fail(code: code, message: "进入房间失败")
        case .error(let code, let message):
            print("[LiveTranscriber] TRTC error \(code): \(message)")
        case .transcript(let segment):
            guard segment.speakerUserId.isEmpty || segment.speakerUserId == TRTCCredentials.userId else { return }
            retries = 0
            onEvent?(.segment(id: segment.id, source: segment.sourceText, translations: segment.translations, isCompleted: segment.isCompleted))
        case .transcriberError(_, let code, let message):
            if Self.ignoredCodes.contains(code) { return }
            if Self.retryableCodes.contains(code), retries < Self.maxRetries {
                retries += 1
                retryTask?.cancel()
                retryTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(Double(1 << (self?.retries ?? 1))))
                    guard !Task.isCancelled, let self, self.isRunning else { return }
                    self.startTranscriber()
                }
                return
            }
            fail(code: code, message: message)
        case .transcriberStopped(_, let reason) where reason != 0:
            fail(code: reason, message: "转写任务已被服务端结束")
        default:
            break
        }
    }

    private func fail(code: Int, message: String) {
        stop()
        onEvent?(.failed(code: code, message: message))
    }
}
