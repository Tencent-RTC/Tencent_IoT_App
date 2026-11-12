import Foundation
import Observation

struct ToastMessage: Equatable, Identifiable {
    let id = UUID()
    let text: String
}

@MainActor
@Observable
final class AppState {
    let glasses: any GlassesService
    private(set) var isOnline = true
    private(set) var session: ActiveSession?
    private(set) var records: [Record]
    private(set) var toast: ToastMessage?
    var dialog: AppDialog?

    private(set) var sourceLanguage: Language = .english
    private(set) var targetLanguage: Language = .chinese
    var savesTranslationText = true
    var readsTranslationAloud = true
    let chat = ChatController()
    let call = CallController()
    var keepsMeetingAudio = false

    var captionEngine: CaptionEngine {
        didSet { UserDefaults.standard.set(captionEngine.rawValue, forKey: Self.engineKey) }
    }

    var availableEngines: [CaptionEngine] {
        AIServiceConfig.isConfigured ? [.transcriber, .asrLLM] : [.transcriber]
    }

    private static let engineKey = "captionEngine"

    @ObservationIgnored private let store: RecordStore
    @ObservationIgnored private let asr = RealtimeASRService()
    @ObservationIgnored private let transcriber = LiveTranscriber()
    @ObservationIgnored private let translator: any TextTranslator = LLMTranslator()
    @ObservationIgnored private let reader = SpeechQueue()
    @ObservationIgnored private let network = NetworkMonitor()
    @ObservationIgnored private var spokenLines: Set<UUID> = []
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var toastDismissal: Task<Void, Never>?
    @ObservationIgnored private var summaryTasks: [UUID: Task<Void, Never>] = [:]

    init(glasses: any GlassesService = MockGlassesService(), store: RecordStore = RecordStore()) {
        self.glasses = glasses
        self.store = store
        captionEngine = UserDefaults.standard.string(forKey: Self.engineKey).flatMap(CaptionEngine.init(rawValue:)) ?? .transcriber
        records = store.load() ?? []
        if !availableEngines.contains(captionEngine) { captionEngine = .transcriber }
        asr.onEvent = { [weak self] in self?.handleASR($0) }
        transcriber.onEvent = { [weak self] in self?.handleTranscriber($0) }
        chat.onToast = { [weak self] in self?.showToast($0) }
        reader.onFailed = { [weak self] code in self?.showToast("译文朗读失败（\(code)）") }
        call.onEnded = { [weak self] message in
            guard let self, self.session?.kind == .call else { return }
            self.session = nil
            self.showToast(message)
        }
        network.onChange = { [weak self] in self?.setOnline($0) }
        network.start()
        startTicker()
    }

    var isConnected: Bool { glasses.isConnected }

    var batteryLevel: Int? { glasses.batteryLevel }

    var captureBlocker: String? {
        if !TRTCCredentials.isConfigured { return "请先在 TRTCCredentials 中配置 SDKAppID 与密钥" }
        if !isConnected { return "请先连接眼镜" }
        if !isOnline { return "网络未连接，请恢复后开始" }
        return nil
    }

    var canStartCapture: Bool { captureBlocker == nil }

    var isCapturing: Bool {
        guard let session else { return false }
        return !session.isPaused && isConnected
    }

    var canProcess: Bool { isCapturing && isOnline }

    func sessionStatus(_ session: ActiveSession) -> String {
        let state = if session.isPaused {
            "已暂停"
        } else if !isConnected {
            "等待重连"
        } else if !isOnline && session.kind.needsNetwork {
            "网络中断"
        } else {
            "进行中"
        }
        return session.kind.shortLabel + state
    }

    func setSourceLanguage(_ language: Language) {
        sourceLanguage = language
        if targetLanguage == language { targetLanguage = language.other }
    }

    func setTargetLanguage(_ language: Language) {
        targetLanguage = language
        if sourceLanguage == language { sourceLanguage = language.other }
    }

    func swapLanguages() {
        (sourceLanguage, targetLanguage) = (targetLanguage, sourceLanguage)
    }

    func setConnected(_ connected: Bool) {
        guard connected != isConnected else { return }
        if connected {
            reconnect()
        } else {
            glasses.disconnect()
            syncLive()
            call.setGlassesConnected(false)
            showToast(session == nil ? "眼镜已断开" : "眼镜已断开，收音中断，已有内容保留")
            chat.interrupt("眼镜已断开，收音已停止")
        }
    }

