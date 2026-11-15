package com.tencent.iot.watchapp

import com.tencent.iot.watchapp.call.*

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CallStateStoreTest {
    @Test
    fun outgoingStateKeepsSemanticAvatarIdAndSessionId() {
        val store = CallStateStore()
        val target = CallTarget(productId = "PRODUCT_A", deviceName = "watch-01")

        store.startOutgoing(target, "小雅", avatarId = "watch-01", mediaType = CallMediaType.VIDEO)
        val state = store.state.value

        assertEquals(CallPhase.OUTGOING, state.phase)
        assertEquals("watch-01", state.avatarId)
        assertEquals(1L, state.sessionId)
        assertEquals(target, state.target)
    }

    @Test
    fun incomingStateIsIgnoredWhenAnotherCallIsActive() {
        val store = CallStateStore()
        store.startOutgoing(CallTarget("PRODUCT_A", "watch-01"), "小雅", "watch-01", CallMediaType.AUDIO)
        val before = store.state.value

        store.incoming(CallUser("PRODUCT_B", "watch-02"), CallMediaType.VIDEO)

        assertEquals(before, store.state.value)
        assertFalse(store.state.value.phase == CallPhase.INCOMING)
    }

    @Test
    fun finishKeepsSessionIdAndPublishesResult() {
        val store = CallStateStore()
        store.startOutgoing(CallTarget("PRODUCT_A", "watch-01"), "小雅", "watch-01", CallMediaType.AUDIO)

        store.finish(CallEndReason.REMOTE_HANGUP)
        val state = store.state.value

        assertEquals(CallPhase.IDLE, state.phase)
        assertEquals(CallEndReason.REMOTE_HANGUP, state.result)
        assertTrue(state.sessionId > 0)
    }
}
