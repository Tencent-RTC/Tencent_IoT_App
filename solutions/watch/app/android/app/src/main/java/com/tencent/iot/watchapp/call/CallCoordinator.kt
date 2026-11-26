package com.tencent.iot.watchapp.call

import android.content.Context
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

class CallCoordinator(
    context: Context,
    owner: LifecycleOwner,
    private val signalTransport: CallSignalTransport,
) {
    private val scope = owner.lifecycleScope
    private val store = CallStateStore()
    private val engine = IoTSession(context, scope)
    private val call = CallMediaSession(context, { engineCallSession() }, ::handleEvent)
    private var microphoneRequested = false
    private var frontCamera = true
    private val signaling = CallSignaling(
        transport = signalTransport,
        onStateChange = ::handleSignalState,
    )

    val loginState: StateFlow<IoTLoginState> = engine.loginState
    val callState: StateFlow<CallUiState> = store.state

    init {
        scope.launch {
            engine.loginState.collect { state ->
                if (state is IoTLoginState.LoggedIn) call.attach()
            }
        }
        scope.launch {
            signalTransport.incomingSignals.collect { incoming ->
                signaling.receive(incoming.senderId, incoming.signal)
            }
        }
        scope.launch {
            signalTransport.transportAvailable.collect { available ->
                if (!available) signaling.onTransportUnavailable()
            }
        }
    }

    fun login(channel: String, appId: String, appSecret: String) {
        scope.launch {
            engine.login(IotSessionConfig(channel.trim(), appId.trim(), appSecret))
        }
    }

    fun startCall(target: CallTarget, targetName: String, avatarId: String, mediaType: CallMediaType): Boolean {
        microphoneRequested = false
        frontCamera = true
        store.startOutgoing(target, targetName, avatarId, mediaType)
        if (!signaling.startOutgoing(target, mediaType)) {
            store.finish(CallEndReason.UNKNOWN)
            return false
        }
        if (loginState.value !is IoTLoginState.LoggedIn) return true
        if (!call.callDevice(target, mediaType)) {
            signaling.markMediaEnded("media_start_failed")
            store.finish(CallEndReason.UNKNOWN)
            return false
        }
        return true
    }

    fun bindRemote(surface: CallVideoSurface) { surface.bindRemote(call) }
    fun startLocalVideo(surface: CallVideoSurface) {
        if (callState.value.mediaType == CallMediaType.VIDEO) surface.startLocalVideo(call, frontCamera)
    }
    fun setMicrophoneEnabled(enabled: Boolean) {
        if (enabled) call.openMicrophone() else call.closeMicrophone()
    }
    fun setSpeakerphoneEnabled(enabled: Boolean) { call.selectSpeakerphone(enabled) }
    fun setCameraEnabled(enabled: Boolean, surface: CallVideoSurface) = surface.setCameraEnabled(call, enabled, frontCamera)
    fun switchCamera() {
        frontCamera = !frontCamera
        call.switchCamera(frontCamera)
    }
    fun hangup() { signaling.hangup(); call.hangup(); store.finish(CallEndReason.LOCAL_HANGUP) }
    fun acceptIncoming(): Boolean {
        val target = callState.value.target ?: return false
        if (loginState.value is IoTLoginState.LoggedIn && !call.prepareIncomingCall(target)) return false
        return signaling.acceptIncoming()
    }
    fun rejectIncoming(): Boolean { return signaling.rejectIncoming().also { if (it) store.finish(CallEndReason.LOCAL_HANGUP) } }

    fun logout() {
        signaling.onTransportUnavailable()
        call.hangup()
        store.finish(CallEndReason.LOCAL_HANGUP)
        engine.logout()
    }

    fun release() { call.detach(); engine.release() }

    private fun handleEvent(event: CallEvent) {
        when (event) {
            is CallEvent.Begin -> {
                signaling.markMediaActive()
                store.active(event.mediaType)
                requestMicrophoneIfActive()
            }
            is CallEvent.End -> {
                signaling.markMediaEnded("media_end")
                store.finish(event.reason)
            }
            CallEvent.Rejected, CallEvent.NoResponse, CallEvent.LineBusy,
            is CallEvent.UserOffline, is CallEvent.Error,
            is CallEvent.Incoming, is CallEvent.Cancelled -> Unit
            is CallEvent.RemoteAudioAvailable -> {
                if (event.available && callState.value.phase in setOf(CallPhase.OUTGOING, CallPhase.ACTIVE)) {
                    signaling.markMediaActive()
                    store.active(callState.value.mediaType)
                    requestMicrophoneIfActive()
                }
            }
            is CallEvent.RemoteVideoAvailable -> {
                if (event.available && callState.value.phase in setOf(CallPhase.OUTGOING, CallPhase.ACTIVE)) {
                    signaling.markMediaActive()
                    store.active(callState.value.mediaType)
                    requestMicrophoneIfActive()
                }
                store.remoteVideoAvailable(event.available)
            }
        }
    }

    private fun handleSignalState(state: CallSignalState) {
        when (state.phase) {
            CallSignalPhase.OUTGOING -> Unit
            CallSignalPhase.INCOMING -> {
                microphoneRequested = false
                store.incoming(CallUser("", state.peerId), state.mediaType)
            }
            CallSignalPhase.ACTIVE -> {
                store.active(state.mediaType)
                requestMicrophoneIfActive()
            }
            CallSignalPhase.IDLE -> {
                microphoneRequested = false
                if (callState.value.phase != CallPhase.IDLE) store.finish(CallEndReason.REMOTE_HANGUP)
            }
        }
    }

    private fun requestMicrophoneIfActive() {
        if (!shouldRequestMicrophone(callState.value.phase, microphoneRequested)) return
        microphoneRequested = true
        call.openMicrophone()
    }

    private fun engineCallSession() = engine.callSession()
}

internal fun shouldRequestMicrophone(phase: CallPhase, microphoneRequested: Boolean): Boolean =
    !microphoneRequested && (phase == CallPhase.OUTGOING || phase == CallPhase.ACTIVE)
