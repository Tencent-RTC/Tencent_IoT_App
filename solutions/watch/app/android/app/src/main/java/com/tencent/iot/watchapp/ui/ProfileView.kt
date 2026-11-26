package com.tencent.iot.watchapp.ui
import com.tencent.iot.watchapp.R
import com.tencent.iot.watchapp.app.MainActivity
import com.tencent.iot.watchapp.im.ImService
import com.tencent.iot.watchapp.watch.WatchAvatarResolver

import android.content.Context
import android.util.AttributeSet
import android.view.LayoutInflater
import android.view.View
import android.widget.FrameLayout

class ProfileView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : FrameLayout(context, attrs, defStyleAttr) {
    init {
        LayoutInflater.from(context).inflate(R.layout.watch_profile_view, this, true)
        findViewById<android.widget.ImageView>(R.id.watch_profile_avatar)
            .setImageResource(WatchAvatarResolver.resourceFor(ImService.loggedInUserId))
        findViewById<View>(R.id.watch_profile_logout).setOnClickListener {
            (context as? MainActivity)?.onLogoutRequested()
        }
    }
}
