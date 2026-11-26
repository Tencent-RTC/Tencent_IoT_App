import Foundation

/// 一次 IoT／TRTC 登录所需的运行时配置，不持有页面或 SDK 类型。
struct IotSessionConfig {
    let channel: String
    let appID: String
    let appSecret: String
}
