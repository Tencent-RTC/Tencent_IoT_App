package com.tencent.iot.aiglasses.services.trtc

import com.tencent.iot.aiglasses.models.Language

class SpeechQueue {

    var onFailed: ((Int) -> Unit)? = null

    private var service: RealtimeTTSService? = null
    private val pending = ArrayDeque<Pair<String, Language>>()

    private val tts: RealtimeTTSService
        get() = service ?: RealtimeTTSService().also { tts ->
            tts.onEvent = { event ->
                if (event is RealtimeTTSEvent.Finished && !event.ok) onFailed?.invoke(event.code)
                next()
            }
            service = tts
        }

    fun enqueue(text: String, language: Language) {
        if (text.isBlank()) return
        pending.addLast(text to language)
        if (!tts.isSpeaking) next()
    }

    fun clear() {
        pending.clear()
        service?.stop()
    }

    private fun next() {
        val (text, language) = pending.removeFirstOrNull() ?: return
        tts.speak(text, language)
    }
}
