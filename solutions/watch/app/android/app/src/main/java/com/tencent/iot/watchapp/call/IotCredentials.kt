package com.tencent.iot.watchapp.call

data class IoTUserSignature(
    val appKey: String,
    val loginId: String,
    val requestId: String,
    val timestamp: Long,
    val nonce: Int,
    val signature: String,
)

interface IoTSignatureProvider {
    suspend fun fetchSignature(config: IotSessionConfig): IoTUserSignature
}

object IoTSignatureProviders {
    @Volatile
    private var current: IoTSignatureProvider = object : IoTSignatureProvider {
        override suspend fun fetchSignature(config: IotSessionConfig): IoTUserSignature {
            error("signature provider is not configured")
        }
    }

    fun install(provider: IoTSignatureProvider) {
        current = provider
    }

    fun require(): IoTSignatureProvider = current
}
