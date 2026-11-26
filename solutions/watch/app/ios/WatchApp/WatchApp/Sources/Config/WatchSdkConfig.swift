import Foundation

/// 本地联调配置入口。
///
/// 本地联调 SDK 配置入口；真实密钥不能进入正式客户端，生产环境必须由服务端签发 UserSig。
enum WatchSdkConfig {
    /// TRTC／IoT 房间登录 SDKAppID；登录页默认显示后仍允许手动修改。
    static let TRTC_SDK_APP_ID: Int64 = 0

    /// TRTC／IoT 房间登录密钥，仅用于本地联调。
    static let TRTC_SECRET_KEY = ""

    /// IMSDK 初始化和 UserSig 使用的 SDKAppID。
    static let IM_SDK_APP_ID: Int64 = 0

    /// IMSDK UserSig 使用的 SDKSecretKey，仅用于本地联调。
    static let IM_SECRET_KEY = ""

    /// TRTC／IoT 登录页默认房间号；登录页显示后仍允许手动修改。
    static let TRTC_ROOM_ID = "260101"

    /// 首期本地绑定使用的产品 ID，待接入真实绑定服务后替换为服务端返回值。
    static let boundWatchProductId = "PRODUCT_A"

    static let userSigExpireSeconds: Int64 = 604_800

}

/// 按设计目录规则为当前手机端生成跨 SDK 复用的 userId。
enum WatchIdentity {
    static func userID(for channel: String) -> String {
        let normalizedChannel = channel.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedChannel.isEmpty ? "" : "\(normalizedChannel)_ios"
    }
}
