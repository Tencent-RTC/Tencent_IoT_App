import CommonCrypto
import Compression
import Foundation

struct TrtcSignatureProvider: IoTSignatureProvider {
    func fetchSignature(config: IotSessionConfig) throws -> IoTUserSignature {
        let appId = config.appID
        let secret = config.appSecret
        let channel = config.channel
        let userId = WatchIdentity.userID(for: channel)
        guard !appId.isEmpty, !secret.isEmpty, !channel.isEmpty else {
            throw IotSignatureError.credentialsMissing
        }
        guard let sdkAppId = Int64(appId) else { throw IotSignatureError.appIdNotNumeric }
        let now = Int64(Date().timeIntervalSince1970)
        return IoTUserSignature(
            appKey: appId,
            loginId: channel,
            requestId: userId,
            timestamp: now,
            nonce: Int.random(in: 1...Int(Int32.max)),
            signature: Self.generateUserSig(
                sdkAppId: sdkAppId,
                userId: userId,
                key: secret,
                now: now,
                expireSeconds: WatchSdkConfig.userSigExpireSeconds
            )
        )
    }

    static func generateUserSig(
        sdkAppId: Int64,
        userId: String,
        key: String,
        now: Int64,
        expireSeconds: Int64 = 604_800
    ) -> String {
        let content = "TLS.identifier:\(userId)\nTLS.sdkappid:\(sdkAppId)\nTLS.time:\(now)\nTLS.expire:\(expireSeconds)\n"
        let keyBytes = Array(key.utf8)
        let dataBytes = Array(content.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        keyBytes.withUnsafeBytes { keyBuffer in
            dataBytes.withUnsafeBytes { dataBuffer in
                digest.withUnsafeMutableBytes { digestBuffer in
                    CCHmac(
                        CCHmacAlgorithm(kCCHmacAlgSHA256),
                        keyBuffer.baseAddress,
                        keyBytes.count,
                        dataBuffer.baseAddress,
                        dataBytes.count,
                        digestBuffer.baseAddress
                    )
                }
            }
        }
        let sig = Data(digest).base64EncodedString()
        let json: [String: Any] = [
            "TLS.ver": "2.0", "TLS.identifier": userId, "TLS.sdkappid": sdkAppId,
            "TLS.expire": expireSeconds, "TLS.time": now, "TLS.sig": sig
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]),
              let compressed = zlibDeflate(data) else { return "" }
        return compressed.base64EncodedString()
            .replacingOccurrences(of: "+", with: "*")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "=", with: "_")
    }

    private static func zlibDeflate(_ input: Data) -> Data? {
        var destination = [UInt8](repeating: 0, count: input.count + 128)
        let destinationCapacity = destination.count
        let written = input.withUnsafeBytes { raw -> Int in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return destination.withUnsafeMutableBytes { destinationBuffer in
                guard let destinationBase = destinationBuffer.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_encode_buffer(destinationBase, destinationCapacity, base, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        var output = Data([0x78, 0x01])
        output.append(contentsOf: destination[0..<written])
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in input {
            a = (a + UInt32(byte)) % 65_521
            b = (b + a) % 65_521
        }
        let checksum = (b << 16) | a
        output.append(contentsOf: [
            UInt8(truncatingIfNeeded: checksum >> 24),
            UInt8(truncatingIfNeeded: checksum >> 16),
            UInt8(truncatingIfNeeded: checksum >> 8),
            UInt8(truncatingIfNeeded: checksum)
        ])
        return output
    }
}