    func reconnect() {
        glasses.connect()
        syncLive()
        call.setGlassesConnected(true)
        if let session {
            showToast(session.isPaused ? "眼镜已重连，会话保持暂停" : "眼镜已重连，继续当前记录")
        } else {
            showToast("眼镜已连接，可以开始使用")
        }
    }

    private func setOnline(_ online: Bool) {
        guard online != isOnline else { return }
        isOnline = online
        if session == nil {
            showToast(online ? "网络已恢复" : "网络已中断")
        } else {
            showToast(online ? "网络已恢复，字幕继续更新" : "网络中断，字幕已暂停")
        }
        if !online {
            chat.interrupt("网络中断，提问已停止")
        } else {
            for record in records where record.kind == .meeting && record.summary?.phase == .pending {
                generateSummary(record.id)
            }
        }
    }

    func isSummaryGenerating(_ recordID: UUID) -> Bool {
        summaryTasks[recordID] != nil
    }

    func retrySummary(_ recordID: UUID) {
        guard let index = records.firstIndex(where: { $0.id == recordID }), records[index].kind == .meeting else { return }
        records[index].summary = MeetingSummary()
        persistRecords()
        generateSummary(recordID)
    }

    func toggleMeetingTodo(_ recordID: UUID, todoID: UUID) {
        guard let index = records.firstIndex(where: { $0.id == recordID }),
              let todoIndex = records[index].summary?.todos.firstIndex(where: { $0.id == todoID }) else { return }
        records[index].summary?.todos[todoIndex].isDone.toggle()
        persistRecords()
    }

    private func generateSummary(_ recordID: UUID) {
        guard summaryTasks[recordID] == nil,
              let index = records.firstIndex(where: { $0.id == recordID }),
              records[index].kind == .meeting,
              records[index].summary?.phase == .pending else { return }
        guard isOnline else { return }
        let record = records[index]
        let title = record.title
        let duration = record.durationSeconds
        let lines = record.transcript ?? []
        summaryTasks[recordID] = Task { [weak self] in
            do {
                let summary = try await MeetingSummarizer().summarize(title: title, durationSeconds: duration, lines: lines)
                self?.finishSummary(recordID, summary)
            } catch {
                print("[MeetingSummary] \(error.localizedDescription)")
                self?.failSummary(recordID)
            }
        }
    }

    private func finishSummary(_ recordID: UUID, _ summary: MeetingSummary) {
        summaryTasks[recordID] = nil
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { return }
        records[index].summary = summary
        if let title = summary.title, !title.isEmpty {
            records[index].title = title
        }
        persistRecords()
    }

    static func temporaryMeetingTitle(date: Date = .now) -> String {
        let c = Calendar.current.dateComponents([.month, .day, .hour, .minute], from: date)
        return String(format: "%d月%d日 %02d:%02d 会议", c.month ?? 1, c.day ?? 1, c.hour ?? 0, c.minute ?? 0)
    }

    private func failSummary(_ recordID: UUID) {
        summaryTasks[recordID] = nil
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { return }
        records[index].summary?.phase = .failed
        persistRecords()
    }

    @discardableResult
    func startSession(_ kind: SessionKind) -> Bool {
        guard session == nil, !chat.isBusy, canStartCapture else { return false }
        dialog = nil
        beginSession(kind)
        syncLive()
        return true
    }

    private func beginSession(_ kind: SessionKind) {
        chat.interrupt("已停止聆听", quiet: true)
        spokenLines.removeAll()
        session = ActiveSession(
            kind: kind,
            source: sourceLanguage,
            target: targetLanguage,
            savesText: savesTranslationText,
            readsAloud: kind != .translation || readsTranslationAloud,
            engine: kind == .meeting ? .asrLLM : captionEngine
        )
        if kind == .meeting {
            self.session?.title = Self.temporaryMeetingTitle()
            self.session?.keepsAudio = keepsMeetingAudio
            self.session?.source = .chinese
            self.session?.target = .chinese
        }
    }

    func togglePause() {
        guard let session else { return }
        self.session?.isPaused = !session.isPaused
        syncLive()
        showToast(session.isPaused ? "已继续" : "已暂停")
    }

