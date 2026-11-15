package com.tencent.iot.watchapp.call

import android.os.Handler
import android.os.Looper
import java.security.SecureRandom

enum class CallSignalPhase { IDLE, OUTGOING, INCOMING, ACTIVE }

data class CallSignalState(
    val phase: CallSignalPhase = CallSignalPhase.IDLE,
    val sessionId: Long = 0,
    val peerId: String = "",
    val mediaType: CallMediaType = CallMediaType.VIDEO,
    val reason: String? = null,
)

/** 协议 v1 的四态 Call Engine；UI 和媒体层都通过它间接使用 IMSDK 信令。 */
class CallSignaling(
    private val transport: CallSignalTransport,
    private val onStateChange: (CallSignalState) -> Unit,
) {
    private val handler = Handler(Looper.getMainLooper())
    private val random = SecureRandom()
    private var state = CallSignalState()
    private var epoch = 0L
    private var timeout: Runnable? = null

    fun currentState(): CallSignalState = state

    fun startOutgoing(target: CallTarget, mediaType: CallMediaType): Boolean {
        val peerId = target.signalUserId
        if (state.phase != CallSignalPhase.IDLE || peerId.isBlank() || transport.localUserId.isBlank()) return false
        val sessionId = nextSessionId()
        val newState = CallSignalState(CallSignalPhase.OUTGOING, sessionId, peerId, mediaType)
        update(newState)
        scheduleTimeout(sessionId, epoch, 35_000L) { sendHangupIfCurrent("timeout") }
        val signal = CallSignal(
            type = CallSignalType.CALL,
            sessionId = sessionId,
            to = peerId,
            mediaCode = mediaType.toSignalCode(),
            videoQuality = if (mediaType == CallMediaType.VIDEO) CallSignalCodec.VIDEO_QUALITY_HIGH else 0,
            deviceCode = target.deviceName.takeIf { it.isNotBlank() },
        )
        transport.send(peerId, signal) { result ->
            if (result.isFailure && matches(sessionId, CallSignalPhase.OUTGOING)) finish("send_failed")
        }
        return true
    }

    fun acceptIncoming(): Boolean {
        val current = state
        if (current.phase != CallSignalPhase.INCOMING) return false
        val signal = CallSignal(CallSignalType.ACCEPT, current.sessionId, current.peerId)
        transport.send(current.peerId, signal) { result ->
            if (result.isSuccess && matches(current.sessionId, CallSignalPhase.INCOMING)) update(current.copy(phase = CallSignalPhase.ACTIVE))
        }
        return true
    }

    fun rejectIncoming(reason: String = "decline"): Boolean {
        val current = state
        if (current.phase != CallSignalPhase.INCOMING) return false
        transport.send(current.peerId, CallSignal(CallSignalType.REJECT, current.sessionId, current.peerId, reason = reason)) { }
        finish(reason)
        return true
    }

    fun hangup(): Boolean {
        val current = state
        if (current.phase == CallSignalPhase.IDLE) return false
        if (current.phase == CallSignalPhase.INCOMING) return rejectIncoming("decline")
        sendHangupIfCurrent(if (current.phase == CallSignalPhase.OUTGOING) "cancel" else "hangup")
        return true
    }

    fun receive(senderId: String, signal: CallSignal) {
        if (senderId.isBlank() || signal.to != transport.localUserId) return
        when (signal.type) {
            CallSignalType.CALL -> receiveCall(senderId, signal)
            CallSignalType.ACCEPT -> if (matches(signal.sessionId, CallSignalPhase.OUTGOING, senderId)) {
                cancelTimeout()
                update(state.copy(phase = CallSignalPhase.ACTIVE))
            }
            CallSignalType.REJECT -> if (matches(signal.sessionId, CallSignalPhase.OUTGOING, senderId)) finish(signal.reason ?: "reject")
            CallSignalType.HANGUP -> if (matches(signal.sessionId, CallSignalPhase.OUTGOING, senderId) || matches(signal.sessionId, CallSignalPhase.INCOMING, senderId) || matches(signal.sessionId, CallSignalPhase.ACTIVE, senderId)) finish(signal.reason ?: "hangup")
        }
    }

    fun onTransportUnavailable() {
        if (state.phase == CallSignalPhase.OUTGOING || state.phase == CallSignalPhase.INCOMING) finish("im_unavailable")
    }

    fun markMediaActive() {
        if (state.phase == CallSignalPhase.OUTGOING || state.phase == CallSignalPhase.INCOMING) {
            cancelTimeout()
            update(state.copy(phase = CallSignalPhase.ACTIVE))
        }
    }

    fun markMediaEnded(reason: String = "media_end") {
        if (state.phase != CallSignalPhase.IDLE) finish(reason)
    }

    private fun receiveCall(senderId: String, signal: CallSignal) {
        if (state.phase != CallSignalPhase.IDLE) {
            transport.send(senderId, CallSignal(CallSignalType.REJECT, signal.sessionId, senderId, reason = "busy")) { }
            return
        }
        val mediaType = signal.mediaCode.toMediaType() ?: return
        update(CallSignalState(CallSignalPhase.INCOMING, signal.sessionId, senderId, mediaType))
        scheduleTimeout(signal.sessionId, epoch, 40_000L) { if (matches(signal.sessionId, CallSignalPhase.INCOMING)) rejectIncoming("decline") }
    }

    private fun sendHangupIfCurrent(reason: String) {
        val current = state
        if (current.phase == CallSignalPhase.IDLE) return
        transport.send(current.peerId, CallSignal(CallSignalType.HANGUP, current.sessionId, current.peerId, reason = reason)) { }
        finish(reason)
    }

    private fun finish(reason: String) {
        cancelTimeout()
        update(CallSignalState(reason = reason))
    }

    private fun update(newState: CallSignalState) {
        state = newState
        epoch += 1
        onStateChange(newState)
    }

    private fun matches(sessionId: Long, phase: CallSignalPhase, peerId: String? = null) =
        state.sessionId == sessionId && state.phase == phase && (peerId == null || state.peerId == peerId)

    private fun scheduleTimeout(sessionId: Long, expectedEpoch: Long, delay: Long, action: () -> Unit) {
        cancelTimeout()
        val task = Runnable { if (state.sessionId == sessionId && epoch == expectedEpoch + 1) action() }
        timeout = task
        handler.postDelayed(task, delay)
    }

    private fun cancelTimeout() {
        timeout?.let(handler::removeCallbacks)
        timeout = null
    }

    private fun nextSessionId(): Long = random.nextInt().toLong() and 0xFFFF_FFFFL
        .let { if (it == 0L) 1L else it }
}

private fun CallMediaType.toSignalCode() = if (this == CallMediaType.VIDEO) CallSignalCodec.AUDIO_VIDEO_MEDIA_CODE else CallSignalCodec.AUDIO_ONLY_MEDIA_CODE

private fun Int?.toMediaType(): CallMediaType? = when (this) {
    CallSignalCodec.AUDIO_VIDEO_MEDIA_CODE -> CallMediaType.VIDEO
    CallSignalCodec.AUDIO_ONLY_MEDIA_CODE -> CallMediaType.AUDIO
    else -> null
}
