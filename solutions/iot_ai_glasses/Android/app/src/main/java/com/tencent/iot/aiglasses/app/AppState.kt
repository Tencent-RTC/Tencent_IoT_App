package com.tencent.iot.aiglasses.app

import android.content.Context
import android.util.Log
import com.tencent.iot.aiglasses.features.call.CallController
import com.tencent.iot.aiglasses.features.chat.ChatController
import com.tencent.iot.aiglasses.models.ActiveSession
import com.tencent.iot.aiglasses.models.MeetingSummary
import com.tencent.iot.aiglasses.models.CaptionEngine
import com.tencent.iot.aiglasses.models.Language
import com.tencent.iot.aiglasses.models.Record
import com.tencent.iot.aiglasses.models.RecordKind
import com.tencent.iot.aiglasses.models.SessionKind
import com.tencent.iot.aiglasses.models.Speaker
import com.tencent.iot.aiglasses.models.TranscriptLine
import com.tencent.iot.aiglasses.services.GlassesService
import com.tencent.iot.aiglasses.services.LLMTranslator
import com.tencent.iot.aiglasses.services.MockGlassesService
import com.tencent.iot.aiglasses.services.NetworkMonitor
import com.tencent.iot.aiglasses.services.RecordStore
import com.tencent.iot.aiglasses.services.ai.AIServiceConfig
import com.tencent.iot.aiglasses.services.ai.MeetingSummarizer
import com.tencent.iot.aiglasses.services.trtc.LiveTranscriber
import com.tencent.iot.aiglasses.services.trtc.LiveTranscriberEvent
import com.tencent.iot.aiglasses.services.trtc.RealtimeASREvent
import com.tencent.iot.aiglasses.services.trtc.RealtimeASRService
import com.tencent.iot.aiglasses.services.trtc.SpeechQueue
import com.tencent.iot.aiglasses.services.trtc.TRTCCredentials
import com.tencent.iot.aiglasses.services.trtc.trtcCode
import kotlinx.coroutines.Job
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDateTime
import java.util.UUID

data class ToastMessage(val text: String, val id: UUID = UUID.randomUUID())

