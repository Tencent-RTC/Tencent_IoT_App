import Foundation

enum SessionKind: String, Codable, CaseIterable {
    case translation
    case interpret
    case meeting
    case call

    var shortLabel: String {
        switch self {
        case .translation: "翻译"
        case .interpret: "同传"
        case .meeting: "会议"
        case .call: "通话"
        }
    }

    var title: String {
        switch self {
        case .translation: "实时翻译"
        case .interpret: "双向传译"
        case .meeting: "会议转录"
        case .call: "语音通话"
        }
    }

    var needsNetwork: Bool { self != .call }
}

enum Language: String, Codable, CaseIterable, Identifiable {
    case english = "英语"
    case chinese = "中文"

    var id: Self { self }

    var other: Language { self == .english ? .chinese : .english }
}

enum Speaker: String, Codable, CaseIterable {
    case other
    case me
}

struct TranscriptLine: Identifiable, Codable, Hashable {
    var id = UUID()
    var original: String
    var translated: String
    var speaker: Speaker = .other
    var time: Int
    var speakerLabel: String?
}

struct ActiveSession: Equatable {
    let id = UUID()
    let kind: SessionKind
    var source: Language = .english
    var target: Language = .chinese
    var savesText = true
    var readsAloud = true
    var seconds = 0
    var isPaused = false
    var speaking: Speaker = .other
    var entries: [TranscriptLine] = []
    var engine: CaptionEngine = .transcriber
    var asrRun = 0
    var asrSegments: [String: UUID] = [:]
    var title = ""
    var keepsAudio = false
    var isStarred = false
}

enum CaptionEngine: String, CaseIterable, Identifiable {
    case transcriber
    case asrLLM

    var id: Self { self }

    var title: String {
        switch self {
        case .transcriber: "TRTC AI 转写"
        case .asrLLM: "识别 + 大模型翻译"
        }
    }
}

enum Clock {
    static func text(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
