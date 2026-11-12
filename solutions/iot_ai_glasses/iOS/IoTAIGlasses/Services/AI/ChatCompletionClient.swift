import Foundation

struct ChatMessage: Codable {
    let role: String
    let content: String

    static func system(_ content: String) -> ChatMessage { ChatMessage(role: "system", content: content) }
    static func user(_ content: String) -> ChatMessage { ChatMessage(role: "user", content: content) }
    static func assistant(_ content: String) -> ChatMessage { ChatMessage(role: "assistant", content: content) }
}

enum ChatCompletionError: LocalizedError {
    case notConfigured
    case http(Int, String)
    case emptyReply

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "请先在 AIServiceConfig 中配置大模型服务地址、API Key 与模型名"
        case .http(let code, let body): return "HTTP \(code): \(body)"
        case .emptyReply: return "模型未返回内容"
        }
    }
}

final class ChatCompletionClient {
    static let shared = ChatCompletionClient()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func complete(_ messages: [ChatMessage], temperature: Double = 0.2, thinking: Bool = false) async throws -> String {
        guard AIServiceConfig.isConfigured, let url = URL(string: AIServiceConfig.endpoint) else {
            throw ChatCompletionError.notConfigured
        }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("Bearer \(AIServiceConfig.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RequestBody(
            model: AIServiceConfig.model,
            messages: messages,
            stream: false,
            temperature: temperature,
            thinking: .init(type: thinking ? "enabled" : "disabled")
        ))

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw ChatCompletionError.http(status, String(decoding: data.prefix(300), as: UTF8.self))
        }
        let reply = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard let content = reply.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw ChatCompletionError.emptyReply
        }
        return content
    }

    private struct RequestBody: Encodable {
        struct Thinking: Encodable { let type: String }
        let model: String
        let messages: [ChatMessage]
        let stream: Bool
        let temperature: Double
        let thinking: Thinking
    }

    private struct ResponseBody: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        let choices: [Choice]
    }
}
