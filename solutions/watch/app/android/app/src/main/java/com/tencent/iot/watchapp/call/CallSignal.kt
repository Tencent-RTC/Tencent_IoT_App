package com.tencent.iot.watchapp.call

import org.json.JSONArray
import org.json.JSONObject
import kotlinx.coroutines.flow.Flow
import java.nio.charset.StandardCharsets

enum class CallSignalType(val wireValue: String) {
    CALL("call"),
    ACCEPT("accept"),
    REJECT("reject"),
    HANGUP("hangup"),
}

data class CallSignal(
    val type: CallSignalType,
    val sessionId: Long,
    val to: String,
    val mediaCode: Int? = null,
    val videoQuality: Int? = null,
    val deviceCode: String? = null,
    val reason: String? = null,
)

data class IncomingCallSignal(val senderId: String, val signal: CallSignal)

/**
 * 宿主 App 提供的最小通话信令接口。
 *
 * 通话模块只依赖这组能力，不直接依赖 IMSDK 或 ImService，移植时可替换为任意 IM 实现。
 */
interface CallSignalTransport {
    val localUserId: String
    val incomingSignals: Flow<IncomingCallSignal>
    val transportAvailable: Flow<Boolean>
    fun send(to: String, signal: CallSignal, callback: (Result<Unit>) -> Unit)
}

/** App 与手表之间的协议 v1。信令只使用扁平 JSON 文本，不使用 V2TIMSignalingManager。 */
object CallSignalCodec {
    private const val VERSION = 1
    private const val MAX_SESSION_ID = 0xFFFF_FFFFL
    private const val MAX_DEVICE_CODE_BYTES = 128

    const val AUDIO_ONLY_MEDIA_CODE = 1
    const val VIDEO_ONLY_MEDIA_CODE = 2
    const val AUDIO_VIDEO_MEDIA_CODE = 3
    const val VIDEO_QUALITY_HIGH = 2

    fun encode(signal: CallSignal): String {
        require(signal.sessionId in 0..MAX_SESSION_ID) { "sessionId must be uint32" }
        require(signal.to.isNotBlank()) { "to must not be blank" }
        if (signal.type == CallSignalType.CALL) {
            require(signal.mediaCode != null && signal.videoQuality != null) { "call requires mc and vq" }
        }
        require(signal.mediaCode == null || signal.mediaCode >= 0) { "mc must be non-negative" }
        require(signal.videoQuality == null || signal.videoQuality >= 0) { "vq must be non-negative" }
        val json = JSONObject()
            .put("v", VERSION)
            .put("t", signal.type.wireValue)
            .put("sid", signal.sessionId)
            .put("to", signal.to)
        signal.mediaCode?.let { json.put("mc", it) }
        signal.videoQuality?.let { json.put("vq", it) }
        signal.deviceCode?.takeIf { it.isNotEmpty() }?.let { json.put("cd", truncateUtf8(it)) }
        signal.reason?.takeIf { it.isNotEmpty() }?.let { json.put("rs", it) }
        return json.toString()
    }

    fun decode(text: String): CallSignal? {
        val json = try { JSONObject(text) } catch (_: Exception) { return null }
        val keys = json.keys()
        while (keys.hasNext()) {
            when (json.opt(keys.next())) {
                is JSONObject, is JSONArray -> return null
            }
        }
        if (json.optIntOrNull("v") != VERSION) return null
        val type = when (json.stringOrNull("t")) {
            CallSignalType.CALL.wireValue -> CallSignalType.CALL
            CallSignalType.ACCEPT.wireValue -> CallSignalType.ACCEPT
            CallSignalType.REJECT.wireValue -> CallSignalType.REJECT
            CallSignalType.HANGUP.wireValue -> CallSignalType.HANGUP
            else -> return null
        }
        val sessionId = json.optLongStrict("sid") ?: return null
        val to = json.stringOrNull("to") ?: return null
        if (sessionId !in 0..MAX_SESSION_ID || to.isBlank()) return null
        val mediaCode = if (json.has("mc")) json.optIntOrNull("mc") ?: return null else null
        val videoQuality = if (json.has("vq")) json.optIntOrNull("vq") ?: return null else null
        if (type == CallSignalType.CALL && (mediaCode == null || videoQuality == null)) return null
        return buildSignal(type, sessionId, to, mediaCode, videoQuality, json)
    }

    private fun buildSignal(type: CallSignalType, sessionId: Long, to: String, mediaCode: Int?, videoQuality: Int?, json: JSONObject): CallSignal {
        return CallSignal(
            type = type,
            sessionId = sessionId,
            to = to,
            mediaCode = mediaCode,
            videoQuality = videoQuality,
            deviceCode = json.stringOrNull("cd"),
            reason = json.stringOrNull("rs"),
        )
    }

    private fun JSONObject.optIntOrNull(key: String): Int? {
        if (!has(key)) return null
        val value = opt(key)
        return when (value) {
            is Int -> value.takeIf { it >= 0 }
            is Long -> value.takeIf { it in 0..Int.MAX_VALUE }?.toInt()
            else -> null
        }
    }

    private fun JSONObject.optLongStrict(key: String): Long? {
        if (!has(key)) return null
        return when (val value = opt(key)) {
            is Int -> value.toLong()
            is Long -> value
            else -> null
        }
    }

    private fun JSONObject.stringOrNull(key: String): String? {
        if (!has(key)) return null
        return (opt(key) as? String)?.takeIf { it.isNotEmpty() }
    }

    private fun truncateUtf8(value: String): String {
        if (value.toByteArray(StandardCharsets.UTF_8).size <= MAX_DEVICE_CODE_BYTES) return value
        val result = StringBuilder()
        var bytes = 0
        for (character in value) {
            val characterBytes = character.toString().toByteArray(StandardCharsets.UTF_8).size
            if (bytes + characterBytes > MAX_DEVICE_CODE_BYTES) break
            result.append(character)
            bytes += characterBytes
        }
        return result.toString()
    }
}
