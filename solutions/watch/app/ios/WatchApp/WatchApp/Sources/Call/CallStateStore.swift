import Foundation

enum CallMediaType {
    case audio
    case video
}

enum CallPhase {
    case idle
    case outgoing
    case incoming
    case active
}

enum CallEndReason {
    case localHangup
    case remoteHangup
    case permissionDenied
    case networkError
    case unknown
}

struct CallTarget {
    let productId: String
    let deviceName: String
    let displayName: String
    let avatarID: String

    init(productId: String, deviceName: String, displayName: String, avatarID: String) {
        self.productId = productId
        self.deviceName = deviceName
        self.displayName = displayName
        self.avatarID = avatarID
    }
}

struct CallUIState {
    var phase: CallPhase = .idle
    var sessionID: UInt32 = 0
    var target: CallTarget?
    var mediaType: CallMediaType = .video
    var remoteVideoAvailable = false
    var result: CallEndReason?
}

@MainActor
final class CallStateStore {
    private(set) var state = CallUIState()
    var onChange: ((CallUIState) -> Void)?

    func startOutgoing(target: CallTarget, mediaType: CallMediaType, sessionID: UInt32 = 0) {
        update(CallUIState(
            phase: .outgoing,
            sessionID: sessionID,
            target: target,
            mediaType: mediaType,
            remoteVideoAvailable: false,
            result: nil
        ))
    }

    func incoming(target: CallTarget, mediaType: CallMediaType, sessionID: UInt32) {
        guard state.phase == .idle else { return }
        update(CallUIState(
            phase: .incoming,
            sessionID: sessionID,
            target: target,
            mediaType: mediaType,
            remoteVideoAvailable: false,
            result: nil
        ))
    }

    func active(mediaType: CallMediaType? = nil) {
        guard state.phase == .outgoing || state.phase == .incoming else { return }
        var next = state
        next.phase = .active
        if let mediaType { next.mediaType = mediaType }
        update(next)
    }

    func remoteVideoAvailable(_ available: Bool) {
        guard state.phase == .active || state.phase == .outgoing else { return }
        var next = state
        next.remoteVideoAvailable = available
        update(next)
    }

    func finish(reason: CallEndReason? = nil) {
        update(CallUIState(sessionID: state.sessionID, result: reason))
    }

    private func update(_ newState: CallUIState) {
        state = newState
        onChange?(newState)
    }
}
