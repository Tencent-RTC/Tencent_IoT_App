package com.tencent.iot.aiglasses.models

import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.UUID

enum class RecordKind(val rawValue: String) {
    MEETING("meeting"),
    TRANSLATION("translation");

    companion object {
        fun from(raw: String?): RecordKind = entries.firstOrNull { it.rawValue == raw } ?: TRANSLATION
    }
}

data class MeetingTodo(
    val id: UUID = UUID.randomUUID(),
    var text: String,
    var note: String,
    var isDone: Boolean = false
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id.toString())
        put("text", text)
        put("note", note)
        put("isDone", isDone)
    }

    companion object {
        fun fromJson(json: JSONObject) = MeetingTodo(
            id = UUID.fromString(json.getString("id")),
            text = json.getString("text"),
            note = json.optString("note"),
            isDone = json.optBoolean("isDone")
        )
    }
}

data class MeetingSummary(
    var phase: Phase = Phase.PENDING,
    var title: String? = null,
    var headline: String = "",
    var consensus: List<String> = emptyList(),
    var questions: List<String> = emptyList(),
    var todos: List<MeetingTodo> = emptyList()
) {
    enum class Phase(val rawValue: String) {
        PENDING("pending"),
        READY("ready"),
        FAILED("failed");

        companion object {
            fun from(raw: String?): Phase = entries.firstOrNull { it.rawValue == raw } ?: PENDING
        }
    }

    fun toJson(): JSONObject = JSONObject().apply {
        put("phase", phase.rawValue)
        put("headline", headline)
        put("consensus", JSONArray(consensus))
        put("questions", JSONArray(questions))
        put("todos", JSONArray(todos.map { it.toJson() }))
    }

    companion object {
        fun fromJson(json: JSONObject) = MeetingSummary(
            phase = Phase.from(json.optString("phase")),
            headline = json.optString("headline"),
            consensus = json.optJSONArray("consensus").strings(),
            questions = json.optJSONArray("questions").strings(),
            todos = json.optJSONArray("todos").objects().map(MeetingTodo::fromJson)
        )
    }
}

data class Record(
    val id: UUID = UUID.randomUUID(),
    var kind: RecordKind,
    var title: String,
    var createdAt: Instant,
    var durationSeconds: Int,
    var transcript: List<TranscriptLine>? = null,
    var keepsAudio: Boolean = false,
    var summary: MeetingSummary? = null,
    var source: Language? = null,
    var target: Language? = null,
    var isInterpret: Boolean = false,
    var isStarred: Boolean = false
) {
    val durationText: String
        get() = if (durationSeconds < 60) "不足 1 分钟" else "${durationSeconds / 60} 分钟"

    val translationHeading: String
        get() = if (isInterpret || title.contains("双向传译")) "双向传译" else "翻译记录"

    val languagePair: String?
        get() {
            val from = source ?: return null
            val to = target ?: return null
            return "${from.rawValue} ${if (isInterpret) "⇄" else "→"} ${to.rawValue}"
        }

    fun subtitle(now: Instant = Instant.now()): String = "${RecordDate.text(createdAt, now)} · $durationText"

    fun translationSubtitle(now: Instant = Instant.now()): String = listOfNotNull(languagePair, subtitle(now)).joinToString(" · ")

    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id.toString())
        put("kind", kind.rawValue)
        put("title", title)
        put("createdAt", createdAt.toString())
        put("durationSeconds", durationSeconds)
        transcript?.let { lines -> put("transcript", JSONArray(lines.map { it.toJson() })) }
        put("keepsAudio", keepsAudio)
        summary?.let { put("summary", it.toJson()) }
        source?.let { put("source", it.rawValue) }
        target?.let { put("target", it.rawValue) }
        put("isInterpret", isInterpret)
        if (isStarred) put("isStarred", true)
    }

    companion object {
        fun fromJson(json: JSONObject) = Record(
            id = UUID.fromString(json.getString("id")),
            kind = RecordKind.from(json.optString("kind")),
            title = json.getString("title"),
            createdAt = Instant.parse(json.getString("createdAt")),
            durationSeconds = json.optInt("durationSeconds"),
            transcript = json.optJSONArray("transcript")?.objects()?.map(TranscriptLine::fromJson),
            keepsAudio = json.optBoolean("keepsAudio"),
            summary = json.optJSONObject("summary")?.let(MeetingSummary::fromJson),
            source = if (json.has("source")) Language.from(json.optString("source")) else null,
            target = if (json.has("target")) Language.from(json.optString("target")) else null,
            isInterpret = json.optBoolean("isInterpret"),
            isStarred = json.optBoolean("isStarred")
        )
    }
}

object RecordDate {
    private val time = formatter("HH:mm")
    private val monthDay = formatter("M 月 d 日")
    private val full = formatter("yyyy 年 M 月 d 日")

    fun text(date: Instant, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): String {
        val day = date.atZone(zone)
        val today = now.atZone(zone).toLocalDate()
        return when {
            day.toLocalDate() == today -> "今天 ${time.format(day)}"
            day.toLocalDate() == today.minusDays(1) -> "昨天 ${time.format(day)}"
            day.year == today.year -> monthDay.format(day)
            else -> full.format(day)
        }
    }

    private fun formatter(pattern: String) = DateTimeFormatter.ofPattern(pattern, Locale.SIMPLIFIED_CHINESE)
}

private fun JSONArray?.strings(): List<String> =
    if (this == null) emptyList() else List(length()) { getString(it) }

private fun JSONArray?.objects(): List<JSONObject> =
    if (this == null) emptyList() else List(length()) { getJSONObject(it) }
