import Foundation
import Observation

struct ChatTurn: Identifiable, Equatable {
    enum Phase: Equatable {
        case listening
        case thinking
        case done
        case failed
        case interrupted
    }

    let id = UUID()
    var question = ""
    var draft = ""
    var answer: String?
    var phase: Phase = .listening

    var displayQuestion: String { question + draft }
}

@MainActor
@Observable
final class ChatController {
    private(set) var turns: [ChatTurn] = []
    private(set) var isListening = false
    private(set) var speakingTurnID: UUID?
    private(set) var readsAloud = true

    var isEmpty: Bool { turns.isEmpty }
    var isBusy: Bool { isListening || turns.contains { $0.phase == .thinking } }
    var canRetry: Bool { !turns.contains { $0.phase == .listening || $0.phase == .thinking } }

    @ObservationIgnored var onToast: ((String) -> Void)?

    @ObservationIgnored private var asr: RealtimeASRService?
    @ObservationIgnored private var tts: RealtimeTTSService?
    @ObservationIgnored private let client = ChatCompletionClient.shared
    @ObservationIgnored private var currentTurnID: UUID?
    @ObservationIgnored private var activeSegmentID: String?
    @ObservationIgnored private var completedSegments: Set<String> = []
    @ObservationIgnored private var lastCompletedWithoutID: String?
    @ObservationIgnored private var replyTask: Task<Void, Never>?
    @ObservationIgnored private var pendingReply: (id: UUID, turnID: UUID)?
    @ObservationIgnored private static let systemPrompt = """
        你是「AI眼镜」的语音助手。请用提问相同的语言回答，默认简体中文。\
        回答简洁口语化，一般不超过 120 字，不要使用 Markdown 格式。
        """

    func beginQuestion() {
        guard !isListening else { return }
        invalidateReply()
        stopSpeaking()
        completedSegments.removeAll()
        lastCompletedWithoutID = nil
        activeSegmentID = nil
        currentTurnID = nil
        let recognizer = RealtimeASRService()
        asr = recognizer
        recognizer.onEvent = { [weak self, weak recognizer] event in
            guard let self, let recognizer, self.asr === recognizer, self.isListening else { return }
            self.handleASR(event)
        }
        isListening = true
        recognizer.start(language: nil, sdkAppId: TRTCCredentials.sdkAppId, secretKey: TRTCCredentials.secretKey, denoiseStrategy: 2)
    }

    func pauseListening() {
        interrupt("已暂停聆听", quiet: true)
    }

    func retry(_ id: UUID) {
        guard canRetry, let turn = turns.first(where: { $0.id == id }), turn.phase == .failed else { return }
        stopSpeaking()
        ask(turn)
    }

    func interrupt(_ reason: String, quiet: Bool = false) {
        let wasActive = isBusy || speakingTurnID != nil
        isListening = false
        let recognizer = asr
        asr = nil
        recognizer?.onEvent = nil
        recognizer?.stop()
        invalidateReply()
        stopSpeaking()
        interruptDraft()
        if wasActive && !quiet { onToast?(reason) }
    }

    private func handleASR(_ event: RealtimeASREvent) {
        guard isListening else { return }
        switch event {
        case .segment(let segment):
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            let segmentID = segment.segmentId
            if !segmentID.isEmpty && completedSegments.contains(segmentID) { return }
            if segmentID.isEmpty && segment.isCompleted && lastCompletedWithoutID == text { return }
            if !segment.isCompleted || !segmentID.isEmpty { lastCompletedWithoutID = nil }

            invalidateReply()
            stopSpeaking()
            if currentTurnID != nil && activeSegmentID != segmentID { interruptDraft() }
            if currentTurnID == nil {
                let turn = ChatTurn()
                turns.append(turn)
                currentTurnID = turn.id
                activeSegmentID = segmentID
            }
            guard let index = turns.firstIndex(where: { $0.id == currentTurnID }) else { return }
            if segment.isCompleted {
                turns[index].question = text
                turns[index].draft = ""
                if segmentID.isEmpty {
                    lastCompletedWithoutID = text
                } else {
                    completedSegments.insert(segmentID)
                }
                currentTurnID = nil
                activeSegmentID = nil
                ask(turns[index])
            } else {
                turns[index].draft = text
            }
        case .failed(let code, let message):
            interrupt("", quiet: true)
            onToast?("语音识别出错（\(code)）：\(message)")
        case .stopped:
            interrupt("聆听已结束，请重新开始")
        case .started, .volume:
            break
        }
    }