    func toggleStar() {
        guard session?.kind == .meeting else { return }
        session?.isStarred.toggle()
        showToast(session?.isStarred == true ? "已将本场会议标为星标" : "已取消星标")
    }

    func toggleReadAloud() {
        readsTranslationAloud.toggle()
        guard session?.kind == .translation else { return }
        session?.readsAloud = readsTranslationAloud
        if !readsTranslationAloud { reader.clear() }
        showToast(readsTranslationAloud ? "已开启译文播报" : "已关闭译文播报")
    }

    func setCaptionEngine(_ engine: CaptionEngine) {
        guard engine != captionEngine else { return }
        captionEngine = engine
        guard let session, session.kind == .translation || session.kind == .interpret else { return }
        stopLive()
        self.session?.engine = engine
        syncLive()
    }

    func setSavesTranslationText(_ value: Bool) {
        savesTranslationText = value
        if session?.kind == .translation { session?.savesText = value }
    }

    func setKeepsMeetingAudio(_ value: Bool) {
        keepsMeetingAudio = value
        if session?.kind == .meeting { session?.keepsAudio = value }
    }

    func switchSpeaking() {
        guard let session else { return }
        let next: Speaker = session.speaking == .other ? .me : .other
        self.session?.speaking = next
        if session.engine == .asrLLM {
            self.session?.asrRun += 1
            asr.stop()
            syncLive()
        }
    }

