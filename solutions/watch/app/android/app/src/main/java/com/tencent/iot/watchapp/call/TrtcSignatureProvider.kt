package com.tencent.iot.watchapp.call
import com.tencent.iot.watchapp.config.WatchSdkConfig
import com.tencent.iot.watchapp.config.WatchIdentity

import kotlin.random.Random

/** 仅用于当前设计目录联调的本地 UserSig 生成器。 */
internal object TrtcSignatureProvider : IoTSignatureProvider {
    override suspend fun fetchSignature(config: IotSessionConfig): IoTUserSignature {
        val appId = config.appId
        val secret = config.appSecret
        val channel = config.channel
        val userId = WatchIdentity.userId(channel)
        require(appId.isNotBlank() && secret.isNotBlank() && channel.isNotBlank()) {
            "channel, SDKAppID and SDKAppSecret are required"
        }
        val sdkAppId = appId.toLongOrNull() ?: error("SDKAppID must be numeric")
        val now = System.currentTimeMillis() / 1000
        return IoTUserSignature(
            appKey = appId,
            loginId = channel,
            requestId = userId,
            timestamp = now,
            nonce = Random.nextInt(1, Int.MAX_VALUE),
            signature = TencentUserSigGenerator.generate(
                sdkAppId = sdkAppId,
                userId = userId,
                secretKey = secret,
                nowSeconds = now,
            ),
        )
    }
}
