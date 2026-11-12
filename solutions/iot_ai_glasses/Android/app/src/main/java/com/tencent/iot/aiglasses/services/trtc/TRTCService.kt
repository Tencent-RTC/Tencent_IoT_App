package com.tencent.iot.aiglasses.services.trtc

import android.content.Context
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import com.tencent.iot.aiglasses.models.Language
import com.tencent.liteav.transcriber.AITranscriberManager
import com.tencent.trtc.TRTCCloud
import com.tencent.trtc.TRTCCloudDef
import com.tencent.trtc.TRTCCloudListener
import com.tencent.voiceai.TXRealtimeASR

data class TRTCRoomConfig(
    val sdkAppId: Int,
    val userId: String,
    val userSig: String,
    val roomId: RoomID,
    val role: Int = TRTCCloudDef.TRTCRoleAnchor,
    val scene: Int = TRTCCloudDef.TRTC_APP_SCENE_AUDIOCALL
) {
    sealed interface RoomID {
        data class Numeric(val value: Int) : RoomID
        data class Text(val value: String) : RoomID
    }
}

data class TranscriberConfig(
    val source: String,
    val targets: List<Language>,
    val robotId: String? = null,
    val userIds: List<String> = emptyList()
)

data class TranscriptSegment(
    val id: String,
    val speakerUserId: String,
    val sourceText: String,
    val translations: Map<String, String>,
    val timestamp: Long,
    val isCompleted: Boolean
) {
    fun translation(language: Language): String? = translations[language.trtcCode]
}

sealed interface TRTCEvent {
    data class EnteredRoom(val elapsedMs: Long) : TRTCEvent
    data class EnterRoomFailed(val code: Int) : TRTCEvent
    data class ExitedRoom(val reason: Int) : TRTCEvent
    data class Error(val code: Int, val message: String) : TRTCEvent
    data object ConnectionLost : TRTCEvent
    data object Reconnecting : TRTCEvent
    data object ConnectionRecovered : TRTCEvent
    data class RemoteUserEntered(val userId: String) : TRTCEvent
    data class RemoteUserLeft(val userId: String, val reason: Int) : TRTCEvent
    data class RemoteAudioAvailable(val userId: String, val available: Boolean) : TRTCEvent
    data class TranscriberStarted(val robotId: String) : TRTCEvent
    data class Transcript(val segment: TranscriptSegment) : TRTCEvent
    data class TranscriberStopped(val robotId: String, val reason: Int) : TRTCEvent
    data class TranscriberError(val robotId: String, val code: Int, val message: String) : TRTCEvent
}

class TRTCService private constructor(context: Context) {

    enum class RoomState {
        IDLE,
        ENTERING,
        IN_ROOM,
        EXITING
    }

    var roomState = RoomState.IDLE
        private set
    var isReconnecting = false
        private set
    var isLocalAudioStarted = false
        private set
    var isLocalAudioMuted = false
        private set
    val remoteAudioUsers = mutableSetOf<String>()
    var transcriberRobotId: String? = null
        private set
    var roomId: String? = null
        private set

    private val cloud = TRTCCloud.sharedInstance(context.applicationContext)
    private val main = Handler(Looper.getMainLooper())
    private val observers = mutableListOf<(TRTCEvent) -> Unit>()

    private val cloudListener = object : TRTCCloudListener() {
        override fun onEnterRoom(result: Long) = post(if (result > 0) TRTCEvent.EnteredRoom(result) else TRTCEvent.EnterRoomFailed(result.toInt()))
        override fun onExitRoom(reason: Int) = post(TRTCEvent.ExitedRoom(reason))
        override fun onError(errCode: Int, errMsg: String?, extraInfo: Bundle?) = post(TRTCEvent.Error(errCode, errMsg.orEmpty()))
        override fun onConnectionLost() = post(TRTCEvent.ConnectionLost)
        override fun onTryToReconnect() = post(TRTCEvent.Reconnecting)
        override fun onConnectionRecovery() = post(TRTCEvent.ConnectionRecovered)
        override fun onRemoteUserEnterRoom(userId: String) = post(TRTCEvent.RemoteUserEntered(userId))
        override fun onRemoteUserLeaveRoom(userId: String, reason: Int) = post(TRTCEvent.RemoteUserLeft(userId, reason))
        override fun onUserAudioAvailable(userId: String, available: Boolean) = post(TRTCEvent.RemoteAudioAvailable(userId, available))
    }