    @discardableResult
    func finishSession() -> Record? {
        guard var session else { return nil }
        stopLive()
        session.entries.removeAll { $0.original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var saved: Record?
        if session.kind == .meeting {
            let record = Record(
                kind: .meeting,
                title: session.title.isEmpty ? "未命名会议" : session.title,
                createdAt: .now,
                durationSeconds: session.seconds,
                transcript: session.entries,
                keepsAudio: session.keepsAudio,
                summary: AIServiceConfig.isConfigured ? MeetingSummary() : nil,
                isStarred: session.isStarred ? true : nil
            )
            records.insert(record, at: 0)
            persistRecords()
            saved = record
            if AIServiceConfig.isConfigured {
                generateSummary(record.id)
            }
        } else if session.kind == .translation || session.kind == .interpret, session.savesText {
            let arrow = session.kind == .interpret ? "⇄" : "→"
            let suffix = session.kind == .interpret ? "双向传译" : "翻译记录"
            let record = Record(
                kind: .translation,
                title: "\(session.source.rawValue) \(arrow) \(session.target.rawValue) · \(suffix)",
                createdAt: .now,
                durationSeconds: session.seconds,
                transcript: session.entries,
                source: session.source,
                target: session.target,
                isInterpret: session.kind == .interpret
            )
            records.insert(record, at: 0)
            persistRecords()
            saved = record
        }
        self.session = nil
        dialog = nil
        showToast(saved == nil ? "会话已结束" : "已保存到记录")
        return saved
    }

    func discardSession() {
        guard session != nil else { return }
        stopLive()
        session = nil
        dialog = nil
        showToast("已结束，内容未保存")
    }

    @discardableResult
    func startCall(roomId: String, userId: String) -> Bool {
        guard session == nil, !chat.isBusy, canStartCapture else { return false }
        beginSession(.call)
        self.session?.title = roomId
        call.start(roomId: roomId, userId: userId, glassesConnected: isConnected)
        return true
    }

    func hangUp() {
        guard session?.kind == .call else { return }
        call.stop()
        session = nil
        showToast("通话已结束")
    }

    func showToast(_ text: String) {
        toast = ToastMessage(text: text)
        toastDismissal?.cancel()
        toastDismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    private func heardLanguage(_ session: ActiveSession) -> Language {
        session.speaking == .me ? session.target : session.source
    }

    private func syncLive() {
        guard let session, session.kind != .call else {
            stopLive()
            return
        }
        let active = !session.isPaused && isConnected
        if !active { reader.clear() }
        let heard = heardLanguage(session)
        switch session.engine {
        case .asrLLM:
            guard active else {
                asr.stop()
                return
            }
            guard !asr.isRunning else { return }
            self.session?.asrRun += 1
            asr.start(language: heard, sdkAppId: TRTCCredentials.sdkAppId, secretKey: TRTCCredentials.secretKey, speakerDiarization: session.kind == .meeting, denoiseStrategy: session.kind == .meeting ? 1 : 3)
        case .transcriber:
            if active, !transcriber.isRunning {
                self.session?.asrRun += 1
                transcriber.start(
                    source: session.kind == .interpret ? "zh_en" : heard.trtcCode,
                    targets: session.kind == .meeting ? nil : Language.allCases
                )
            }
            transcriber.setCapturing(active)
        }
    }

    private func stopLive() {
        reader.clear()
        asr.stop()
        transcriber.stop()
    }

    private func readAloud(_ lineID: UUID, text: String, language: Language) {
        guard let session, session.kind == .translation || session.kind == .interpret, session.readsAloud, !session.isPaused else { return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, spokenLines.insert(lineID).inserted else { return }
        reader.enqueue(text, language: language)
    }

    @discardableResult
    private func upsertLine(segmentId: String, original: String, translated: String?, speakerLabel: String? = nil) -> UUID? {
        guard let session else { return nil }
        let text = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = "\(session.asrRun)-\(segmentId)"
        if let id = session.asrSegments[key], let index = session.entries.firstIndex(where: { $0.id == id }) {
            self.session?.entries[index].original = text
            if let translated, !translated.isEmpty { self.session?.entries[index].translated = translated }
            if let speakerLabel {
                self.session?.entries[index].speakerLabel = speakerLabel
            }
            return id
        }
        guard !text.isEmpty else { return nil }
        let line = TranscriptLine(original: text, translated: translated ?? "", speaker: session.speaking, time: session.seconds, speakerLabel: speakerLabel)
        self.session?.entries.append(line)
        self.session?.asrSegments[key] = line.id
        return line.id
    }

    private func handleTranscriber(_ event: LiveTranscriberEvent) {
        guard session?.engine == .transcriber else { return }
        switch event {
        case .segment(let id, let source, let translations, let isCompleted):
            guard let session else { return }
            let spoken = heardLanguage(session)
            let translation: String?
            if session.kind == .meeting {
                translation = nil
            } else {
                translation = (translations[spoken.other.trtcCode] ?? (translations.count == 1 ? translations.values.first : nil))
                    .flatMap { value in value != source ? value : nil }
            }
            let lineID = upsertLine(segmentId: id, original: source, translated: translation)
            if isCompleted, let lineID, let translation {
                readAloud(lineID, text: translation, language: spoken.other)
            }
        case .failed(let code, let message):
            self.session?.isPaused = true
            showToast("AI 转写出错（\(code)）：\(message)")
        }
    }

    private func handleASR(_ event: RealtimeASREvent) {
        guard let session, session.engine == .asrLLM else { return }
        switch event {
        case .segment(let segment):
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = session.kind == .meeting ? Self.speakerLabel(for: segment.speakerId) : nil
            let lineID = upsertLine(segmentId: segment.segmentId, original: text, translated: nil, speakerLabel: label)
            if segment.isCompleted, !text.isEmpty, let lineID, session.kind != .meeting {
                let heard = heardLanguage(session)
                translate(lineID, text: text, from: heard, to: heard.other)
            }
        case .failed(let code, let message):
            self.session?.isPaused = true
            showToast("实时识别出错（\(code)）：\(message)")
        case .started, .stopped, .volume:
            break
        }
    }

    private static func speakerLabel(for speakerId: Int) -> String? {
        speakerId > 0 ? "发言人 \(speakerId)" : nil
    }

    private func translate(_ lineID: UUID, text: String, from source: Language, to target: Language) {
        Task { [weak self, translator] in
            let result = await translator.translate(text, from: source, to: target)
            guard let self else { return }
            guard let result else {
                self.showToast("翻译失败，请检查网络")
                return
            }
            guard let index = self.session?.entries.firstIndex(where: { $0.id == lineID }) else { return }
            self.session?.entries[index].translated = result
            self.readAloud(lineID, text: result, language: target)
        }
    }

    private func persistRecords() {
        do {
            try store.save(records)
        } catch {
            showToast("本地保存不可用，记录仅在本次使用期间保留")
        }
    }

    private func startTicker() {
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.tick()
            }
        }
    }

    private func tick() {
        guard let session else { return }
        if session.kind == .call ? call.phase == .inCall : isCapturing { self.session?.seconds += 1 }
    }
}
