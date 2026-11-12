import Foundation

@MainActor
final class SpeechQueue {
    var onFailed: ((Int) -> Void)?

    private var service: RealtimeTTSService?
    private var pending: [(text: String, language: Language)] = []

    private var tts: RealtimeTTSService {
        if let service { return service }
        let tts = RealtimeTTSService()
        tts.onEvent = { [weak self] event in
            guard let self else { return }
            if case .finished(let ok, let code, _) = event, !ok { self.onFailed?(code) }
            self.next()
        }
        service = tts
        return tts
    }

    func enqueue(_ text: String, language: Language) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        pending.append((text, language))
        if !tts.isSpeaking { next() }
    }

    func clear() {
        pending.removeAll()
        service?.stop()
    }

    private func next() {
        guard !pending.isEmpty else { return }
        let item = pending.removeFirst()
        tts.speak(item.text, language: item.language)
    }
}
