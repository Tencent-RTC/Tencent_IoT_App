package com.tencent.iot.aiglasses.components

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.os.SystemClock
import android.util.AttributeSet
import android.view.View
import com.tencent.iot.aiglasses.R
import com.tencent.iot.aiglasses.designsystem.color
import com.tencent.iot.aiglasses.designsystem.dp
import com.tencent.iot.aiglasses.designsystem.dpInt
import kotlin.math.PI
import kotlin.math.sin

class ThinkingDots @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : View(context, attrs) {

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = context.color(R.color.text_secondary) }

    init {
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        setMeasuredDimension(context.dpInt(26f), context.dpInt(10f))
    }

    override fun onDraw(canvas: Canvas) {
        val animate = ValueAnimator.areAnimatorsEnabled()
        val time = SystemClock.uptimeMillis() / 1000.0
        val radius = context.dp(3f)
        val gap = context.dp(4f)
        repeat(3) { index ->
            paint.alpha = if (animate) (255 * (0.3 + 0.7 * (sin(time * PI * 2 - index * 0.8) + 1) / 2)).toInt() else 160
            canvas.drawCircle(radius + index * (radius * 2 + gap), height / 2f, radius, paint)
        }
        if (animate) postInvalidateOnAnimation()
    }
}
