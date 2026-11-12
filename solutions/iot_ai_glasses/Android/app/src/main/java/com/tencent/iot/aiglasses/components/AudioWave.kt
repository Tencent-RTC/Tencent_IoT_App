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

class AudioWave @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : View(context, attrs) {

    var isActive = false
        set(value) {
            if (field == value) return
            field = value
            alpha = if (value) 1f else 0.35f
            invalidate()
        }

    var speed = 1f
        set(value) {
            if (field == value) return
            field = value
            invalidate()
        }

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = context.color(R.color.accent) }

    init {
        alpha = 0.35f
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = context.dp(2f) * HEIGHTS.size + context.dp(4f) * (HEIGHTS.size - 1)
        setMeasuredDimension(width.toInt(), context.dpInt(32f))
    }

    override fun onDraw(canvas: Canvas) {
        val animate = isActive && ValueAnimator.areAnimatorsEnabled()
        val time = SystemClock.uptimeMillis() / 1000.0
        val bar = context.dp(2f)
        val gap = context.dp(4f)
        val center = height / 2f
        HEIGHTS.forEachIndexed { index, base ->
            val scale = if (animate) {
                val period = (0.9 + (index % 5) * 0.12) * speed
                val wave = (sin((time / period) * PI * 2 + index * 0.37) + 1) / 2
                (0.45 + 0.55 * wave).toFloat()
            } else {
                1f
            }
            val half = context.dp(base) * scale / 2
            val left = index * (bar + gap)
            canvas.drawRoundRect(left, center - half, left + bar, center + half, bar / 2, bar / 2, paint)
        }
        if (animate) postInvalidateOnAnimation()
    }

    private companion object {
        val HEIGHTS = floatArrayOf(9f, 18f, 12f, 25f, 15f, 29f, 20f, 12f, 24f, 16f, 8f, 20f, 29f, 16f, 23f, 12f, 7f)
    }
}
