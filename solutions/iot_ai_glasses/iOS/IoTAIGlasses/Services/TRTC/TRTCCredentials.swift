import Foundation

enum TRTCCredentials {
    // TODO: 客户填写自己的 SDKAppID 与 SDKSecretKey
    static let sdkAppId = 0
    static let secretKey = ""

    static var isConfigured: Bool { sdkAppId != 0 && !secretKey.isEmpty }

    static var userId: String {
        let key = "trtcUserId"
        if let saved = UserDefaults.standard.string(forKey: key) { return saved }
        let generated = "glasses_" + UUID().uuidString.prefix(8).lowercased()
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }

    static func userSig() -> String {
        userSig(for: userId)
    }

    static func userSig(for identifier: String) -> String {
        GenerateTestUserSig.genTestUserSig(sdkAppId: sdkAppId, userId: identifier, secrectkey: secretKey)
    }
}
