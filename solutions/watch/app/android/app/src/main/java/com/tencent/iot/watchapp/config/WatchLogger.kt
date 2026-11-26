package com.tencent.iot.watchapp.config

import android.util.Log

object WatchLogger {
    private const val tag = "WatchApp"

    fun d(message: String) = Log.d(tag, message)
    fun i(message: String) = Log.i(tag, message)
    fun w(message: String) = Log.w(tag, message)
    fun e(message: String, error: Throwable? = null) {
        if (error == null) Log.e(tag, message) else Log.e(tag, message, error)
    }
}
