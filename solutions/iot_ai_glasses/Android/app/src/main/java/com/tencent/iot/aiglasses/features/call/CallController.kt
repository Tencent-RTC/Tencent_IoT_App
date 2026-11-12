package com.tencent.iot.aiglasses.features.call

import android.content.Context
import android.util.Log
import com.tencent.iot.aiglasses.services.trtc.TRTCCredentials
import com.tencent.iot.aiglasses.services.trtc.TRTCEvent
import com.tencent.iot.aiglasses.services.trtc.TRTCRoomConfig
import com.tencent.iot.aiglasses.services.trtc.TRTCService

class CallController(context: Context, private val trtc: TRTCService = TRTCService.shared(context)) {

    enum class Phase {
        IDLE,
        JOINING,
        IN_CALL
    }

    var phase = Phase.IDLE
        private set
    var roomId = ""
        private set
    var userId = ""
        private set
    val remoteUsers = mutableListOf<String>()
    var isMuted = false
        private set
    var isReconnecting = false
        private set

    var onChange: (() -> Unit)? = null
    var onEnded: ((String) -> Unit)? = null

    private var glassesConnected = true

    val isRunning: Boolean
        get() = phase != Phase.IDLE

    init {
        trtc.addObserver(::handle)
    }

    fun start(roomId: String, userId: String, glassesConnected: Boolean) {
        if (phase != Phase.IDLE) return
        this.roomId = roomId
        this.userId = userId
        this.glassesConnected = glassesConnected
        remoteUsers.clear()
        isMuted = false
        isReconnecting = false
        phase = Phase.JOINING
        trtc.enterRoom(TRTCRoomConfig(
            sdkAppId = TRTCCredentials.SDK_APP_ID,
            userId = userId,
            userSig = TRTCCredentials.userSig(userId),
            roomId = roomID(roomId)
        ))
        onChange?.invoke()
    }

    fun stop() {
        if (phase == Phase.IDLE) return
        phase = Phase.IDLE
        remoteUsers.clear()
        isReconnecting = false
        trtc.stopLocalAudio()
        trtc.exitRoom()
        onChange?.invoke()
    }

    fun toggleMute() {
        isMuted = !isMuted
        applyMute()
        onChange?.invoke()
    }

    fun setGlassesConnected(connected: Boolean) {
        glassesConnected = connected
        applyMute()
    }

    private fun applyMute() {
        if (phase != Phase.IN_CALL) return
        trtc.muteLocalAudio(isMuted || !glassesConnected)
    }

    private fun handle(event: TRTCEvent) {
        if (phase == Phase.IDLE) return
        when (event) {
            is TRTCEvent.EnteredRoom -> {
                phase = Phase.IN_CALL
                trtc.startLocalAudio()
                applyMute()
            }
            is TRTCEvent.EnterRoomFailed -> return end("进入房间失败（${event.code}）")
            is TRTCEvent.ExitedRoom -> return end(if (event.reason == 0) "通话已结束" else "已被移出房间（${event.reason}）")
            is TRTCEvent.Error -> Log.w(TAG, "TRTC error ${event.code}: ${event.message}")
            TRTCEvent.ConnectionLost, TRTCEvent.Reconnecting -> isReconnecting = true
            TRTCEvent.ConnectionRecovered -> isReconnecting = false
            is TRTCEvent.RemoteUserEntered -> if (event.userId !in remoteUsers) remoteUsers += event.userId
            is TRTCEvent.RemoteUserLeft -> remoteUsers -= event.userId
            else -> return
        }
        onChange?.invoke()
    }

    private fun end(message: String) {
        stop()
        onEnded?.invoke(message)
    }

    private companion object {
        const val TAG = "Call"

        fun roomID(text: String): TRTCRoomConfig.RoomID {
            val number = text.toIntOrNull()
            return if (number != null && number > 0) TRTCRoomConfig.RoomID.Numeric(number) else TRTCRoomConfig.RoomID.Text(text)
        }
    }
}
