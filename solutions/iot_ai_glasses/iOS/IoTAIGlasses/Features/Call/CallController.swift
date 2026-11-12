import Foundation
import Observation

@MainActor
@Observable
final class CallController {
    enum Phase {
        case idle
        case joining
        case inCall
    }

    private(set) var phase: Phase = .idle
    private(set) var roomId = ""
    private(set) var userId = ""
    private(set) var remoteUsers: [String] = []
    private(set) var isMuted = false
    private(set) var isReconnecting = false

    @ObservationIgnored var onJoined: (() -> Void)?
    @ObservationIgnored var onEnded: ((String) -> Void)?

    @ObservationIgnored private let trtc = TRTCService.shared
    @ObservationIgnored private var glassesConnected = true

    var isRunning: Bool { phase != .idle }

    init() {
        Task { [weak self, trtc] in
            for await event in trtc.events() {
                self?.handle(event)
            }
        }
    }

    func start(roomId: String, userId: String, glassesConnected: Bool) {
        guard phase == .idle else { return }
        self.roomId = roomId
        self.userId = userId
        self.glassesConnected = glassesConnected
        remoteUsers = []
        isMuted = false
        isReconnecting = false
        phase = .joining
        trtc.enterRoom(TRTCRoomConfig(
            sdkAppId: UInt32(TRTCCredentials.sdkAppId),
            userId: userId,
            userSig: TRTCCredentials.userSig(for: userId),
            roomId: Self.roomID(roomId)
        ))
    }

    func stop() {
        guard phase != .idle else { return }
        phase = .idle
        remoteUsers = []
        isReconnecting = false
        trtc.stopLocalAudio()
        trtc.exitRoom()
    }

    func toggleMute() {
        isMuted.toggle()
        applyMute()
    }

    func setGlassesConnected(_ connected: Bool) {
        glassesConnected = connected
        applyMute()
    }

    private func applyMute() {
        guard phase == .inCall else { return }
        trtc.muteLocalAudio(isMuted || !glassesConnected)
    }

    private func handle(_ event: TRTCEvent) {
        guard phase != .idle else { return }
        switch event {
        case .enteredRoom:
            phase = .inCall
            trtc.startLocalAudio()
            applyMute()
            onJoined?()
        case .enterRoomFailed(let code):
            end("进入房间失败（\(code)）")
        case .exitedRoom(let reason):
            end(reason == 0 ? "通话已结束" : "已被移出房间（\(reason)）")
        case .error(let code, let message):
            print("[Call] TRTC error \(code): \(message)")
        case .connectionLost, .reconnecting:
            isReconnecting = true
        case .connectionRecovered:
            isReconnecting = false
        case .remoteUserEntered(let id):
            if !remoteUsers.contains(id) { remoteUsers.append(id) }
        case .remoteUserLeft(let id, _):
            remoteUsers.removeAll { $0 == id }
        default:
            break
        }
    }

    private func end(_ message: String) {
        stop()
        onEnded?(message)
    }

    private static func roomID(_ text: String) -> TRTCRoomConfig.RoomID {
        if let number = UInt32(text), number > 0, number < UInt32.max {
            return .numeric(number)
        }
        return .string(text)
    }
}
