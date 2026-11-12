package com.tencent.iot.aiglasses.features.chat

import com.tencent.iot.aiglasses.services.ai.ChatCompletionClient
import com.tencent.iot.aiglasses.services.ai.ChatMessage
import com.tencent.iot.aiglasses.services.trtc.RealtimeASREvent
import com.tencent.iot.aiglasses.services.trtc.RealtimeASRService
import com.tencent.iot.aiglasses.services.trtc.RealtimeTTSEvent
import com.tencent.iot.aiglasses.services.trtc.RealtimeTTSService
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import java.util.UUID

data class ChatTurn(
    val id: UUID = UUID.randomUUID(),
    val question: String = "",
    val draft: String = "",
    val answer: String? = null,
    val phase: Phase = Phase.LISTENING
) {
    enum class Phase {
        LISTENING,
        THINKING,
        DONE,
        FAILED,
        INTERRUPTED
    }

    val displayQuestion: String
        get() = question + draft
}

class ChatController(
    private val scope: CoroutineScope,
    private val client: ChatCompletionClient = ChatCompletionClient.shared
) {
    var turns: List<ChatTurn> = emptyList()
        private set
    var isListening = false
        private set
    var speakingTurnID: UUID? = null
        private set
    var readsAloud = true
        private set

    var onChange: (() -> Unit)? = null
    var onToast: ((String) -> Unit)? = null

    val isEmpty: Boolean
        get() = turns.isEmpty()

    val isBusy: Boolean
        get() = isListening || turns.any { it.phase == ChatTurn.Phase.THINKING }

    val canRetry: Boolean
        get() = currentTurnID == null && requestID == null

    private var recognizer: RealtimeASRService? = null
    private var ttsEngine: RealtimeTTSService? = null
    private var activeSegmentID: String? = null
    private var currentTurnID: UUID? = null
    private val completedSegments = mutableSetOf<String>()
    private var lastCompletedWithoutID: String? = null
    private var replyJob: Job? = null
    private var requestID: UUID? = null
    private var requestTurnID: UUID? = null

    fun beginQuestion() {
        if (isListening) return
        invalidateReply()
        stopSpeaking()
        activeSegmentID = null
        currentTurnID = null
        completedSegments.clear()
        lastCompletedWithoutID = null
        val instance = RealtimeASRService()
        recognizer = instance
        instance.onEvent = { event ->
            if (recognizer === instance && isListening) handleASR(event)
        }
        isListening = true
        instance.start(null, denoiseStrategy = 2)
        onChange?.invoke()
    }

    fun pauseListening() {
        interrupt("", quiet = true)
    }

    fun retry(id: UUID) {
        val turn = turns.firstOrNull { it.id == id } ?: return
        if (turn.phase != ChatTurn.Phase.FAILED || !canRetry) return
        stopSpeaking()
        ask(turn)
    }

    fun interrupt(reason: String, quiet: Boolean = false) {
        val wasBusy = isBusy || speakingTurnID != null
        val instance = recognizer
        isListening = false
        recognizer = null
        instance?.onEvent = null
        invalidateReply()
        stopSpeaking()
        interruptDraft()
        instance?.stop()
        onChange?.invoke()
        if (!quiet && wasBusy) onToast?.invoke(reason)
    }

    private fun handleASR(event: RealtimeASREvent) {
        if (!isListening) return
        when (event) {
            is RealtimeASREvent.Segment -> {
                val segment = event.segment
                val text = segment.text.trim()
                if (text.isEmpty()) return
                val segmentID = segment.segmentId
                if (segmentID.isNotEmpty() && segmentID in completedSegments) return
                if (!segment.isCompleted || segmentID.isNotEmpty()) {
                    lastCompletedWithoutID = null
                } else if (lastCompletedWithoutID == text) {
                    return
                }
                invalidateReply()
                stopSpeaking()
                if (currentTurnID != null && activeSegmentID != segmentID) interruptDraft()
                val turn = currentTurn() ?: ChatTurn(draft = text).also {
                    turns = turns + it
                    currentTurnID = it.id
                    activeSegmentID = segmentID
                }
                if (segment.isCompleted) {
                    val completed = turn.copy(question = text, draft = "")
                    turns = turns.replace(completed)
                    if (segmentID.isNotEmpty()) completedSegments.add(segmentID) else lastCompletedWithoutID = text
                    currentTurnID = null
                    activeSegmentID = null
                    ask(completed)
                } else {
                    turns = turns.replace(turn.copy(draft = text))
                    onChange?.invoke()
                }
            }
            is RealtimeASREvent.Failed -> {
                val hadSpeech = currentTurn()?.displayQuestion?.isNotEmpty() == true
                interrupt("", quiet = true)
                onToast?.invoke(if (hadSpeech) "语音识别出错（${event.code}）：${event.message}" else "语音识别出错（${event.code}），请再试一次")
            }
            RealtimeASREvent.Stopped -> interrupt("聆听已结束，请重新开始")
            else -> Unit
        }
    }

    private fun speak(id: UUID, text: String) {
        stopSpeaking()
        val instance = RealtimeTTSService()
        ttsEngine = instance
        speakingTurnID = id
        instance.onEvent = { event ->
            if (ttsEngine === instance) handleTTS(event)
        }
        instance.speak(text)
        onChange?.invoke()
    }

    private fun handleTTS(event: RealtimeTTSEvent) {
        val finished = event as? RealtimeTTSEvent.Finished ?: return
        stopSpeaking()
        if (!finished.ok) onToast?.invoke("语音播报失败（${finished.code}）")
    }

    fun toggleReadsAloud() {
        readsAloud = !readsAloud
        if (!readsAloud) stopSpeaking()
        onToast?.invoke(if (readsAloud) "已开启回答播报" else "已关闭回答播报")
        onChange?.invoke()
    }

    fun stopSpeaking() {
        val instance = ttsEngine
        ttsEngine = null
        instance?.onEvent = null
        val wasSpeaking = speakingTurnID != null
        speakingTurnID = null
        instance?.stop()
        if (wasSpeaking) onChange?.invoke()
    }

    private fun currentTurn(): ChatTurn? = currentTurnID?.let { id -> turns.firstOrNull { it.id == id } }

    private fun interruptDraft() {
        currentTurn()?.let { turn ->
            turns = turns.replace(turn.copy(question = turn.displayQuestion, draft = "", phase = ChatTurn.Phase.INTERRUPTED))
        }
        activeSegmentID?.takeIf { it.isNotEmpty() }?.let(completedSegments::add)
        currentTurnID = null
        activeSegmentID = null
    }

    private fun invalidateReply() {
        val id = requestTurnID
        requestID = null
        requestTurnID = null
        val job = replyJob
        replyJob = null
        job?.cancel()
        turns.firstOrNull { it.id == id && it.phase == ChatTurn.Phase.THINKING }?.let { turn ->
            turns = turns.replace(turn.copy(phase = ChatTurn.Phase.INTERRUPTED))
        }
    }

    private fun ask(turn: ChatTurn) {
        if (turns.none { it.id == turn.id }) return
        invalidateReply()
        val token = UUID.randomUUID()
        requestID = token
        requestTurnID = turn.id
        turns = turns.replace(turn.copy(phase = ChatTurn.Phase.THINKING))
        onChange?.invoke()
        val messages = history(turn)
        replyJob = scope.launch {
            val answer = try {
                client.complete(messages)
            } catch (_: CancellationException) {
                return@launch
            } catch (_: Exception) {
                null
            }
            settle(token, turn.id, answer)
        }
    }

    private fun settle(token: UUID, id: UUID, answer: String?) {
        if (requestID != token || requestTurnID != id) return
        val turn = turns.firstOrNull { it.id == id && it.phase == ChatTurn.Phase.THINKING } ?: return
        requestID = null
        requestTurnID = null
        replyJob = null
        if (answer != null) {
            turns = turns.replace(turn.copy(answer = answer, phase = ChatTurn.Phase.DONE))
            if (readsAloud) speak(turn.id, answer)
        } else {
            turns = turns.replace(turn.copy(phase = ChatTurn.Phase.FAILED))
            onToast?.invoke("回答生成失败，请检查网络后重试")
        }
        onChange?.invoke()
    }

    private fun history(turn: ChatTurn): List<ChatMessage> {
        val messages = mutableListOf(ChatMessage.system(SYSTEM_PROMPT))
        turns.filter { it.phase == ChatTurn.Phase.DONE && it.id != turn.id }.takeLast(4).forEach {
            messages += ChatMessage.user(it.question)
            messages += ChatMessage.assistant(it.answer.orEmpty())
        }
        messages += ChatMessage.user(turn.question)
        return messages
    }

    private fun List<ChatTurn>.replace(turn: ChatTurn): List<ChatTurn> = map { if (it.id == turn.id) turn else it }

    private companion object {
        const val SYSTEM_PROMPT = "你是「AI眼镜」的语音助手。请用提问相同的语言回答，默认简体中文。" +
            "回答简洁口语化，一般不超过 120 字，不要使用 Markdown 格式。"
    }
}
