package com.tencent.iot.watchapp.call

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

enum class CallPhase { IDLE, OUTGOING, INCOMING, ACTIVE }

data class CallUiState(
    val phase: CallPhase = CallPhase.IDLE,
    val sessionId: Long = 0,
    val target: CallTarget? = null,
    val targetName: String = "",
    val avatarId: String = "",
    val mediaType: CallMediaType = CallMediaType.VIDEO,
    val remoteVideoAvailable: Boolean = false,
    val result: CallEndReason? = null,
)

class CallStateStore {
    private val mutableState = MutableStateFlow(CallUiState())
    val state: StateFlow<CallUiState> = mutableState.asStateFlow()

    fun startOutgoing(target: CallTarget, targetName: String, avatarId: String, mediaType: CallMediaType) {
        mutableState.value = CallUiState(
            phase = CallPhase.OUTGOING,
            sessionId = mutableState.value.sessionId + 1,
            target = target,
            targetName = targetName,
            avatarId = avatarId,
            mediaType = mediaType,
        )
    }

    fun incoming(user: CallUser, mediaType: CallMediaType) {
        if (mutableState.value.phase != CallPhase.IDLE) return
        mutableState.value = mutableState.value.copy(
            phase = CallPhase.INCOMING,
            sessionId = mutableState.value.sessionId + 1,
            target = CallTarget(user.productId, user.deviceName),
            targetName = user.deviceName,
            avatarId = user.deviceName,
            mediaType = mediaType,
        )
    }

    fun active(mediaType: CallMediaType) {
        val current = mutableState.value
        if (current.phase !in setOf(CallPhase.OUTGOING, CallPhase.INCOMING)) return
        mutableState.value = current.copy(phase = CallPhase.ACTIVE, mediaType = mediaType)
    }

    fun remoteVideoAvailable(available: Boolean) {
        if (mutableState.value.phase == CallPhase.ACTIVE) mutableState.value = mutableState.value.copy(remoteVideoAvailable = available)
    }

    fun finish(reason: CallEndReason? = null) {
        mutableState.value = CallUiState(sessionId = mutableState.value.sessionId, result = reason)
    }

    fun reset() { mutableState.value = CallUiState(sessionId = mutableState.value.sessionId) }
}
