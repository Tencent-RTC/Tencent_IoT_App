package com.tencent.iot.aiglasses.services.trtc

import android.util.Base64
import org.json.JSONObject
import java.util.zip.Deflater
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * 仅用于测试：客户端计算 UserSig 会泄露 SecretKey，正式产品必须由业务服务器下发。
 * https://cloud.tencent.com/document/product/647/17275
 */
object GenerateTestUserSig {
    private const val EXPIRE_TIME = 604800L

    fun genTestUserSig(sdkAppId: Int, userId: String, secretKey: String): String {
        val time = System.currentTimeMillis() / 1000
        val content = "TLS.identifier:$userId\nTLS.sdkappid:$sdkAppId\nTLS.time:$time\nTLS.expire:$EXPIRE_TIME\n"
        val json = JSONObject().apply {
            put("TLS.ver", "2.0")
            put("TLS.identifier", userId)
            put("TLS.sdkappid", sdkAppId)
            put("TLS.expire", EXPIRE_TIME)
            put("TLS.time", time)
            put("TLS.sig", hmac(content, secretKey))
        }
        val deflater = Deflater()
        deflater.setInput(json.toString().toByteArray(Charsets.UTF_8))
        deflater.finish()
        val buffer = ByteArray(2048)
        val length = deflater.deflate(buffer)
        deflater.end()
        return base64Url(buffer.copyOf(length))
    }

    private fun hmac(content: String, secretKey: String): String {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(secretKey.toByteArray(Charsets.UTF_8), "HmacSHA256"))
        return Base64.encodeToString(mac.doFinal(content.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)
    }

    private fun base64Url(data: ByteArray): String =
        Base64.encodeToString(data, Base64.NO_WRAP).replace('+', '*').replace('/', '-').replace('=', '_')
}
