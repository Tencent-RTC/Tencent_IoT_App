package com.tencent.iot.watchapp

import com.tencent.iot.watchapp.call.*

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CallStatePolicyTest {
    @Test
    fun activePhaseStillRequestsMicrophoneAfterAccept() {
        assertTrue(shouldRequestMicrophone(CallPhase.ACTIVE, microphoneRequested = false))
    }

    @Test
    fun outgoingPhaseRequestsMicrophoneBeforeAccept() {
        assertTrue(shouldRequestMicrophone(CallPhase.OUTGOING, microphoneRequested = false))
    }

    @Test
    fun incomingPhaseAndRepeatedRequestAreIgnored() {
        assertFalse(shouldRequestMicrophone(CallPhase.INCOMING, microphoneRequested = false))
        assertFalse(shouldRequestMicrophone(CallPhase.ACTIVE, microphoneRequested = true))
    }
}
