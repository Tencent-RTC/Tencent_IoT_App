import Foundation

enum CallSignalPhase {
    case idle
    case outgoing
    case incoming
    case active
}

struct CallSignalState {
    let phase: CallSignalPhase
    let sessionID: UInt32
    let peerID: String
    let mediaType: CallMediaType
    let reason: String?

    static let idle = CallSignalState(phase: .idle, sessionID: 0, peerID: "", mediaType: .video, reason: nil)
}

@MainActor
final class CallSignaling {
    private let transport: CallSignalTransport
    private let onStateChange: (CallSignalState) -> Void
    private(set) var state = CallSignalState.idle
    private var epoch: UInt64 = 0
    private var timeoutWork: DispatchWorkItem?

    init(transport: CallSignalTransport, onStateChange: @escaping (CallSignalState) -> Void) {
        self.transport = transport
        self.onStateChange = onStateChange
        transport.onIncomingSignal = { [weak self] incoming in
            self?.receive(senderID: incoming.senderID, signal: incoming.signal)
        }
    }

    @discardableResult
    func startOutgoing(target: CallTarget, mediaType: CallMediaType) -> Bool {
        let peerID = target.deviceName
        guard state.phase == .idle, transport.isAvailable, !peerID.isEmpty, let localUserID = transport.localUserID, !localUserID.isEmpty else { return false }
        let sessionID = UInt32.random(in: 1...UInt32.max)
        update(CallSignalState(phase: .outgoing, sessionID: sessionID, peerID: peerID, mediaType: mediaType, reason: nil))
        scheduleTimeout(sessionID: sessionID, expectedEpoch: epoch, delay: 35) { [weak self] in self?.sendHangupIfCurrent(reason: "timeout") }
        let signal = CallSignal(type: .call, sessionID: sessionID, to: peerID, mediaCode: mediaType == .video ? CallSignalCodec.audioVideoMediaCode : CallSignalCodec.audioOnlyMediaCode, videoQuality: mediaType == .video ? CallSignalCodec.highVideoQuality : 0, deviceCode: target.deviceName)
        do {
            _ = try CallSignalCodec.encode(signal)
            transport.send(to: peerID, signal: signal) { [weak self] result in
                guard let self else { return }
                guard case .failure = result else { return }
                Task { @MainActor in if self.matches(sessionID: sessionID, phase: .outgoing) { self.finish(reason: "send_failed") } }
            }
        } catch {
            finish(reason: "encode_failed")
        }
        return true
    }

    @discardableResult
    func acceptIncoming() -> Bool {
        guard state.phase == .incoming else { return false }
        let current = state
        transport.send(to: current.peerID, signal: CallSignal(type: .accept, sessionID: current.sessionID, to: current.peerID)) { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                if case .success = result, self.matches(sessionID: current.sessionID, phase: .incoming) {
                    self.cancelTimeout()
                    self.update(CallSignalState(phase: .active, sessionID: current.sessionID, peerID: current.peerID, mediaType: current.mediaType, reason: nil))
                }
            }
        }
        return true
    }

    @discardableResult
    func rejectIncoming(reason: String = "decline") -> Bool {
        guard state.phase == .incoming else { return false }
        let current = state
        transport.send(to: current.peerID, signal: CallSignal(type: .reject, sessionID: current.sessionID, to: current.peerID, reason: reason)) { _ in }
        finish(reason: reason)
        return true
    }

    @discardableResult
    func hangup() -> Bool {
        guard state.phase != .idle else { return false }
        if state.phase == .incoming { return rejectIncoming() }
        sendHangupIfCurrent(reason: state.phase == .outgoing ? "cancel" : "hangup")
        return true
    }

    func receive(senderID: String, signal: CallSignal) {
        guard !senderID.isEmpty, signal.to == transport.localUserID else { return }
        switch signal.type {
        case .call:
            guard state.phase == .idle, let mediaType = mediaType(for: signal.mediaCode) else {
                transport.send(to: senderID, signal: CallSignal(type: .reject, sessionID: signal.sessionID, to: senderID, reason: "busy")) { _ in }
                return
            }
            update(CallSignalState(phase: .incoming, sessionID: signal.sessionID, peerID: senderID, mediaType: mediaType, reason: nil))
            scheduleTimeout(sessionID: signal.sessionID, expectedEpoch: epoch, delay: 40) { [weak self] in _ = self?.rejectIncoming(reason: "decline") }
        case .accept:
            guard matches(sessionID: signal.sessionID, phase: .outgoing, peerID: senderID) else { return }
            cancelTimeout()
            update(CallSignalState(phase: .active, sessionID: signal.sessionID, peerID: senderID, mediaType: state.mediaType, reason: nil))
        case .reject:
            if matches(sessionID: signal.sessionID, phase: .outgoing, peerID: senderID) { finish(reason: signal.reason ?? "reject") }
        case .hangup:
            if matches(sessionID: signal.sessionID, phase: .outgoing, peerID: senderID) || matches(sessionID: signal.sessionID, phase: .incoming, peerID: senderID) || matches(sessionID: signal.sessionID, phase: .active, peerID: senderID) { finish(reason: signal.reason ?? "hangup") }
        }
    }

    func markMediaActive() {
        guard state.phase == .outgoing || state.phase == .incoming else { return }
        cancelTimeout()
        update(CallSignalState(phase: .active, sessionID: state.sessionID, peerID: state.peerID, mediaType: state.mediaType, reason: nil))
    }

    func markMediaEnded(reason: String = "media_end") {
        guard state.phase != .idle else { return }
        finish(reason: reason)
    }

    func onTransportUnavailable() {
        if state.phase == .outgoing || state.phase == .incoming { finish(reason: "im_unavailable") }
    }

    private func mediaType(for code: Int?) -> CallMediaType? {
        switch code {
        case CallSignalCodec.audioVideoMediaCode: return .video
        case CallSignalCodec.audioOnlyMediaCode: return .audio
        default: return nil
        }
    }

    private func sendHangupIfCurrent(reason: String) {
        guard state.phase != .idle else { return }
        let current = state
        transport.send(to: current.peerID, signal: CallSignal(type: .hangup, sessionID: current.sessionID, to: current.peerID, reason: reason)) { _ in }
        finish(reason: reason)
    }

    private func finish(reason: String) {
        cancelTimeout()
        update(CallSignalState(phase: .idle, sessionID: 0, peerID: "", mediaType: .video, reason: reason))
    }

    private func update(_ newState: CallSignalState) {
        state = newState
        epoch &+= 1
        onStateChange(newState)
    }

    private func matches(sessionID: UInt32, phase: CallSignalPhase, peerID: String? = nil) -> Bool {
        state.sessionID == sessionID && state.phase == phase && (peerID == nil || state.peerID == peerID)
    }

    private func scheduleTimeout(sessionID: UInt32, expectedEpoch: UInt64, delay: TimeInterval, action: @escaping () -> Void) {
        cancelTimeout()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, self.state.sessionID == sessionID, self.epoch == expectedEpoch + 1 else { return }
                action()
            }
        }
        timeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelTimeout() {
        timeoutWork?.cancel()
        timeoutWork = nil
    }
}
