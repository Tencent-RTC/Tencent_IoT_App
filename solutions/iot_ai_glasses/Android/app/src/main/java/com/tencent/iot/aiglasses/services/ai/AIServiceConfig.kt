package com.tencent.iot.aiglasses.services.ai

object AIServiceConfig {
    // TODO: 客户填写自己的大模型服务地址、API Key 与模型名；生产环境应由业务服务器转发，客户端不保存 API Key
    const val ENDPOINT = ""
    const val API_KEY = ""
    const val MODEL = ""

    val isConfigured: Boolean
        get() = ENDPOINT.startsWith("https://") && API_KEY.isNotEmpty() && MODEL.isNotEmpty()
}
