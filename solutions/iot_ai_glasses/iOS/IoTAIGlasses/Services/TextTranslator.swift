import Foundation

protocol TextTranslator {
    func translate(_ text: String, from source: Language, to target: Language) async -> String?
}

struct LLMTranslator: TextTranslator {
    var client = ChatCompletionClient.shared

    func translate(_ text: String, from source: Language, to target: Language) async -> String? {
        let prompt = """
        You are a professional real-time interpreter. Translate the user's \(source.englishName) speech \
        transcript into \(target.englishName). Keep the tone natural and spoken. \
        Output only the translation, without quotes, notes or explanations.
        """
        do {
            return try await client.complete([.system(prompt), .user(text)])
        } catch {
            print("[LLMTranslator] \(error.localizedDescription)")
            return nil
        }
    }
}

private extension Language {
    var englishName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "Simplified Chinese"
        }
    }
}
