package com.tencent.iot.aiglasses.services.trtc

import android.os.Handler
import android.os.Looper
import com.tencent.iot.aiglasses.models.Language
import com.tencent.voiceai.TXRealtimeASR
import org.json.JSONObject
import java.util.UUID

data class ASRSegment(
    val segmentId: String,
    val text: String,
    val isCompleted: Boolean,
    val speakerId: Int
)

sealed interface RealtimeASREvent {
    data class Started(val voiceId: String) : RealtimeASREvent
    data class Segment(val segment: ASRSegment) : RealtimeASREvent
    data object Stopped : RealtimeASREvent
    data class Failed(val code: Int, val message: String) : RealtimeASREvent
    data class Volume(val level: Int) : RealtimeASREvent
}

class RealtimeASRService {
    var onEvent: ((RealtimeASREvent) -> Unit)? = null

    var isRunning = false
        private set

    private val engine = TXRealtimeASR()
    private val main = Handler(Looper.getMainLooper())

    private val listener = object : TXRealtimeASR.Listener {
        override fun onRealtimeASRStarted(voiceId: String?) = post(RealtimeASREvent.Started(voiceId.orEmpty()))

        override fun onReceiveRealtimeASRMessage(message: TXRealtimeASR.Message) = post(RealtimeASREvent.Segment(ASRSegment(
            segmentId = message.segmentId.orEmpty(),
            text = message.sourceText.orEmpty(),
            isCompleted = message.isCompleted,
            speakerId = message.speakerId
        )))

        override fun onRealtimeASRStopped() = post(RealtimeASREvent.Stopped)

        override fun onRealtimeASRError(errorCode: Int, errorMsg: String?) = post(RealtimeASREvent.Failed(errorCode, errorMsg.orEmpty()))

        override fun onRealtimeASRVolume(volume: Int) = post(RealtimeASREvent.Volume(volume))

        override fun onExperimentalEvent(eventName: String?, params: String?, data: ByteArray?) = Unit
    }

    init {
        engine.addListener(listener)
    }

    fun start(language: Language?, speakerDiarization: Boolean = false, denoiseStrategy: Int? = null) {
        if (isRunning) return
        val extra = JSONObject().put("extraRequestParams", if (speakerDiarization) "speaker_diarization=1" else "")
        denoiseStrategy?.let { extra.put("clientDenoiseStrategy", it) }
        engine.callExperimentalAPI(JSONObject()
            .put("api", "setExtraParams")
            .put("params", extra)
            .toString())
        val voiceId = UUID.randomUUID().toString()
        val params = TXRealtimeASR.Params().apply {
            sdkAppId = TRTCCredentials.SDK_APP_ID.toString()
            userSig = TRTCCredentials.userSig(voiceId)
            this.voiceId = voiceId
            sourceLanguage = language?.trtcCode.orEmpty()
            enableCustomCapture = false
        }
        isRunning = true
        engine.startRealtimeASR(params)
    }

    fun stop() {
        if (!isRunning) return
        isRunning = false
        engine.stopRealtimeASR()
    }

    private fun post(event: RealtimeASREvent) {
        main.post {
            if (event is RealtimeASREvent.Failed) isRunning = false
            onEvent?.invoke(event)
        }
    }
}
