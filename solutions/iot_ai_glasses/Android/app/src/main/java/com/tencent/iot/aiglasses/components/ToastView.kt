package com.tencent.iot.aiglasses.components

import android.content.Context
import android.util.AttributeSet
import android.view.Gravity
import androidx.appcompat.widget.AppCompatTextView
import com.tencent.iot.aiglasses.R
import com.tencent.iot.aiglasses.designsystem.color
import com.tencent.iot.aiglasses.designsystem.dp
import com.tencent.iot.aiglasses.designsystem.dpInt
import com.tencent.iot.aiglasses.designsystem.roundedDrawable

class ToastView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : AppCompatTextView(context, attrs) {
    init {
        setTextAppearance(R.style.TextAppearance_Suisheng_Footnote)
        setTextColor(context.color(R.color.notice_text))
        gravity = Gravity.CENTER
        setPadding(context.dpInt(16f), context.dpInt(12f), context.dpInt(16f), context.dpInt(12f))
        background = context.roundedDrawable(12f, R.color.notice, R.color.notice_border)
        elevation = context.dp(8f)
        outlineSpotShadowColor = context.color(R.color.toast_shadow)
        outlineAmbientShadowColor = context.color(R.color.toast_shadow)
        isClickable = false
        isFocusable = false
        accessibilityLiveRegion = ACCESSIBILITY_LIVE_REGION_POLITE
    }
}
