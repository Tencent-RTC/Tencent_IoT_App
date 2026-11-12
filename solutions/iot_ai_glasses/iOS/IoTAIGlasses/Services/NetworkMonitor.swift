import Foundation
import Network

final class NetworkMonitor {
    var onChange: ((Bool) -> Void)?

    private let monitor = NWPathMonitor()

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            DispatchQueue.main.async { self?.onChange?(online) }
        }
        monitor.start(queue: DispatchQueue(label: "NetworkMonitor"))
    }
}
