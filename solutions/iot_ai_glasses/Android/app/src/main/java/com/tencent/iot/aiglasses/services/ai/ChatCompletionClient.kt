package com.tencent.iot.aiglasses.services.ai

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

data class ChatMessage(val role: String, val content: String) {
    fun toJson(): JSONObject = JSONObject().put("role", role).put("content", content)

    companion object {
        fun system(content: String) = ChatMessage("system", content)
        fun user(content: String) = ChatMessage("user", content)
        fun assistant(content: String) = ChatMessage("assistant", content)
    }
}

class ChatCompletionException(message: String) : IOException(message)

class ChatCompletionClient {

    suspend fun complete(messages: List<ChatMessage>, temperature: Double = 0.2, thinking: Boolean = false): String =
        withContext(Dispatchers.IO) {
            if (!AIServiceConfig.isConfigured) {
                throw ChatCompletionException("请先在 AIServiceConfig 中配置大模型服务地址、API Key 与模型名")
            }
            val body = JSONObject()
                .put("model", AIServiceConfig.MODEL)
                .put("messages", JSONArray(messages.map { it.toJson() }))
                .put("stream", false)
                .put("temperature", temperature)
                .put("thinking", JSONObject().put("type", if (thinking) "enabled" else "disabled"))
            val connection = (URL(AIServiceConfig.ENDPOINT).openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = TIMEOUT_MS
                readTimeout = TIMEOUT_MS
                doOutput = true
                setRequestProperty("Authorization", "Bearer ${AIServiceConfig.API_KEY}")
                setRequestProperty("Content-Type", "application/json")
            }
            try {
                connection.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
                val status = connection.responseCode
                val stream = if (status in 200..299) connection.inputStream else connection.errorStream
                val text = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
                if (status != 200) throw ChatCompletionException("HTTP $status: ${text.take(300)}")
                val content = JSONObject(text).optJSONArray("choices")?.optJSONObject(0)
                    ?.optJSONObject("message")?.optString("content")?.trim()
                if (content.isNullOrEmpty()) throw ChatCompletionException("模型未返回内容")
                content
            } finally {
                connection.disconnect()
            }
        }

    companion object {
        private const val TIMEOUT_MS = 20_000
        val shared = ChatCompletionClient()
    }
}
