package com.tencent.iot.aiglasses.services

import android.util.Log
import com.tencent.iot.aiglasses.models.Language
import com.tencent.iot.aiglasses.services.ai.ChatCompletionClient
import com.tencent.iot.aiglasses.services.ai.ChatMessage

interface TextTranslator {
    suspend fun translate(text: String, source: Language, target: Language): String?
}

class LLMTranslator(private val client: ChatCompletionClient = ChatCompletionClient.shared) : TextTranslator {
    override suspend fun translate(text: String, source: Language, target: Language): String? {
        val prompt = "You are a professional real-time interpreter. Translate the user's ${source.englishName} speech " +
            "transcript into ${target.englishName}. Keep the tone natural and spoken. " +
            "Output only the translation, without quotes, notes or explanations."
        return try {
            client.complete(listOf(ChatMessage.system(prompt), ChatMessage.user(text)))
        } catch (e: Exception) {
            Log.w("LLMTranslator", e.message.orEmpty())
            null
        }
    }
}

private val Language.englishName: String
    get() = when (this) {
        Language.ENGLISH -> "English"
        Language.CHINESE -> "Simplified Chinese"
    }