    private val transcriberListener = object : AITranscriberManager.AITranscriberListener {
        override fun onRealtimeTranscriberStarted(roomId: String?, transcriberRobotId: String?) =
            post(TRTCEvent.TranscriberStarted(transcriberRobotId.orEmpty()))

        override fun onReceiveTranscriberMessage(roomId: String?, message: AITranscriberManager.TranscriberMessage) =
            post(TRTCEvent.Transcript(TranscriptSegment(
                id = message.segmentId.orEmpty(),
                speakerUserId = message.speakerUserId.orEmpty(),
                sourceText = message.sourceText.orEmpty(),
                translations = message.translationTexts?.toMap().orEmpty(),
                timestamp = message.timestamp,
                isCompleted = message.isCompleted
            )))

        override fun onRealtimeTranscriberStopped(roomId: String?, transcriberRobotId: String?, reason: Int) =
            post(TRTCEvent.TranscriberStopped(transcriberRobotId.orEmpty(), reason))

        override fun onRealtimeTranscriberError(roomId: String?, transcriberRobotId: String?, error: Int, errorInfo: String?) =
            post(TRTCEvent.TranscriberError(transcriberRobotId.orEmpty(), error, errorInfo.orEmpty()))
    }

    init {
        cloud.addListener(cloudListener)
        cloud.aiTranscriberManager.addListener(transcriberListener)
    }

    fun addObserver(observer: (TRTCEvent) -> Unit): () -> Unit {
        observers += observer
        return { observers -= observer }
    }

    fun enterRoom(config: TRTCRoomConfig) {
        if (roomState != RoomState.IDLE) return
        val params = TRTCCloudDef.TRTCParams().apply {
            sdkAppId = config.sdkAppId
            userId = config.userId
            userSig = config.userSig
            role = config.role
        }
        when (val id = config.roomId) {
            is TRTCRoomConfig.RoomID.Numeric -> {
                params.roomId = id.value
                roomId = id.value.toString()
            }
            is TRTCRoomConfig.RoomID.Text -> {
                params.strRoomId = id.value
                roomId = id.value
            }
        }
        roomState = RoomState.ENTERING
        cloud.enterRoom(params, config.scene)
    }

    fun exitRoom() {
        if (roomState != RoomState.ENTERING && roomState != RoomState.IN_ROOM) return
        roomState = RoomState.EXITING
        cloud.exitRoom()
    }

    fun startLocalAudio(quality: Int = TRTCCloudDef.TRTC_AUDIO_QUALITY_SPEECH) {
        if (isLocalAudioStarted) return
        cloud.startLocalAudio(quality)
        isLocalAudioStarted = true
    }

    fun stopLocalAudio() {
        cloud.stopLocalAudio()
        isLocalAudioStarted = false
    }

    fun muteLocalAudio(mute: Boolean) {
        cloud.muteLocalAudio(mute)
        isLocalAudioMuted = mute
    }

    fun startTranscriber(config: TranscriberConfig) {
        val params = AITranscriberManager.TranscriberParams().apply {
            config.robotId?.let { transcriberRobotId = it }
            sourceLanguage = config.source
            translationLanguages = config.targets.map { it.trtcCode }
            userIdsToTranscribe = config.userIds
        }
        cloud.aiTranscriberManager.startRealtimeTranscriber(params)
    }

    fun stopTranscriber() {
        cloud.aiTranscriberManager.stopRealtimeTranscriber(transcriberRobotId.orEmpty())
    }

    private fun post(event: TRTCEvent) {
        main.post { handle(event) }
    }

    private fun handle(event: TRTCEvent) {
        when (event) {
            is TRTCEvent.EnteredRoom -> roomState = RoomState.IN_ROOM
            is TRTCEvent.EnterRoomFailed, is TRTCEvent.ExitedRoom -> resetRoomState()
            TRTCEvent.ConnectionLost, TRTCEvent.Reconnecting -> isReconnecting = true
            TRTCEvent.ConnectionRecovered -> isReconnecting = false
            is TRTCEvent.RemoteAudioAvailable -> if (event.available) remoteAudioUsers += event.userId else remoteAudioUsers -= event.userId
            is TRTCEvent.RemoteUserLeft -> remoteAudioUsers -= event.userId
            is TRTCEvent.TranscriberStarted -> transcriberRobotId = event.robotId
            is TRTCEvent.TranscriberStopped -> transcriberRobotId = null
            else -> Unit
        }
        observers.toList().forEach { it(event) }
    }

    private fun resetRoomState() {
        roomState = RoomState.IDLE
        roomId = null
        isReconnecting = false
        isLocalAudioStarted = false
        isLocalAudioMuted = false
        remoteAudioUsers.clear()
        transcriberRobotId = null
    }

    companion object {
        @Volatile
        private var instance: TRTCService? = null

        fun shared(context: Context): TRTCService =
            instance ?: synchronized(this) { instance ?: TRTCService(context).also { instance = it } }
    }
}

val Language.trtcCode: String
    get() = when (this) {
        Language.ENGLISH -> "en"
        Language.CHINESE -> "zh"
    }
