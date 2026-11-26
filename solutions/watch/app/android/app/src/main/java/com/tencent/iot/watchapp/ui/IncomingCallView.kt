package com.tencent.iot.watchapp.ui
import com.tencent.iot.watchapp.R
import com.tencent.iot.watchapp.app.MainActivity

import android.content.Context
import android.util.AttributeSet
import android.view.LayoutInflater
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView

class IncomingCallView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0,
) : FrameLayout(context, attrs, defStyleAttr) {
    init {
        id = R.id.watch_incoming_call_root
        LayoutInflater.from(context).inflate(R.layout.watch_incoming_call, this, true)
        findViewById<TextView>(R.id.watch_incoming_accept).setOnClickListener {
            (context as? MainActivity)?.acceptIncomingCall()
        }
        findViewById<TextView>(R.id.watch_incoming_reject).setOnClickListener {
            (context as? MainActivity)?.rejectIncomingCall()
        }
    }

    fun configure(targetName: String, avatarRes: Int, audioOnly: Boolean) {
        findViewById<ImageView>(R.id.watch_incoming_stage).setImageResource(avatarRes)
        findViewById<ImageView>(R.id.watch_incoming_avatar).setImageResource(avatarRes)
        findViewById<TextView>(R.id.watch_incoming_name).text = targetName
        findViewById<TextView>(R.id.watch_incoming_nav_title).text = targetName
        findViewById<TextView>(R.id.watch_incoming_nav_subtitle).setText(
            if (audioOnly) R.string.watch_call_voice_incoming else R.string.watch_call_video_incoming,
        )
        findViewById<TextView>(R.id.watch_incoming_name).setText(
            if (audioOnly) R.string.watch_call_voice_incoming else R.string.watch_call_incoming,
        )
    }
}
