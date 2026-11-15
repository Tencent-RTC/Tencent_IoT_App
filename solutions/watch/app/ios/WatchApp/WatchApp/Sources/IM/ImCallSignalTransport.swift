import Foundation

@MainActor
final class ImCallSignalTransport: CallSignalTransport {
    private let manager: ImService

    var onIncomingSignal: ((IncomingCallSignal) -> Void)?

    var localUserID: String? {
        manager.loggedInUserID
    }

    var isAvailable: Bool {
        manager.loggedInUserID != nil
    }

    init(manager: ImService) {
        self.manager = manager
        manager.onCallSignalReceived = { [weak self] incoming in
            self?.onIncomingSignal?(incoming)
        }
    }

    func send(to userID: String, signal: CallSignal, completion: @escaping (Result<Void, Error>) -> Void) {
        manager.sendCallSignal(signal, to: userID, completion: completion)
    }
}
