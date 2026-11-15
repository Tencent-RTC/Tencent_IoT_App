import Foundation

struct ImSdkCredentials {
    let sdkAppID: Int64
    let userID: String
    let userSig: String
}

enum ImSdkAuthError: LocalizedError {
    case appIDMissing
    case secretKeyMissing
    case userIDMissing

    var errorDescription: String? {
        switch self {
        case .appIDMissing: return "IMSDK_APP_ID_MISSING"
        case .secretKeyMissing: return "IMSDK_SECRET_KEY_MISSING"
        case .userIDMissing: return "IMSDK_USER_ID_MISSING"
        }
    }
}

/// 为后续 IMSDK 登录提供与 IoT SDK 相同的本端身份和 UserSig。
enum ImSdkAuth {
    static func forChannel(
        _ channel: String,
        nowSeconds: Int64 = Int64(Date().timeIntervalSince1970)
    ) throws -> ImSdkCredentials {
        let userID = WatchIdentity.userID(for: channel)
        guard WatchSdkConfig.IM_SDK_APP_ID > 0 else { throw ImSdkAuthError.appIDMissing }
        guard !WatchSdkConfig.IM_SECRET_KEY.isEmpty else { throw ImSdkAuthError.secretKeyMissing }
        guard !userID.isEmpty else { throw ImSdkAuthError.userIDMissing }

        return ImSdkCredentials(
            sdkAppID: WatchSdkConfig.IM_SDK_APP_ID,
            userID: userID,
            userSig: TrtcSignatureProvider.generateUserSig(
                sdkAppId: WatchSdkConfig.IM_SDK_APP_ID,
                userId: userID,
                key: WatchSdkConfig.IM_SECRET_KEY,
                now: nowSeconds,
                expireSeconds: WatchSdkConfig.userSigExpireSeconds
            )
        )
    }
}
