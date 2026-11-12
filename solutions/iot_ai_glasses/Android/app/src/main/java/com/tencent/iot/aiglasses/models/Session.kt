package com.tencent.iot.aiglasses.models

import org.json.JSONObject
import java.util.Locale
import java.util.UUID

enum class SessionKind(val rawValue: String) {
    TRANSLATION("translation"),
    INTERPRET("interpret"),
    MEETING("meeting"),
    CALL("call");

    val shortLabel: String
        get() = when (this) {
            TRANSLATION -> "翻译"
            INTERPRET -> "同传"
            MEETING -> "会议"
            CALL -> "通话"
        }

    val title: String
        get() = when (this) {
            TRANSLATION -> "实时翻译"
            INTERPRET -> "双向传译"
            MEETING -> "会议转录"
            CALL -> "语音通话"
        }

    val needsNetwork: Boolean
        get() = this != CALL

    companion object {
        fun from(raw: String?): SessionKind? = entries.firstOrNull { it.rawValue == raw }
    }
}

enum class Language(val rawValue: String) {
    ENGLISH("英语"),
    CHINESE("中文");

    val other: Language
        get() = if (this == ENGLISH) CHINESE else ENGLISH

    companion object {
        fun from(raw: String?): Language = entries.firstOrNull { it.rawValue == raw } ?: ENGLISH
    }
}

enum class Speaker(val rawValue: String) {
    OTHER("other"),
    ME("me");

    companion object {
        fun from(raw: String?): Speaker = entries.firstOrNull { it.rawValue == raw } ?: OTHER
    }
}

data class TranscriptLine(
    val id: UUID = UUID.randomUUID(),
    var original: String,
    var translated: String,
    var speaker: Speaker = Speaker.OTHER,
    var time: Int,
    var speakerLabel: String? = null
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id.toString())
        put("original", original)
        put("translated", translated)
        put("speaker", speaker.rawValue)
        put("time", time)
        speakerLabel?.let { put("speakerLabel", it) }
    }

    companion object {
        fun fromJson(json: JSONObject) = TranscriptLine(
            id = UUID.fromString(json.getString("id")),
            original = json.getString("original"),
            translated = json.optString("translated"),
            speaker = Speaker.from(json.optString("speaker")),
            time = json.optInt("time"),
            speakerLabel = if (json.has("speakerLabel")) json.getString("speakerLabel") else null
        )
    }
}

class ActiveSession(
    val kind: SessionKind,
    var source: Language = Language.ENGLISH,
    var target: Language = Language.CHINESE,
    var savesText: Boolean = true,
    var readsAloud: Boolean = true,
    var engine: CaptionEngine = CaptionEngine.TRANSCRIBER
) {
    val id: UUID = UUID.randomUUID()
    var seconds = 0
    var isPaused = false
    var speaking = Speaker.OTHER
    val entries = mutableListOf<TranscriptLine>()
    var asrRun = 0
    val asrSegments = mutableMapOf<String, UUID>()
    var title = ""
    var keepsAudio = false
    var isStarred = false
}

enum class CaptionEngine(val rawValue: String) {
    TRANSCRIBER("transcriber"),
    ASR_LLM("asrLLM");

    val title: String
        get() = when (this) {
            TRANSCRIBER -> "TRTC AI 转写"
            ASR_LLM -> "识别 + 大模型翻译"
        }

    companion object {
        fun from(raw: String?): CaptionEngine? = entries.firstOrNull { it.rawValue == raw }
    }
}

object Clock {
    fun text(seconds: Int): String = String.format(Locale.ROOT, "%02d:%02d", seconds / 60, seconds % 60)
}
