package com.tencent.iot.watchapp.call
import com.tencent.iot.watchapp.config.WatchLogger

import android.content.Context
import android.os.Build
import com.tencent.liteav.iot.TXIoTEngine
import com.tencent.liteav.iot.TXIoTEngineDef
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

sealed interface IoTLoginState {
    object LoggedOut : IoTLoginState
    object LoggingIn : IoTLoginState
    data class LoggedIn(val userId: String) : IoTLoginState
    data class Failed(val code: String, val message: String) : IoTLoginState
}

/** 只负责 IoT 引擎生命周期，不承载页面逻辑和通话状态。 */
class IoTSession(
    context: Context,
    private val scope: CoroutineScope,
) {
    private val mutableState = MutableStateFlow<IoTLoginState>(IoTLoginState.LoggedOut)
    val loginState: StateFlow<IoTLoginState> = mutableState.asStateFlow()

    private val sdkAvailable = Build.SUPPORTED_ABIS.any { it == "arm64-v8a" }
    private val engine: TXIoTEngine? = if (sdkAvailable) {
        TXIoTEngine.getInstance(context.applicationContext)
    } else {
        null
    }

    @Volatile
    private var activeUserId: String? = null
    @Volatile
    private var activeConfig: IotSessionConfig? = null

    private val listener = object : TXIoTEngine.TXIoTEngineListener() {
        override fun onLoginSuccess() {
            val userId = activeUserId
            WatchLogger.i("IoT login success, userId=${userId ?: "unknown"}")
            mutableState.value = if (userId.isNullOrBlank()) {
                IoTLoginState.LoggedOut
            } else {
                IoTLoginState.LoggedIn(userId)
            }
        }

        override fun onLoginFailure(code: TXIoTEngineDef.TXIoTErrorCode?, message: String?) {
            WatchLogger.e("IoT login failure, code=${code?.name ?: "unknown"}, message=${message.orEmpty()}")
            mutableState.value = IoTLoginState.Failed(code?.name ?: "ERR_FAILED", message.orEmpty())
        }

        override fun onLogout() {
            activeUserId = null
            activeConfig = null
            mutableState.value = IoTLoginState.LoggedOut
        }

        override fun onUserSignatureExpired() {
            activeConfig?.let { config -> scope.launch { login(config) } }
        }
    }

    init {
        engine?.addListener(listener)
        if (!sdkAvailable) {
            WatchLogger.w("IoT SDK runtime requires arm64-v8a; current ABI is emulator-only")
        }
    }

    suspend fun login(config: IotSessionConfig) {
        activeConfig = config
        WatchLogger.i("IoT login started, sdkAvailable=$sdkAvailable, secretPresent=${config.appSecret.isNotBlank()}")
        if (config.appSecret == "watch_local_secret") {
            mutableState.value = IoTLoginState.Failed(
                "SDK_UNAVAILABLE",
                "LOCAL_UI_ONLY_CREDENTIALS",
            )
            return
        }
        if (engine == null) {
            WatchLogger.w("IoT login skipped because SDK engine is unavailable")
            mutableState.value = IoTLoginState.Failed(
                "SDK_UNAVAILABLE",
                "SDK_UNAVAILABLE_ON_CURRENT_ABI",
            )
            return
        }
        mutableState.value = IoTLoginState.LoggingIn
        val credentials = try {
            withContext(Dispatchers.Default) { IoTSignatureProviders.require().fetchSignature(config) }
        } catch (error: Exception) {
            WatchLogger.e("IoT signature generation failed: ${error.message}")
            activeUserId = null
            activeConfig = null
            mutableState.value = IoTLoginState.Failed("SIGNATURE_UNAVAILABLE", error.message.orEmpty())
            return
        }
        activeUserId = credentials.requestId
        engine.login(
            credentials.appKey,
            credentials.loginId,
            TXIoTEngine.TXIoTUserSignature().apply {
                requestId = credentials.requestId
                timestamp = credentials.timestamp
                nonce = credentials.nonce
                signature = credentials.signature
            },
            TXIoTEngine.TXIoTRegion.DEFAULT,
        )
        WatchLogger.i("IoT login requested, room=${credentials.loginId}, user=${credentials.requestId}")
    }

    fun logout() {
        engine?.logout()
        activeUserId = null
        activeConfig = null
        mutableState.value = IoTLoginState.LoggedOut
    }

    fun callSession() = engine?.callSession

    fun release() {
        engine?.removeListener(listener)
    }
}
