import Foundation

enum AIServiceConfig {
    // TODO: 客户填写自己的大模型服务地址、API Key 与模型名；生产环境应由业务服务器转发，客户端不保存 API Key
    static let endpoint = ""
    static let apiKey = ""
    static let model = ""

    static var isConfigured: Bool { endpoint.hasPrefix("https://") && !apiKey.isEmpty && !model.isEmpty }
}
