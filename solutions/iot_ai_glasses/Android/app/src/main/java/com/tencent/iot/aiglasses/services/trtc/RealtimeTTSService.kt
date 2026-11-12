package com.tencent.iot.aiglasses.services.trtc

import android.os.Handler
import android.os.Looper
import com.tencent.iot.aiglasses.models.Language
import com.tencent.voiceai.TXRealtimeTTS
import org.json.JSONObject
import java.util.UUID

sealed interface RealtimeTTSEvent {
    data class Finished(val ok: Boolean, val code: Int, val message: String) : RealtimeTTSEvent
}

class RealtimeTTSService {

    var onEvent: ((RealtimeTTSEvent) -> Unit)? = null

    var isSpeaking = false
        private set

    private val engine = TXRealtimeTTS()
    private val main = Handler(Looper.getMainLooper())
    private var sessionActive = false
    private var sessionStarted = false

    private val listener = object : TXRealtimeTTS.TXRealtimeTTSListener {
        override fun onStarted() = post {
            sessionStarted = true
        }

        override fun onCompleted(code: Int, msg: String?) = post {
            if (!sessionActive) return@post
            if (code == TXRealtimeTTS.TXRealtimeTTSError.OK && !sessionStarted) return@post
            sessionActive = false
            isSpeaking = false
            onEvent?.invoke(RealtimeTTSEvent.Finished(code == TXRealtimeTTS.TXRealtimeTTSError.OK, code, msg.orEmpty()))
        }
    }

    init {
        engine.setListener(listener)
    }

    fun speak(text: String, language: Language? = null) {
        if (text.isBlank()) return
        if (sessionActive) engine.stop()
        if (language != null) {
            engine.callExperimentalAPI(JSONObject()
                .put("api", "setOnlineTTSExtraParams")
                .put("params", JSONObject().put("Language", language.trtcCode))
                .toString())
        }
        val userId = "tts_" + UUID.randomUUID().toString().take(8)
        val params = TXRealtimeTTS.TXRealtimeTTSParams().apply {
            online.appId = TRTCCredentials.SDK_APP_ID.toString()
            online.userId = userId
            online.userSig = TRTCCredentials.userSig(userId)
            voiceName = VOICE_NAME
        }
        val code = engine.start(params)
        if (code != TXRealtimeTTS.TXRealtimeTTSError.OK) {
            post { onEvent?.invoke(RealtimeTTSEvent.Finished(ok = false, code = code, message = "start failed")) }
            return
        }
        engine.appendText(UUID.randomUUID().toString(), text, true)
        sessionActive = true
        sessionStarted = false
        isSpeaking = true
    }

    fun stop() {
        if (!sessionActive) return
        sessionActive = false
        isSpeaking = false
        engine.stop()
    }

    private fun post(action: () -> Unit) {
        main.post(action)
    }

    private companion object {
        const val VOICE_NAME = "v-male-s5NqE0rZ"
    }
}
