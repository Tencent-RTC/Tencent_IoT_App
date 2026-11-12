package com.tencent.iot.aiglasses.services.trtc

import android.content.Context
import java.util.UUID

object TRTCCredentials {
    // TODO: 客户填写自己的 SDKAppID 与 SDKSecretKey
    const val SDK_APP_ID = 0
    const val SECRET_KEY = ""

    private const val USER_ID_KEY = "trtcUserId"

    val isConfigured: Boolean
        get() = SDK_APP_ID != 0 && SECRET_KEY.isNotEmpty()

    fun userId(context: Context): String {
        val prefs = context.getSharedPreferences("suisheng", Context.MODE_PRIVATE)
        prefs.getString(USER_ID_KEY, null)?.let { return it }
        val generated = "glasses_" + UUID.randomUUID().toString().take(8).lowercase()
        prefs.edit().putString(USER_ID_KEY, generated).apply()
        return generated
    }

    fun userSig(context: Context): String = userSig(userId(context))

    fun userSig(identifier: String): String = GenerateTestUserSig.genTestUserSig(SDK_APP_ID, identifier, SECRET_KEY)
}
