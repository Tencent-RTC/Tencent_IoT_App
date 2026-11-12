package com.tencent.iot.aiglasses.components

import android.content.Context
import android.util.AttributeSet
import android.widget.LinearLayout
import com.tencent.iot.aiglasses.designsystem.Spacing
import com.tencent.iot.aiglasses.designsystem.dpInt
import com.tencent.iot.aiglasses.designsystem.pageBackground

class FlowScreen @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : LinearLayout(context, attrs) {
    init {
        orientation = VERTICAL
        clipChildren = false
        clipToPadding = false
        background = context.pageBackground()
        val horizontal = context.dpInt(Spacing.SCREEN_HORIZONTAL)
        setPadding(horizontal, context.dpInt(Spacing.SCREEN_TOP), horizontal, context.dpInt(20f))
    }
}
