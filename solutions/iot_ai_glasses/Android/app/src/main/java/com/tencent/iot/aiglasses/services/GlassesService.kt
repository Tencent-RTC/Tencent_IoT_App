package com.tencent.iot.aiglasses.services

interface GlassesService {
    val isConnected: Boolean
    val batteryLevel: Int?
    fun connect()
    fun disconnect()
}

class MockGlassesService(isConnected: Boolean = true) : GlassesService {
    override var isConnected: Boolean = isConnected
        private set

    private val level = 82

    override val batteryLevel: Int?
        get() = if (isConnected) level else null

    override fun connect() {
        isConnected = true
    }

    override fun disconnect() {
        isConnected = false
    }
}
