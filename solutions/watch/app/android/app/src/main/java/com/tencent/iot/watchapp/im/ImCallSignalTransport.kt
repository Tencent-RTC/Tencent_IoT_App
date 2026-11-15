package com.tencent.iot.watchapp.im
import com.tencent.iot.watchapp.call.*

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/** 将 IM 服务适配为通话模块需要的最小信令传输接口。 */
class ImCallSignalTransport : CallSignalTransport {
    override val localUserId: String
        get() = ImService.loggedInUserId

    override val incomingSignals: Flow<IncomingCallSignal> = ImService.callSignalEvents

    override val transportAvailable: Flow<Boolean> = ImService.loginState.map { it is ImLoginState.LoggedIn }

    override fun send(to: String, signal: CallSignal, callback: (Result<Unit>) -> Unit) {
        ImService.sendCallSignal(to, signal, callback)
    }
}
