package com.tencent.iot.aiglasses.services.ai

import com.tencent.iot.aiglasses.models.MeetingSummary
import com.tencent.iot.aiglasses.models.MeetingTodo
import com.tencent.iot.aiglasses.models.TranscriptLine
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

class MeetingSummarizerException(message: String) : Exception(message)

class MeetingSummarizer(private val client: ChatCompletionClient = ChatCompletionClient.shared) {

    suspend fun summarize(title: String, durationSeconds: Int, lines: List<TranscriptLine>): MeetingSummary {
        val transcript = lines.joinToString("\n") { "${it.speakerLabel ?: "发言人"}：${it.original}" }
        if (transcript.isBlank()) throw MeetingSummarizerException("本次没有识别到文字")

        val prompt = """
            请根据以下会议转写内容生成会议纪要。严格只输出一个 JSON 对象，不要输出任何解释文字或代码块标记，格式：
            {"title":"会议标题","headline":"一句话总结","consensus":["已达成共识的点",...],"questions":["待确认的问题",...],"todos":[{"text":"待办事项","note":"负责人或时间的说明"}]}
            要求：title 根据转写内容概括本次会议主题，不超过 12 字，不含日期时间；headline 不超过 40 字；consensus 和 questions 各最多 5 条，没有就给空数组；todos 最多 5 条，没有就给空数组；全部用简体中文。
            会议开始于：$title
            会议时长：约 ${maxOf(1, durationSeconds / 60)} 分钟
            转写内容：
            $transcript
        """.trimIndent()

        val reply = client.complete(listOf(ChatMessage.user(prompt)), temperature = 0.3)
        return parse(reply)
    }

    private fun parse(reply: String): MeetingSummary {
        var json = reply.trim()
        if (json.startsWith("```")) {
            json = json.substringAfter('\n').substringBeforeLast("```").trim()
        }
        return try {
            val dto = JSONObject(json)
            MeetingSummary(
                phase = MeetingSummary.Phase.READY,
                title = dto.optString("title").takeIf(String::isNotBlank),
                headline = dto.getString("headline"),
                consensus = dto.optJSONArray("consensus").strings(),
                questions = dto.optJSONArray("questions").strings(),
                todos = dto.optJSONArray("todos").objects().map { MeetingTodo(text = it.getString("text"), note = it.optString("note")) }
            )
        } catch (e: JSONException) {
            throw MeetingSummarizerException("模型返回的内容无法解析为会议纪要")
        }
    }
}

private fun JSONArray?.strings(): List<String> = if (this == null) emptyList() else List(length()) { getString(it) }

private fun JSONArray?.objects(): List<JSONObject> = if (this == null) emptyList() else List(length()) { getJSONObject(it) }
