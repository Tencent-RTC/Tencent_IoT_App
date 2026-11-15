package com.tencent.iot.watchapp.ui
import com.tencent.iot.watchapp.call.*

import com.tencent.rtmp.ui.TXCloudVideoView

/** Android 页面到 IoT 媒体适配器的视频 View 适配。 */
class AndroidCallVideoSurface(private val view: TXCloudVideoView) : CallVideoSurface {
    override fun bindRemote(controller: CallMediaSession) {
        controller.bindRemoteView(view)
    }

    override fun startLocalVideo(controller: CallMediaSession, frontCamera: Boolean) {
        controller.openCamera(view, frontCamera)
    }

    override fun setCameraEnabled(controller: CallMediaSession, enabled: Boolean, frontCamera: Boolean) {
        if (enabled) controller.openCamera(view, frontCamera) else controller.closeCamera()
    }
}
