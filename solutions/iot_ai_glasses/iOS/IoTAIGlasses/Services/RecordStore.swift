import Foundation

struct RecordStore {
    let url: URL

    init(url: URL = .applicationSupportDirectory.appending(path: "records.json")) {
        self.url = url
    }

    func load() -> [Record]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder.decode([Record].self, from: data)
    }

    func save(_ records: [Record]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(records).write(to: url, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
