package com.tencent.iot.watchapp.call
import com.tencent.iot.watchapp.config.WatchLogger

import android.content.Context
import com.tencent.liteav.iot.TXIoTCallSession
import com.tencent.liteav.iot.TXIoTEngineDef
import com.tencent.rtmp.ui.TXCloudVideoView
import com.tencent.trtc.TRTCCloud
import com.tencent.trtc.TRTCCloudDef

data class CallTarget(val productId: String, val deviceName: String) {
    val hasIdentifier: Boolean get() = productId.isNotBlank() || deviceName.isNotBlank()
    val signalUserId: String get() = deviceName
}

data class CallUser(val productId: String, val deviceName: String) {
    val displayName: String get() = deviceName.ifBlank { productId }
}

enum class CallMediaType { AUDIO, VIDEO }
enum class CallEndReason { LOCAL_HANGUP, REMOTE_HANGUP, PERMISSION_DENIED, NETWORK_ERROR, UNKNOWN }

sealed interface CallEvent {
    data class Incoming(val user: CallUser, val mediaType: CallMediaType) : CallEvent
    data class Cancelled(val user: CallUser) : CallEvent
    data class Begin(val mediaType: CallMediaType) : CallEvent
    data class End(val reason: CallEndReason) : CallEvent
    object Rejected : CallEvent
    object NoResponse : CallEvent
    object LineBusy : CallEvent
    data class UserOffline(val user: CallUser) : CallEvent
    data class RemoteAudioAvailable(val user: CallUser, val available: Boolean) : CallEvent
    data class RemoteVideoAvailable(val user: CallUser, val available: Boolean) : CallEvent
    data class Error(val code: String, val message: String) : CallEvent
}

class CallMediaSession(
    private val context: Context,
    private val sessionProvider: () -> TXIoTCallSession?,
    private val onEvent: (CallEvent) -> Unit,
) {
    private var listenerAttached = false
    private var remoteUser: TXIoTCallSession.TXIoTCallUser? = null
    private var pendingRemoteView: TXCloudVideoView? = null

    private val listener = object : TXIoTCallSession.TXIoTCallListener {
        override fun onError(code: TXIoTEngineDef.TXIoTErrorCode?, message: String?) {
            onEvent(CallEvent.Error(code?.name ?: "ERR_FAILED", message.orEmpty()))
        }

        override fun onCallBegin(mediaType: TXIoTCallSession.TXIoTCallMediaType?) {
            onEvent(CallEvent.Begin(mediaType.toMediaType()))
        }

        override fun onCallEnd(
            mediaType: TXIoTCallSession.TXIoTCallMediaType?,
            reason: TXIoTCallSession.TXIoTCallEndReason?,
        ) {
            onEvent(CallEvent.End(reason.toEndReason()))
            clearRemote()
        }

        override fun onCallRejected(user: TXIoTCallSession.TXIoTCallUser?) = onEvent(CallEvent.Rejected)
        override fun onCallNoResponse(user: TXIoTCallSession.TXIoTCallUser?) = onEvent(CallEvent.NoResponse)
        override fun onCallLineBusy(user: TXIoTCallSession.TXIoTCallUser?) = onEvent(CallEvent.LineBusy)
        override fun onCallUserOffline(user: TXIoTCallSession.TXIoTCallUser?) {
            onEvent(CallEvent.UserOffline(user.toRoomUser()))
        }

        override fun onCallUserAudioAvailable(user: TXIoTCallSession.TXIoTCallUser?, available: Boolean) {
            rememberRemote(user)
            onEvent(CallEvent.RemoteAudioAvailable(user.toRoomUser(), available))
        }

        override fun onCallUserVideoAvailable(user: TXIoTCallSession.TXIoTCallUser?, available: Boolean) {
            rememberRemote(user)
            onEvent(CallEvent.RemoteVideoAvailable(user.toRoomUser(), available))
        }

        override fun onCallNetworkQualityChanged(
            local: TXIoTCallSession.TXIoTQuality?,
            remote: MutableList<TXIoTCallSession.TXIoTQuality>?,
        ) = Unit

    }

    fun attach(): Boolean {
        val session = sessionProvider() ?: return false
        if (!listenerAttached) {
            session.addListener(listener)
            listenerAttached = true
        }
        return true
    }

    fun detach() {
        if (listenerAttached) sessionProvider()?.removeListener(listener)
        listenerAttached = false
        clearRemote()
    }

    fun callDevice(target: CallTarget, mediaType: CallMediaType): Boolean {
        val session = sessionProvider() ?: return false
        if (!attach()) return false
        val deviceId = TXIoTEngineDef.TXIoTDeviceId().apply {
            productId = target.productId
            deviceName = target.deviceName
        }
        if (remoteUser == null) {
            remoteUser = TXIoTCallSession.TXIoTCallUser().apply { this.deviceId = deviceId }
        }
        session.callDevice(deviceId, mediaType.toSdkType())
        pendingRemoteView?.let(::bindRemote)
        return true
    }

    fun bindRemoteView(view: TXCloudVideoView) {
        pendingRemoteView = view
        bindRemote(view)
    }

    fun hangup() {
        sessionProvider()?.hangup()
        closeMedia()
    }

    /** 新版 AAR 不再提供 IoT 层 acceptCall；来电确认由 IMSDK 信令完成，这里只准备媒体用户和监听器。 */
    fun prepareIncomingCall(target: CallTarget): Boolean {
        if (!attach()) return false
        val user = target.toCallUser() ?: return false
        remoteUser = user
        return true
    }

    fun openMicrophone() { sessionProvider()?.openMicrophone() }
    fun closeMicrophone() { sessionProvider()?.closeMicrophone() }
    fun openCamera(view: TXCloudVideoView, front: Boolean = true) {
        configureVideoEncoder()
        sessionProvider()?.openCamera(if (front) TXIoTCallSession.TXIoTCamera.FRONT else TXIoTCallSession.TXIoTCamera.BACK, view)
    }
    fun closeCamera() { sessionProvider()?.closeCamera() }
    fun switchCamera(front: Boolean) { sessionProvider()?.switchCamera(if (front) TXIoTCallSession.TXIoTCamera.FRONT else TXIoTCallSession.TXIoTCamera.BACK) }
    fun selectSpeakerphone(enabled: Boolean) {
        sessionProvider()?.selectAudioPlaybackDevice(
            if (enabled) TXIoTCallSession.TXIoTAudioPlaybackDevice.SPEAKER_PHONE
            else TXIoTCallSession.TXIoTAudioPlaybackDevice.EAR_PIECE,
        )
    }

    private fun bindRemote(view: TXCloudVideoView) {
        val session = sessionProvider() ?: return
        remoteUser?.let {
            session.startRemoteView(it, view)
            configureRemoteRender(it)
        }
    }

    private fun configureRemoteRender(user: TXIoTCallSession.TXIoTCallUser) {
        val userId = user.deviceId?.deviceName?.takeIf { it.isNotBlank() } ?: return
        val params = TRTCCloudDef.TRTCRenderParams().apply {
            fillMode = TRTCCloudDef.TRTC_VIDEO_RENDER_MODE_FIT
        }
        TRTCCloud.sharedInstance(context.applicationContext).setRemoteRenderParams(
            userId,
            TRTCCloudDef.TRTC_VIDEO_STREAM_TYPE_BIG,
            params,
        )
        WatchLogger.i("IoT remote video render configured: fit")
    }

    private fun rememberRemote(user: TXIoTCallSession.TXIoTCallUser?) {
        if (user == null) return
        remoteUser = user
        pendingRemoteView?.let(::bindRemote)
    }

    private fun clearRemote() {
        val session = sessionProvider()
        remoteUser?.let { session?.stopRemoteView(it) }
        closeMedia()
        remoteUser = null
        pendingRemoteView = null
    }

    private fun closeMedia() {
        sessionProvider()?.closeCamera()
        sessionProvider()?.closeMicrophone()
    }

    /**
     * TXIoTCallSession 没有独立的视频编码参数接口；它与当前 IoT SDK 共用 TRTC 主路编码器。
     * 640x360 + PORTRAIT 的实际编码方向为 360x640。
     */
    private fun configureVideoEncoder() {
        val params = TRTCCloudDef.TRTCVideoEncParam().apply {
            videoResolution = TRTCCloudDef.TRTC_VIDEO_RESOLUTION_640_360
            videoResolutionMode = TRTCCloudDef.TRTC_VIDEO_RESOLUTION_MODE_PORTRAIT
            videoFps = 15
            videoBitrate = 500
            minVideoBitrate = 0
            enableAdjustRes = false
        }
        TRTCCloud.sharedInstance(context.applicationContext).setVideoEncoderParam(params)
        WatchLogger.i("IoT video encoder configured: 360x640, fps=15, bitrate=500kbps")
    }
}

