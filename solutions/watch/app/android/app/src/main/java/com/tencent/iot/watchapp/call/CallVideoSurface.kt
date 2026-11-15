package com.tencent.iot.watchapp.call

/** 通话页面提供的视频渲染表面，隔离页面 View 和媒体 SDK View 类型。 */
interface CallVideoSurface {
    fun bindRemote(controller: CallMediaSession)
    fun startLocalVideo(controller: CallMediaSession, frontCamera: Boolean)
    fun setCameraEnabled(controller: CallMediaSession, enabled: Boolean, frontCamera: Boolean)
}
