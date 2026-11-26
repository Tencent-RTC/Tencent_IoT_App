package com.tencent.iot.watchapp.im
import com.tencent.iot.watchapp.call.TencentUserSigGenerator
import com.tencent.iot.watchapp.config.WatchIdentity
import com.tencent.iot.watchapp.config.WatchSdkConfig

data class ImSdkCredentials(
    val sdkAppId: Long,
    val userId: String,
    val userSig: String,
)

/** 为后续 IMSDK 登录提供与 IoT SDK 相同的本端身份和 UserSig。 */
internal object ImSdkAuth {
    fun forChannel(channel: String, nowSeconds: Long = System.currentTimeMillis() / 1000): ImSdkCredentials {
        val userId = WatchIdentity.userId(channel)
        require(WatchSdkConfig.IM_SDK_APP_ID > 0) { "IM_SDK_APP_ID must be configured" }
        require(WatchSdkConfig.IM_SECRET_KEY.isNotBlank()) { "IM_SECRET_KEY must be configured" }
        return ImSdkCredentials(
            sdkAppId = WatchSdkConfig.IM_SDK_APP_ID,
            userId = userId,
            userSig = TencentUserSigGenerator.generate(
                sdkAppId = WatchSdkConfig.IM_SDK_APP_ID,
                userId = userId,
                secretKey = WatchSdkConfig.IM_SECRET_KEY,
                nowSeconds = nowSeconds,
            ),
        )
    }
}
