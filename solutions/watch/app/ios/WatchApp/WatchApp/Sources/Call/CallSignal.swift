import Foundation

enum CallSignalType: String {
    case call
    case accept
    case reject
    case hangup
}

struct CallSignal {
    let type: CallSignalType
    let sessionID: UInt32
    let to: String
    let mediaCode: Int?
    let videoQuality: Int?
    let deviceCode: String?
    let reason: String?

    init(type: CallSignalType, sessionID: UInt32, to: String, mediaCode: Int? = nil, videoQuality: Int? = nil, deviceCode: String? = nil, reason: String? = nil) {
        self.type = type
        self.sessionID = sessionID
        self.to = to
        self.mediaCode = mediaCode
        self.videoQuality = videoQuality
        self.deviceCode = deviceCode
        self.reason = reason
    }
}

struct IncomingCallSignal {
    let senderID: String
    let signal: CallSignal
}

@MainActor
protocol CallSignalTransport: AnyObject {
    var localUserID: String? { get }
    var isAvailable: Bool { get }
    var onIncomingSignal: ((IncomingCallSignal) -> Void)? { get set }
    func send(to userID: String, signal: CallSignal, completion: @escaping (Result<Void, Error>) -> Void)
}

enum CallSignalCodec {
    static let audioOnlyMediaCode = 1
    static let videoOnlyMediaCode = 2
    static let audioVideoMediaCode = 3
    static let highVideoQuality = 2

    static func encode(_ signal: CallSignal) throws -> String {
        guard !signal.to.isEmpty else { throw CodecError.invalidField }
        if signal.type == .call && (signal.mediaCode == nil || signal.videoQuality == nil) {
            throw CodecError.invalidField
        }
        if signal.mediaCode?.signum() == -1 || signal.videoQuality?.signum() == -1 {
            throw CodecError.invalidField
        }
        var object: [String: Any] = [
            "v": 1,
            "t": signal.type.rawValue,
            "sid": NSNumber(value: signal.sessionID),
            "to": signal.to
        ]
        if let mediaCode = signal.mediaCode { object["mc"] = mediaCode }
        if let videoQuality = signal.videoQuality { object["vq"] = videoQuality }
        if let deviceCode = signal.deviceCode, !deviceCode.isEmpty { object["cd"] = truncateUTF8(deviceCode) }
        if let reason = signal.reason, !reason.isEmpty { object["rs"] = reason }
        let data = try JSONSerialization.data(withJSONObject: object, options: [])
        guard let text = String(data: data, encoding: .utf8) else { throw CodecError.invalidEncoding }
        return text
    }

    static func decode(_ text: String) -> CallSignal? {
        guard let data = text.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]), let dictionary = object as? [String: Any] else { return nil }
        guard dictionary.values.allSatisfy({ !($0 is [String: Any]) && !($0 is [Any]) }) else { return nil }
        guard let version = integer(dictionary["v"]), version == 1, let typeValue = dictionary["t"] as? String, let type = CallSignalType(rawValue: typeValue), let sessionIDValue = integer(dictionary["sid"]), sessionIDValue >= 0, sessionIDValue <= UInt64(UInt32.max), let to = dictionary["to"] as? String, !to.isEmpty else { return nil }
        let mediaCode = integer(dictionary["mc"]).flatMap { $0 <= UInt64(Int.max) ? Int($0) : nil }
        let videoQuality = integer(dictionary["vq"]).flatMap { $0 <= UInt64(Int.max) ? Int($0) : nil }
        if type == .call && (mediaCode == nil || videoQuality == nil) { return nil }
        return CallSignal(type: type, sessionID: UInt32(sessionIDValue), to: to, mediaCode: mediaCode, videoQuality: videoQuality, deviceCode: dictionary["cd"] as? String, reason: dictionary["rs"] as? String)
    }

    private static func integer(_ value: Any?) -> UInt64? {
        guard let number = value as? NSNumber, !(value is Bool), number.doubleValue.rounded() == number.doubleValue, number.doubleValue >= 0, number.doubleValue <= Double(UInt64.max) else { return nil }
        return number.uint64Value
    }

    private static func truncateUTF8(_ value: String) -> String {
        guard value.utf8.count > 128 else { return value }
        var result = ""
        var count = 0
        for character in value {
            let bytes = String(character).utf8.count
            guard count + bytes <= 128 else { break }
            result.append(character)
            count += bytes
        }
        return result
    }

    private enum CodecError: Error {
        case invalidField
        case invalidEncoding
    }
}
