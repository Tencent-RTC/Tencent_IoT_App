package com.tencent.iot.watchapp

import com.tencent.iot.watchapp.call.*

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CallSignalCodecTest {
    @Test
    fun encodeAndDecodeCallKeepsProtocolFields() {
        val original = CallSignal(
            type = CallSignalType.CALL,
            sessionId = 4_294_967_295L,
            to = "watch_user",
            mediaCode = CallSignalCodec.AUDIO_VIDEO_MEDIA_CODE,
            videoQuality = CallSignalCodec.VIDEO_QUALITY_HIGH,
            deviceCode = "xiaoya",
        )

        assertEquals(original, CallSignalCodec.decode(CallSignalCodec.encode(original)))
    }

    @Test
    fun decodeRejectsNestedPayloadAndNonIntegerSessionId() {
        assertNull(CallSignalCodec.decode("{\"v\":1,\"t\":\"call\",\"sid\":{\"x\":1},\"to\":\"watch\"}"))
        assertNull(CallSignalCodec.decode("{\"v\":1,\"t\":\"call\",\"sid\":1.5,\"to\":\"watch\"}"))
    }

    @Test

    fun deviceCodeIsTruncatedByUtf8Bytes() {
        val encoded = CallSignalCodec.encode(
            CallSignal(
                type = CallSignalType.CALL,
                sessionId = 1,
                to = "watch",
                mediaCode = CallSignalCodec.AUDIO_ONLY_MEDIA_CODE,
                videoQuality = 0,
                deviceCode = "手表".repeat(100),
            ),
        )
        val decoded = CallSignalCodec.decode(encoded)

        assertTrue((decoded?.deviceCode?.toByteArray(Charsets.UTF_8)?.size ?: 0) <= 128)
    }
    @Test
    fun voiceCallUsesAudioOnlyMediaCode() {
        val signal = CallSignal(
            type = CallSignalType.CALL,
            sessionId = 7,
            to = "watch_user",
            mediaCode = CallSignalCodec.AUDIO_ONLY_MEDIA_CODE,
            videoQuality = 0,
        )

        val encoded = CallSignalCodec.encode(signal)

        assertTrue(encoded.contains("\"mc\":1"))
        assertEquals(signal, CallSignalCodec.decode(encoded))
    }
}
