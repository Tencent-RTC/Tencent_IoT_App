package com.tencent.iot.aiglasses.services

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper

class NetworkMonitor(context: Context) {
    var onChange: ((Boolean) -> Unit)? = null

    private val manager = context.getSystemService(ConnectivityManager::class.java)
    private val main = Handler(Looper.getMainLooper())

    fun start() {
        manager.registerDefaultNetworkCallback(object : ConnectivityManager.NetworkCallback() {
            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
                val online = capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
                main.post { onChange?.invoke(online) }
            }

            override fun onLost(network: Network) {
                main.post { onChange?.invoke(false) }
            }
        })
    }
}
