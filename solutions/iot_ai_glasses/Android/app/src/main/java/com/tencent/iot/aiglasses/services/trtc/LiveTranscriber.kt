package com.tencent.iot.aiglasses.services.trtc

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.tencent.iot.aiglasses.models.Language

sealed interface LiveTranscriberEvent {
    data class Segment(val id: String, val source: String, val translations: Map<String, String>, val isCompleted: Boolean) : LiveTranscriberEvent
    data class Failed(val code: Int, val message: String) : LiveTranscriberEvent
}

class LiveTranscriber(private val context: Context, private val trtc: TRTCService = TRTCService.shared(context)) {

    var onEvent: ((LiveTranscriberEvent) -> Unit)? = null

    var isRunning = false
        private set

    private var source = "en"
    private var targets: List<Language>? = listOf(Language.CHINESE)
    private var capturing = true
    private var retries = 0
    private val main = Handler(Looper.getMainLooper())
    private val retry = Runnable { if (isRunning) startTranscriber() }
    private val userId: String
        get() = TRTCCredentials.userId(context)

    init {
        trtc.addObserver(::handle)
    }

    fun start(source: String, targets: List<Language>?) {
        if (isRunning) return
        this.source = source
        this.targets = targets
        isRunning = true
        retries = 0
        capturing = true
        val userId = userId
        trtc.enterRoom(TRTCRoomConfig(
            sdkAppId = TRTCCredentials.SDK_APP_ID,
            userId = userId,
            userSig = TRTCCredentials.userSig(userId),
            roomId = TRTCRoomConfig.RoomID.Text("room_$userId")
        ))
    }

    fun setCapturing(capturing: Boolean) {
        this.capturing = capturing
        if (!isRunning || trtc.roomState != TRTCService.RoomState.IN_ROOM) return
        trtc.muteLocalAudio(!capturing)
    }

    fun stop() {
        if (!isRunning) return
        isRunning = false
        main.removeCallbacks(retry)
        trtc.stopTranscriber()
        trtc.stopLocalAudio()
        trtc.exitRoom()
    }

    private fun startTranscriber() {
        trtc.startTranscriber(TranscriberConfig(source = source, targets = targets.orEmpty(), userIds = listOf(userId)))
    }

    private fun handle(event: TRTCEvent) {
        if (!isRunning) return
        when (event) {
            is TRTCEvent.EnteredRoom -> {
                trtc.startLocalAudio()
                trtc.muteLocalAudio(!capturing)
                startTranscriber()
            }
            is TRTCEvent.EnterRoomFailed -> fail(event.code, "进入房间失败")
            is TRTCEvent.Error -> Log.w(TAG, "TRTC error ${event.code}: ${event.message}")
            is TRTCEvent.Transcript -> {
                val segment = event.segment
                if (segment.speakerUserId.isNotEmpty() && segment.speakerUserId != userId) return
                retries = 0
                onEvent?.invoke(LiveTranscriberEvent.Segment(segment.id, segment.sourceText, segment.translations, segment.isCompleted))
            }
            is TRTCEvent.TranscriberError -> {
                if (event.code in IGNORED_CODES) return
                if (event.code in RETRYABLE_CODES && retries < MAX_RETRIES) {
                    retries += 1
                    main.removeCallbacks(retry)
                    main.postDelayed(retry, 1000L shl retries)
                    return
                }
                fail(event.code, event.message)
            }
            is TRTCEvent.TranscriberStopped -> if (event.reason != 0) fail(event.reason, "转写任务已被服务端结束")
            else -> Unit
        }
    }

    private fun fail(code: Int, message: String) {
        stop()
        onEvent?.invoke(LiveTranscriberEvent.Failed(code, message))
    }

    private companion object {
        const val TAG = "LiveTranscriber"
        val RETRYABLE_CODES = setOf(3000, 5000, -102009, -102005)
        val IGNORED_CODES = setOf(2000, 2002, 4003)
        const val MAX_RETRIES = 3
    }
}