private fun CallTarget.toCallUser(): TXIoTCallSession.TXIoTCallUser? {
    if (!hasIdentifier) return null
    val id = TXIoTEngineDef.TXIoTDeviceId().apply {
        productId = productId
        deviceName = deviceName
    }
    return TXIoTCallSession.TXIoTCallUser().apply { deviceId = id }
}

private fun TXIoTCallSession.TXIoTCallUser?.toRoomUser(): CallUser = CallUser(
    productId = this?.deviceId?.productId.orEmpty(),
    deviceName = this?.deviceId?.deviceName.orEmpty(),
)

private fun TXIoTCallSession.TXIoTCallMediaType?.toMediaType() =
    if (this == TXIoTCallSession.TXIoTCallMediaType.AUDIO) CallMediaType.AUDIO else CallMediaType.VIDEO

private fun CallMediaType.toSdkType() =
    if (this == CallMediaType.AUDIO) TXIoTCallSession.TXIoTCallMediaType.AUDIO else TXIoTCallSession.TXIoTCallMediaType.VIDEO

private fun TXIoTCallSession.TXIoTCallEndReason?.toEndReason() = when (this) {
    TXIoTCallSession.TXIoTCallEndReason.LOCAL_HANGUP -> CallEndReason.LOCAL_HANGUP
    TXIoTCallSession.TXIoTCallEndReason.REMOTE_HANGUP -> CallEndReason.REMOTE_HANGUP
    TXIoTCallSession.TXIoTCallEndReason.CALL_PERMISSION_DENIED -> CallEndReason.PERMISSION_DENIED
    TXIoTCallSession.TXIoTCallEndReason.NETWORK_ERROR -> CallEndReason.NETWORK_ERROR
    else -> CallEndReason.UNKNOWN
}
