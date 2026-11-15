package com.tencent.iot.watchapp.call
import com.tencent.iot.watchapp.config.WatchSdkConfig

import java.nio.charset.StandardCharsets
import java.util.Base64
import java.util.zip.Deflater
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/** 与腾讯云 UserSig v2 规则一致的本地计算器，仅用于开发联调。 */
internal object TencentUserSigGenerator {
    fun generate(
        sdkAppId: Long,
        userId: String,
        secretKey: String,
        nowSeconds: Long,
        expireSeconds: Long = WatchSdkConfig.userSigExpireSeconds,
    ): String {
        require(sdkAppId > 0) { "IMSDK SDKAppID must be configured" }
        require(userId.isNotBlank()) { "userId must not be blank" }
        require(secretKey.isNotBlank()) { "IMSDK SDKSecretKey must be configured" }

        val content = buildString {
            append("TLS.identifier:").append(userId).append('\n')
            append("TLS.sdkappid:").append(sdkAppId).append('\n')
            append("TLS.time:").append(nowSeconds).append('\n')
            append("TLS.expire:").append(expireSeconds).append('\n')
        }
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(secretKey.toByteArray(StandardCharsets.UTF_8), "HmacSHA256"))
        val signature = Base64.getEncoder().encodeToString(
            mac.doFinal(content.toByteArray(StandardCharsets.UTF_8)),
        )
        val document = buildString {
            append("{\"TLS.ver\":\"2.0\",")
            append("\"TLS.identifier\":").append(jsonString(userId)).append(',')
            append("\"TLS.sdkappid\":").append(sdkAppId).append(',')
            append("\"TLS.expire\":").append(expireSeconds).append(',')
            append("\"TLS.time\":").append(nowSeconds).append(',')
            append("\"TLS.sig\":").append(jsonString(signature))
            append('}')
        }
        val input = document.toByteArray(StandardCharsets.UTF_8)
        val deflater = Deflater()
        return try {
            deflater.setInput(input)
            deflater.finish()
            val output = ByteArray(input.size + 128)
            val length = deflater.deflate(output)
            Base64.getEncoder().encodeToString(output.copyOf(length))
                .replace('+', '*')
                .replace('/', '-')
                .replace('=', '_')
        } finally {
            deflater.end()
        }
    }

    private fun jsonString(value: String): String = buildString {
        append('"')
        value.forEach { character ->
            when (character) {
                '\\' -> append("\\\\")
                '"' -> append("\\\"")
                '\b' -> append("\\b")
                '\u000C' -> append("\\f")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                '\t' -> append("\\t")
                in '\u0000'..'\u001F' -> append("\\u%04x".format(character.code))
                else -> append(character)
            }
        }
        append('"')
    }
}
