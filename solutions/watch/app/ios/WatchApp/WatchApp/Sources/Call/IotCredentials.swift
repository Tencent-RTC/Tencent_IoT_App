import Foundation

struct IoTUserSignature {
    let appKey: String
    let loginId: String
    let requestId: String
    let timestamp: Int64
    let nonce: Int
    let signature: String
}

protocol IoTSignatureProvider {
    func fetchSignature(config: IotSessionConfig) throws -> IoTUserSignature
}

enum IotSignatureError: LocalizedError {
    case credentialsMissing
    case appIdNotNumeric

    var errorDescription: String? {
        switch self {
        case .credentialsMissing: return "SIGNATURE_CREDENTIALS_MISSING"
        case .appIdNotNumeric: return "SDK_APP_ID_NOT_NUMERIC"
        }
    }
}

enum IoTSignatureProviders {
    private static var current: IoTSignatureProvider = TrtcSignatureProvider()
    static func install(_ provider: IoTSignatureProvider) { current = provider }
    static func require() -> IoTSignatureProvider { current }
}