    private func interruptDraft() {
        if let id = currentTurnID, let index = turns.firstIndex(where: { $0.id == id }) {
            turns[index].question = turns[index].displayQuestion
            turns[index].draft = ""
            turns[index].phase = .interrupted
        }
        if let activeSegmentID, !activeSegmentID.isEmpty { completedSegments.insert(activeSegmentID) }
        currentTurnID = nil
        activeSegmentID = nil
    }

    private func invalidateReply() {
        let turnID = pendingReply?.turnID
        pendingReply = nil
        replyTask?.cancel()
        replyTask = nil
        if let turnID, let index = turns.firstIndex(where: { $0.id == turnID }), turns[index].phase == .thinking {
            turns[index].phase = .interrupted
        }
    }

    private func ask(_ turn: ChatTurn) {
        guard let index = turns.firstIndex(where: { $0.id == turn.id }) else { return }
        invalidateReply()
        let requestID = UUID()
        pendingReply = (requestID, turn.id)
        turns[index].phase = .thinking
        let history = Self.history(for: turn, in: turns)
        replyTask = Task { [weak self, client] in
            do {
                let answer = try await client.complete(history)
                guard !Task.isCancelled else { return }
                self?.settle(turn.id, requestID: requestID, answer: answer)
            } catch {
                guard !Task.isCancelled else { return }
                self?.settle(turn.id, requestID: requestID)
            }
        }
    }

    private func settle(_ id: UUID, requestID: UUID, answer: String? = nil) {
        guard pendingReply?.id == requestID, pendingReply?.turnID == id,
              let index = turns.firstIndex(where: { $0.id == id }), turns[index].phase == .thinking else { return }
        pendingReply = nil
        replyTask = nil
        if let answer {
            turns[index].answer = answer
            turns[index].phase = .done
            if readsAloud { speak(answer, for: id) }
        } else {
            turns[index].phase = .failed
            onToast?("回答生成失败，请检查网络后重试")
        }
    }

    private func speak(_ text: String, for id: UUID) {
        stopSpeaking()
        let speaker = RealtimeTTSService()
        tts = speaker
        speakingTurnID = id
        speaker.onEvent = { [weak self, weak speaker] event in
            guard let self, let speaker, self.tts === speaker,
                  case .finished(let ok, let code, _) = event else { return }
            self.speakingTurnID = nil
            self.tts = nil
            speaker.onEvent = nil
            if !ok { self.onToast?("语音播报失败（\(code)）") }
        }
        speaker.speak(text)
    }

    func toggleReadsAloud() {
        readsAloud.toggle()
        if !readsAloud { stopSpeaking() }
        onToast?(readsAloud ? "已开启回答播报" : "已关闭回答播报")
    }

    func stopSpeaking() {
        let speaker = tts
        tts = nil
        speakingTurnID = nil
        speaker?.onEvent = nil
        speaker?.stop()
    }

    private static func history(for turn: ChatTurn, in turns: [ChatTurn]) -> [ChatMessage] {
        var messages = [ChatMessage.system(systemPrompt)]
        let recent = turns
            .filter { $0.phase == .done && $0.id != turn.id }
            .suffix(4)
        for item in recent {
            messages.append(.user(item.question))
            messages.append(.assistant(item.answer ?? ""))
        }
        messages.append(.user(turn.question))
        return messages
    }
}
