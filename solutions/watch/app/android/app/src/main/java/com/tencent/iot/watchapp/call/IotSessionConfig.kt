package com.tencent.iot.watchapp.call

/** 一次 IoT／TRTC 登录所需的运行时配置，不持有页面或 SDK 类型。 */
data class IotSessionConfig(
    val channel: String,
    val appId: String,
    val appSecret: String,
)
