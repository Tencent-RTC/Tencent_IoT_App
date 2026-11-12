import Foundation

enum RecordKind: String, Codable {
    case meeting
    case translation
}

struct MeetingTodo: Codable, Hashable, Identifiable {
    var id = UUID()
    var text: String
    var note: String
    var isDone = false
}

struct MeetingSummary: Codable, Hashable {
    enum Phase: String, Codable {
        case pending
        case ready
        case failed
    }

    var phase: Phase = .pending
    var title: String?
    var headline = ""
    var consensus: [String] = []
    var questions: [String] = []
    var todos: [MeetingTodo] = []
}

struct Record: Identifiable, Codable, Hashable {
    let id: UUID
    var kind: RecordKind
    var title: String
    var createdAt: Date
    var durationSeconds: Int
    var transcript: [TranscriptLine]?
    var keepsAudio = false
    var summary: MeetingSummary?
    var source: Language?
    var target: Language?
    var isInterpret: Bool?
    var isStarred: Bool?

    init(id: UUID = UUID(), kind: RecordKind, title: String, createdAt: Date, durationSeconds: Int, transcript: [TranscriptLine]? = nil, keepsAudio: Bool = false, summary: MeetingSummary? = nil, source: Language? = nil, target: Language? = nil, isInterpret: Bool? = nil, isStarred: Bool? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
        self.transcript = transcript
        self.keepsAudio = keepsAudio
        self.summary = summary
        self.source = source
        self.target = target
        self.isInterpret = isInterpret
        self.isStarred = isStarred
    }

    var durationText: String {
        durationSeconds < 60 ? "不足 1 分钟" : "\(durationSeconds / 60) 分钟"
    }

    var translationHeading: String {
        isInterpret == true || title.contains("双向传译") ? "双向传译" : "翻译记录"
    }

    var languagePair: String? {
        guard let source, let target else { return nil }
        return "\(source.rawValue) \(isInterpret == true ? "⇄" : "→") \(target.rawValue)"
    }

    func translationSubtitle(now: Date = .now) -> String {
        [languagePair, subtitle(now: now)].compactMap { $0 }.joined(separator: " · ")
    }

    func subtitle(now: Date = .now) -> String {
        "\(RecordDate.text(createdAt, now: now)) · \(durationText)"
    }
}

enum RecordDate {
    private static let time = formatter("HH:mm")
    private static let monthDay = formatter("M 月 d 日")
    private static let full = formatter("yyyy 年 M 月 d 日")

    static func text(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return "今天 \(time.string(from: date))"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "昨天 \(time.string(from: date))"
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return monthDay.string(from: date)
        }
        return full.string(from: date)
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = format
        return formatter
    }
}
