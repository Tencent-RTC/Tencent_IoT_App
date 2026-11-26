package com.tencent.iot.watchapp.ui
import com.tencent.iot.watchapp.R
import com.tencent.iot.watchapp.app.MainActivity
import com.tencent.iot.watchapp.app.AppScreen

import android.content.Context
import android.graphics.PorterDuff
import android.util.AttributeSet
import android.view.LayoutInflater
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.content.ContextCompat

class MainTabView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : FrameLayout(context, attrs, defStyleAttr) {
    private val items = mutableMapOf<AppScreen, LinearLayout>()
    private val icons = mutableMapOf<AppScreen, ImageView>()
    private val labels = mutableMapOf<AppScreen, TextView>()

    init {
        LayoutInflater.from(context).inflate(R.layout.watch_main_tab_view, this, true)
        register(AppScreen.MESSAGES, R.id.watch_tab_messages, R.id.watch_tab_messages_icon, R.id.watch_tab_messages_text)
        register(AppScreen.LOCATION, R.id.watch_tab_location, R.id.watch_tab_location_icon, R.id.watch_tab_location_text)
        register(AppScreen.DEVICES, R.id.watch_tab_devices, R.id.watch_tab_devices_icon, R.id.watch_tab_devices_text)
        register(AppScreen.PROFILE, R.id.watch_tab_profile, R.id.watch_tab_profile_icon, R.id.watch_tab_profile_text)
        findViewById<ImageButton>(R.id.watch_tab_call_button).setOnClickListener {
            (context as? MainActivity)?.showCallTargetPicker()
        }
    }

    private fun register(screen: AppScreen, itemId: Int, iconId: Int, labelId: Int) {
        val item = findViewById<LinearLayout>(itemId)
        items[screen] = item
        icons[screen] = findViewById(iconId)
        labels[screen] = findViewById(labelId)
        item.setOnClickListener { (context as? MainActivity)?.onTabSelected(screen) }
    }

    private fun tint(icon: ImageView, color: Int) {
        icon.setColorFilter(color, PorterDuff.Mode.SRC_IN)
    }

    fun select(screen: AppScreen) {
        items.forEach { (tab, item) ->
            val selected = tab == screen
            item.isSelected = selected
            val tintColor = ContextCompat.getColor(context, if (selected) R.color.watch_trust_blue else R.color.watch_text_secondary)
            icons[tab]?.let { tint(it, tintColor) }
            labels[tab]?.setTextColor(tintColor)
        }
    }
}
