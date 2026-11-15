package com.tencent.iot.watchapp.watch
import com.tencent.iot.watchapp.R

import android.content.Context
import android.util.AttributeSet
import android.view.LayoutInflater
import android.widget.FrameLayout

class AddContactView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0,
) : FrameLayout(context, attrs, defStyleAttr) {
    init {
        LayoutInflater.from(context).inflate(R.layout.watch_add_contact_view, this, true)
    }

    fun setOnBack(action: () -> Unit) {
        findViewById<android.widget.ImageButton>(R.id.watch_add_contact_back).setOnClickListener { action() }
    }

    fun setOnAddWatch(action: () -> Unit) {
        findViewById<android.view.View>(R.id.watch_add_watch_row).setOnClickListener { action() }
    }

    fun setOnCreateGroup(action: () -> Unit) {
        findViewById<android.view.View>(R.id.watch_add_group_row).setOnClickListener { action() }
    }

}