class AppState(
    private val context: Context,
    val glasses: GlassesService = MockGlassesService(),
    private val store: RecordStore = RecordStore(context)
) {
    private val prefs = context.getSharedPreferences("suisheng", Context.MODE_PRIVATE)
    private val scope = MainScope()
    private val revision = MutableStateFlow(0)
    private var toastDismissal: Job? = null
    private val summaryJobs = mutableMapOf<UUID, Job>()
    private val hasRealtimeASR = runCatching { Class.forName("com.tencent.voiceai.TXRealtimeASR") }.isSuccess
    private val translator = LLMTranslator()
    private val reader = SpeechQueue()
    private val network = NetworkMonitor(context)
    private val spokenLines = mutableSetOf<UUID>()
    private var realtimeASR: RealtimeASRService? = null
    private val asr: RealtimeASRService
        get() = realtimeASR ?: RealtimeASRService().also {
            it.onEvent = ::handleASR
            realtimeASR = it
        }
    private var liveTranscriber: LiveTranscriber? = null
    private var callController: CallController? = null
    val chat = ChatController(scope)
    val call: CallController
        get() = callController ?: CallController(context).also { controller ->
            controller.onChange = ::notifyChanged
            controller.onEnded = { message ->
                if (session?.kind == SessionKind.CALL) {
                    session = null
                    showToast(message)
                }
            }
            callController = controller
        }
    private val transcriber: LiveTranscriber
        get() = liveTranscriber ?: LiveTranscriber(context).also {
            it.onEvent = ::handleTranscriber
            liveTranscriber = it
        }

    val changes: StateFlow<Int> = revision

    var isOnline = true
        private set
    var session: ActiveSession? = null
        private set
    var records: List<Record>
        private set
    var toast: ToastMessage? = null
        private set
    var dialog: AppDialog? = null
        set(value) {
            field = value
            notifyChanged()
        }

    var sourceLanguage = Language.ENGLISH
        private set
    var targetLanguage = Language.CHINESE
        private set
    var savesTranslationText = true
        set(value) {
            field = value
            notifyChanged()
        }
    var readsTranslationAloud = true
        set(value) {
            field = value
            notifyChanged()
        }
    var keepsMeetingAudio = false
        set(value) {
            field = value
            notifyChanged()
        }

    var captionEngine: CaptionEngine = CaptionEngine.TRANSCRIBER
        private set

    val availableEngines: List<CaptionEngine>
        get() = if (AIServiceConfig.isConfigured && hasRealtimeASR) {
            listOf(CaptionEngine.TRANSCRIBER, CaptionEngine.ASR_LLM)
        } else {
            listOf(CaptionEngine.TRANSCRIBER)
        }

    init {
        captionEngine = CaptionEngine.from(prefs.getString(ENGINE_KEY, null))?.takeIf { it in availableEngines } ?: CaptionEngine.TRANSCRIBER
        records = store.load().orEmpty()
        chat.onChange = ::notifyChanged
        chat.onToast = ::showToast
        reader.onFailed = { code -> showToast("译文朗读失败（$code）") }
        network.onChange = ::setOnline
        network.start()
        startTicker()
    }

    val isConnected: Boolean
        get() = glasses.isConnected

    val batteryLevel: Int?
        get() = glasses.batteryLevel

    val captureBlocker: String?
        get() = when {
            !TRTCCredentials.isConfigured -> "请先在 TRTCCredentials 中配置 SDKAppID 与密钥"
            !isConnected -> "请先连接眼镜"
            !isOnline -> "网络未连接，请恢复后开始"
            else -> null
        }

    val canStartCapture: Boolean
        get() = captureBlocker == null

    val isCapturing: Boolean
        get() = session?.let { !it.isPaused && isConnected } ?: false

    val canProcess: Boolean
        get() = isCapturing && isOnline

    fun sessionStatus(session: ActiveSession): String {
        val state = when {
            session.isPaused -> "已暂停"
            !isConnected -> "等待重连"
            !isOnline && session.kind.needsNetwork -> "网络中断"
            else -> "进行中"
        }
        return session.kind.shortLabel + state
    }

    fun setSourceLanguage(language: Language) {
        sourceLanguage = language
        if (targetLanguage == language) targetLanguage = language.other
        notifyChanged()
    }

    fun setTargetLanguage(language: Language) {
        targetLanguage = language
        if (sourceLanguage == language) sourceLanguage = language.other
        notifyChanged()
    }

    fun swapLanguages() {
        sourceLanguage = targetLanguage.also { targetLanguage = sourceLanguage }
        notifyChanged()
    }

    fun setConnected(connected: Boolean) {
        if (connected == isConnected) return
        if (connected) {
            reconnect()
        } else {
            glasses.disconnect()
            syncLive()
            callController?.setGlassesConnected(false)
            showToast(if (session == null) "眼镜已断开" else "眼镜已断开，收音中断，已有内容保留")
            chat.interrupt("眼镜已断开，收音已停止")
        }
    }

    fun reconnect() {
        glasses.connect()
        syncLive()
        callController?.setGlassesConnected(true)
        val session = session
        showToast(
            when {
                session == null -> "眼镜已连接，可以开始使用"
                session.isPaused -> "眼镜已重连，会话保持暂停"
                else -> "眼镜已重连，继续当前记录"
            }
        )
    }

    private fun setOnline(online: Boolean) {
        if (online == isOnline) return
        isOnline = online
        if (session == null) {
            showToast(if (online) "网络已恢复" else "网络已中断")
        } else {
            showToast(if (online) "网络已恢复，字幕继续更新" else "网络中断，字幕已暂停")
        }
        if (!online) {
            chat.interrupt("网络中断，提问已停止")
        } else {
            records.filter { it.kind == RecordKind.MEETING && it.summary?.phase == MeetingSummary.Phase.PENDING }
                .forEach { generateSummary(it.id) }
        }
    }

    fun isSummaryGenerating(recordID: UUID): Boolean = summaryJobs.containsKey(recordID)

    fun retrySummary(recordID: UUID) {
        if (records.none { it.id == recordID && it.kind == RecordKind.MEETING }) return
        updateRecord(recordID) { it.copy(summary = MeetingSummary()) }
        generateSummary(recordID)
    }

    fun toggleMeetingTodo(recordID: UUID, todoID: UUID) {
        updateRecord(recordID) { record ->
            val summary = record.summary ?: return@updateRecord record
            record.copy(summary = summary.copy(todos = summary.todos.map { if (it.id == todoID) it.copy(isDone = !it.isDone) else it }))
        }
    }

    private fun updateRecord(recordID: UUID, transform: (Record) -> Record) {
        if (records.none { it.id == recordID }) return
        records = records.map { if (it.id == recordID) transform(it) else it }
        persistRecords()
        notifyChanged()
    }

    private fun generateSummary(recordID: UUID) {
        val record = records.firstOrNull { it.id == recordID } ?: return
        if (summaryJobs.containsKey(recordID) || record.kind != RecordKind.MEETING || record.summary?.phase != MeetingSummary.Phase.PENDING) return
        if (!isOnline) return
        summaryJobs[recordID] = scope.launch {
            val result = runCatching { MeetingSummarizer().summarize(record.title, record.durationSeconds, record.transcript.orEmpty()) }
            summaryJobs.remove(recordID)
            result.onSuccess { summary ->
                updateRecord(recordID) { it.copy(summary = summary, title = summary.title?.takeIf(String::isNotBlank) ?: it.title) }
            }.onFailure { error ->
                Log.w("MeetingSummary", error.message.orEmpty())
                updateRecord(recordID) { it.copy(summary = it.summary?.copy(phase = MeetingSummary.Phase.FAILED)) }
            }
        }
        notifyChanged()
    }

    private fun temporaryMeetingTitle(): String {
        val now = LocalDateTime.now()
        return "${now.monthValue}月${now.dayOfMonth}日 ${now.hour.toString().padStart(2, '0')}:${now.minute.toString().padStart(2, '0')} 会议"
    }

    fun startSession(kind: SessionKind): Boolean {
        if (session != null || !canStartCapture || chat.isBusy) return false
        dialog = null
        beginSession(kind)
        syncLive()
        return true
    }

    private fun beginSession(kind: SessionKind) {
        chat.interrupt("", quiet = true)
        spokenLines.clear()
        session = ActiveSession(
            kind = kind,
            source = sourceLanguage,
            target = targetLanguage,
            savesText = savesTranslationText,
            readsAloud = kind != SessionKind.TRANSLATION || readsTranslationAloud,
            engine = when {
                kind != SessionKind.MEETING -> captionEngine
                hasRealtimeASR -> CaptionEngine.ASR_LLM
                else -> CaptionEngine.TRANSCRIBER
            }
        ).apply {
            if (kind == SessionKind.MEETING) {
                title = temporaryMeetingTitle()
                keepsAudio = keepsMeetingAudio
                source = Language.CHINESE
                target = Language.CHINESE
            }
        }
        notifyChanged()
    }

    fun togglePause() {
        val session = session ?: return
        val wasPaused = session.isPaused
        session.isPaused = !wasPaused
        syncLive()
        showToast(if (wasPaused) "已继续" else "已暂停")
    }

    fun toggleStar() {
        val session = session?.takeIf { it.kind == SessionKind.MEETING } ?: return
        session.isStarred = !session.isStarred
        showToast(if (session.isStarred) "已将本场会议标为星标" else "已取消星标")
        notifyChanged()
    }

    fun toggleReadAloud() {
        readsTranslationAloud = !readsTranslationAloud
        val session = session?.takeIf { it.kind == SessionKind.TRANSLATION } ?: return
        session.readsAloud = readsTranslationAloud
        if (!readsTranslationAloud) reader.clear()
        showToast(if (readsTranslationAloud) "已开启译文播报" else "已关闭译文播报")
    }

    fun updateCaptionEngine(engine: CaptionEngine) {
        if (engine == captionEngine) return
        captionEngine = engine
        prefs.edit().putString(ENGINE_KEY, engine.rawValue).apply()
        val session = session?.takeIf { it.kind == SessionKind.TRANSLATION || it.kind == SessionKind.INTERPRET }
        if (session != null) {
            stopLive()
            session.engine = engine
            syncLive()
        }
        notifyChanged()
    }

    fun updateSavesTranslationText(value: Boolean) {
        session?.takeIf { it.kind == SessionKind.TRANSLATION }?.savesText = value
        savesTranslationText = value
    }

    fun updateKeepsMeetingAudio(value: Boolean) {
        session?.takeIf { it.kind == SessionKind.MEETING }?.keepsAudio = value
        keepsMeetingAudio = value
    }

    fun switchSpeaking() {
        val session = session ?: return
        session.speaking = if (session.speaking == Speaker.OTHER) Speaker.ME else Speaker.OTHER
        if (session.engine == CaptionEngine.ASR_LLM) {
            session.asrRun += 1
            realtimeASR?.stop()
            syncLive()
        }
        notifyChanged()
    }

    fun finishSession(): Record? {
        val session = session ?: return null
        stopLive()
        session.entries.removeAll { it.original.isBlank() }
        var saved: Record? = null
        if (session.kind == SessionKind.MEETING) {
            val record = Record(
                kind = RecordKind.MEETING,
                title = session.title.ifEmpty { "未命名会议" },
                createdAt = Instant.now(),
                durationSeconds = session.seconds,
                transcript = session.entries.map { it.copy() },
                keepsAudio = session.keepsAudio,
                summary = if (AIServiceConfig.isConfigured) MeetingSummary() else null,
                isStarred = session.isStarred
            )
            records = listOf(record) + records
            persistRecords()
            saved = record
            if (AIServiceConfig.isConfigured) generateSummary(record.id)
        } else if ((session.kind == SessionKind.TRANSLATION || session.kind == SessionKind.INTERPRET) && session.savesText) {
            val arrow = if (session.kind == SessionKind.INTERPRET) "⇄" else "→"
            val suffix = if (session.kind == SessionKind.INTERPRET) "双向传译" else "翻译记录"
            val record = Record(
                kind = RecordKind.TRANSLATION,
                title = "${session.source.rawValue} $arrow ${session.target.rawValue} · $suffix",
                createdAt = Instant.now(),
                durationSeconds = session.seconds,
                transcript = session.entries.map { it.copy() },
                source = session.source,
                target = session.target,
                isInterpret = session.kind == SessionKind.INTERPRET
            )
            records = listOf(record) + records
            persistRecords()
            saved = record
        }
        this.session = null
        dialog = null
        showToast(if (saved == null) "会话已结束" else "已保存到记录")
        return saved
    }

    fun discardSession() {
        if (session == null) return
        stopLive()
        session = null
        dialog = null
        showToast("已结束，内容未保存")
        notifyChanged()
    }

    fun startCall(roomId: String, userId: String): Boolean {
        if (session != null || !canStartCapture || chat.isBusy) return false
        beginSession(SessionKind.CALL)
        session?.title = roomId
        call.start(roomId, userId, isConnected)
        return true
    }

    fun hangUp() {
        if (session?.kind != SessionKind.CALL) return
        callController?.stop()
        session = null
        showToast("通话已结束")
    }

    fun showToast(text: String) {
        toast = ToastMessage(text)
        notifyChanged()
        toastDismissal?.cancel()
        toastDismissal = scope.launch {
            delay(2400)
            toast = null
            notifyChanged()
        }
    }

    private fun heardLanguage(session: ActiveSession): Language =
        if (session.speaking == Speaker.ME) session.target else session.source

    private fun syncLive() {
        val session = session
        if (session == null || session.kind == SessionKind.CALL) {
            stopLive()
            return
        }
        val active = !session.isPaused && isConnected
        if (!active) reader.clear()
        val heard = heardLanguage(session)
        when (session.engine) {
            CaptionEngine.ASR_LLM -> {
                if (!active) {
                    realtimeASR?.stop()
                } else if (!asr.isRunning) {
                    session.asrRun += 1
                    asr.start(heard, speakerDiarization = session.kind == SessionKind.MEETING, denoiseStrategy = if (session.kind == SessionKind.MEETING) 1 else 3)
                }
            }
            CaptionEngine.TRANSCRIBER -> {
                if (active && !transcriber.isRunning) {
                    session.asrRun += 1
                    transcriber.start(
                        if (session.kind == SessionKind.INTERPRET) "zh_en" else heard.trtcCode,
                        if (session.kind == SessionKind.MEETING) null else Language.entries
                    )
                }
                transcriber.setCapturing(active)
            }
        }
    }

    private fun stopLive() {
        reader.clear()
        realtimeASR?.stop()
        liveTranscriber?.stop()
    }

    private fun readAloud(lineID: UUID, text: String, language: Language) {
        val session = session ?: return
        if ((session.kind != SessionKind.TRANSLATION && session.kind != SessionKind.INTERPRET) || !session.readsAloud || session.isPaused) return
        if (text.isBlank() || !spokenLines.add(lineID)) return
        reader.enqueue(text, language)
    }

    private fun upsertLine(segmentId: String, original: String, translated: String?, speakerLabel: String? = null): UUID? {
        val session = session ?: return null
        val text = original.trim()
        val key = "${session.asrRun}-$segmentId"
        val existing = session.asrSegments[key]?.let { id -> session.entries.firstOrNull { it.id == id } }
        if (existing != null) {
            existing.original = text
            if (!translated.isNullOrEmpty()) existing.translated = translated
            if (speakerLabel != null) existing.speakerLabel = speakerLabel
            notifyChanged()
            return existing.id
        }
        if (text.isEmpty()) return null
        val line = TranscriptLine(original = text, translated = translated.orEmpty(), speaker = session.speaking, time = session.seconds, speakerLabel = speakerLabel)
        session.entries += line
        session.asrSegments[key] = line.id
        notifyChanged()
        return line.id
    }

    private fun handleTranscriber(event: LiveTranscriberEvent) {
        if (session?.engine != CaptionEngine.TRANSCRIBER) return
        when (event) {
            is LiveTranscriberEvent.Segment -> {
                val current = session
                if (current == null) return
                val spoken = heardLanguage(current)
                val translation = if (current.kind == SessionKind.MEETING) {
                    null
                } else {
                    (event.translations[spoken.other.trtcCode] ?: event.translations.values.singleOrNull())
                        ?.takeIf { it != event.source }
                }
                val lineID = upsertLine(event.id, event.source, translation)
                if (event.isCompleted && lineID != null && translation != null) readAloud(lineID, translation, spoken.other)
            }
            is LiveTranscriberEvent.Failed -> {
                session?.isPaused = true
                showToast("AI 转写出错（${event.code}）：${event.message}")
            }
        }
    }

    private fun handleASR(event: RealtimeASREvent) {
        val session = session ?: return
        if (session.engine != CaptionEngine.ASR_LLM) return
        when (event) {
            is RealtimeASREvent.Segment -> {
                val segment = event.segment
                val text = segment.text.trim()
                val label = if (session.kind == SessionKind.MEETING && segment.speakerId > 0) "发言人 ${segment.speakerId}" else null
                val lineID = upsertLine(segment.segmentId, text, null, label)
                if (segment.isCompleted && text.isNotEmpty() && lineID != null && session.kind != SessionKind.MEETING) {
                    val heard = heardLanguage(session)
                    translate(lineID, text, heard, heard.other)
                }
            }
            is RealtimeASREvent.Failed -> {
                session.isPaused = true
                showToast("实时识别出错（${event.code}）：${event.message}")
            }
            else -> Unit
        }
    }

    private fun translate(lineID: UUID, text: String, source: Language, target: Language) {
        scope.launch {
            val result = translator.translate(text, source, target)
            if (result == null) {
                showToast("翻译失败，请检查网络")
                return@launch
            }
            session?.entries?.firstOrNull { it.id == lineID }?.let {
                it.translated = result
                notifyChanged()
                readAloud(lineID, result, target)
            }
        }
    }

    private fun persistRecords() {
        runCatching { store.save(records) }.onFailure {
            showToast("本地保存不可用，记录仅在本次使用期间保留")
        }
    }

    private fun startTicker() {
        scope.launch {
            while (isActive) {
                delay(1000)
                tick()
            }
        }
    }

    private fun tick() {
        val session = session ?: return
        if (if (session.kind == SessionKind.CALL) callController?.phase == CallController.Phase.IN_CALL else isCapturing) {
            session.seconds += 1
            notifyChanged()
        }
    }

    private fun notifyChanged() {
        revision.value += 1
    }

    companion object {
        private const val ENGINE_KEY = "captionEngine"
    }
}
