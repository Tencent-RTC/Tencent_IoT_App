package com.tencent.iot.aiglasses.components

import android.content.Context
import android.graphics.Typeface
import android.util.AttributeSet
import android.view.Gravity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.Space
import android.widget.TextView
import com.tencent.iot.aiglasses.R
import com.tencent.iot.aiglasses.designsystem.AppIcon
import com.tencent.iot.aiglasses.designsystem.Elevation
import com.tencent.iot.aiglasses.designsystem.color
import com.tencent.iot.aiglasses.designsystem.dpInt
import com.tencent.iot.aiglasses.designsystem.elevation
import com.tencent.iot.aiglasses.designsystem.isDarkTheme
import com.tencent.iot.aiglasses.designsystem.ovalDrawable
import com.tencent.iot.aiglasses.designsystem.pressable
import com.tencent.iot.aiglasses.designsystem.roundedDrawable
import com.tencent.iot.aiglasses.designsystem.setAppIcon
import com.tencent.iot.aiglasses.models.Clock

class SessionBanner @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : LinearLayout(context, attrs) {

    private val label = TextView(context).apply {
        setTextAppearance(R.style.TextAppearance_Suisheng_Caption)
        setTextColor(context.color(R.color.notice_text))
        fontFeatureSettings = "tnum"
        typeface = Typeface.DEFAULT
    }

    init {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        val horizontal = context.dpInt(16f)
        setPadding(horizontal, 0, horizontal, 0)
        minimumHeight = context.dpInt(48f)
        val radius = if (context.isDarkTheme) 10f else 16f
        background = context.pressable(context.roundedDrawable(radius, R.color.notice, R.color.notice_border))
        elevation(Elevation.RAISED)
        isClickable = true
        isFocusable = true
        addView(View(context).apply { background = context.ovalDrawable(R.color.notice_dot) }, LayoutParams(context.dpInt(6f), context.dpInt(6f)))
        addView(label, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply { marginStart = context.dpInt(8f) })
        addView(Space(context), LayoutParams(0, 0, 1f).apply { marginStart = context.dpInt(8f) })
        addView(ImageView(context).apply { setAppIcon(AppIcon.ARROW, R.color.notice_text) }, LayoutParams(context.dpInt(18f), context.dpInt(18f)))
    }

    fun set(status: String, seconds: Int) {
        label.text = "$status · ${Clock.text(seconds)}"
        contentDescription = "$status，已进行 ${Clock.text(seconds)}，返回当前任务"
    }
}
