import Foundation

enum MeetingSummarizerError: LocalizedError {
    case badFormat
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .badFormat: "模型返回的内容无法解析为会议纪要"
        case .emptyTranscript: "本次没有识别到文字"
        }
    }
}

struct MeetingSummarizer {
    var client = ChatCompletionClient.shared

    func summarize(title: String, durationSeconds: Int, lines: [TranscriptLine]) async throws -> MeetingSummary {
        let transcript = lines.map { line in
            "\(line.speakerLabel ?? "发言人")：\(line.original)"
        }.joined(separator: "\n")
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MeetingSummarizerError.emptyTranscript
        }

        let prompt = """
        请根据以下会议转写内容生成会议纪要。严格只输出一个 JSON 对象，不要输出任何解释文字或代码块标记，格式：
        {"title":"会议标题","headline":"一句话总结","consensus":["已达成共识的点",...],"questions":["待确认的问题",...],"todos":[{"text":"待办事项","note":"负责人或时间的说明"}]}
        要求：title 根据转写内容概括本次会议主题，不超过 12 字，不含日期时间；headline 不超过 40 字；consensus 和 questions 各最多 5 条，没有就给空数组；todos 最多 5 条，没有就给空数组；全部用简体中文。
        会议开始于：\(title)
        会议时长：约 \(max(1, durationSeconds / 60)) 分钟
        转写内容：
        \(transcript)
        """

        let reply = try await client.complete([.user(prompt)], temperature: 0.3)
        return try parse(reply)
    }

    private func parse(_ reply: String) throws -> MeetingSummary {
        var json = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if json.hasPrefix("```") {
            json = json
                .drop(while: { $0 != "\n" })
                .dropFirst()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let fence = json.range(of: "```", options: .backwards) {
                json = String(json[..<fence.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        guard let data = json.data(using: .utf8),
              let dto = try? JSONDecoder().decode(DTO.self, from: data) else {
            throw MeetingSummarizerError.badFormat
        }
        return MeetingSummary(
            phase: .ready,
            title: dto.title,
            headline: dto.headline,
            consensus: dto.consensus ?? [],
            questions: dto.questions ?? [],
            todos: (dto.todos ?? []).map { MeetingTodo(text: $0.text, note: $0.note) }
        )
    }

    private struct DTO: Decodable {
        let title: String?
        let headline: String
        let consensus: [String]?
        let questions: [String]?
        let todos: [TodoDTO]?

        struct TodoDTO: Decodable {
            let text: String
            let note: String
        }
    }
}
