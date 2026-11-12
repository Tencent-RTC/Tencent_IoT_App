import Foundation
import Observation

protocol GlassesService: AnyObject {
    var isConnected: Bool { get }
    var batteryLevel: Int? { get }
    func connect()
    func disconnect()
}

@Observable
final class MockGlassesService: GlassesService {
    private(set) var isConnected: Bool
    private let level = 82

    init(isConnected: Bool = true) {
        self.isConnected = isConnected
    }

    var batteryLevel: Int? { isConnected ? level : nil }

    func connect() { isConnected = true }

    func disconnect() { isConnected = false }
}
