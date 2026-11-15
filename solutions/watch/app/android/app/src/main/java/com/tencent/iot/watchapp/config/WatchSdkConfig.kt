package com.tencent.iot.watchapp.config

/**
 * 本地联调配置入口。
 *
 * 本地联调 SDK 配置入口；真实密钥不能进入正式客户端，生产环境必须由服务端签发 UserSig。
 */
internal object WatchSdkConfig {
    /** TRTC／IoT 房间登录 SDKAppID；登录页默认显示后仍允许手动修改。 */
    const val TRTC_SDK_APP_ID: Long = 0L

    /** TRTC／IoT 房间登录密钥，仅用于本地联调。 */
    const val TRTC_SECRET_KEY: String = ""

    /** IMSDK 初始化和 UserSig 使用的 SDKAppID。 */
    const val IM_SDK_APP_ID: Long = 0L

    /** IMSDK UserSig 使用的 SDKSecretKey，仅用于本地联调。 */
    const val IM_SECRET_KEY: String = ""

    /** TRTC／IoT 登录页默认房间号；登录页显示后仍允许手动修改。 */
    const val TRTC_ROOM_ID: String = "260101"

    /** 首期本地绑定使用的产品 ID，待接入真实绑定服务后替换为服务端返回值。 */
    const val boundWatchProductId: String = "PRODUCT_A"

    const val userSigExpireSeconds: Long = 604800L
}

/** 按设计目录规则为当前手机端生成跨 SDK 复用的 userId。 */
internal object WatchIdentity {
    fun userId(channel: String): String {
        val normalizedChannel = channel.trim()
        return if (normalizedChannel.isEmpty()) "" else "${normalizedChannel}_phone"
    }
}
