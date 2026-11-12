package com.tencent.iot.aiglasses.components

import android.animation.ArgbEvaluator
import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.util.AttributeSet
import android.view.View
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Switch
import androidx.core.view.ViewCompat
import com.tencent.iot.aiglasses.R
import com.tencent.iot.aiglasses.designsystem.color
import com.tencent.iot.aiglasses.designsystem.dp
import com.tencent.iot.aiglasses.designsystem.dpInt

class SoftSwitch @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : View(context, attrs) {

    var onCheckedChange: ((Boolean) -> Unit)? = null

    var isChecked = false
        private set

    private var progress = 0f
    private var animator: ValueAnimator? = null
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val track = RectF()
    private val evaluator = ArgbEvaluator()

    init {
        isClickable = true
        isFocusable = true
        setOnClickListener {
            setChecked(!isChecked, animated = true)
            onCheckedChange?.invoke(isChecked)
        }
        updateStateDescription()
    }

    fun setChecked(checked: Boolean, animated: Boolean = false) {
        if (checked == isChecked) return
        isChecked = checked
        animator?.cancel()
        val target = if (checked) 1f else 0f
        if (animated) {
            animator = ValueAnimator.ofFloat(progress, target).apply {
                duration = 200
                addUpdateListener {
                    progress = it.animatedValue as Float
                    invalidate()
                }
                start()
            }
        } else {
            progress = target
            invalidate()
        }
        updateStateDescription()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val size = context.dpInt(44f)
        setMeasuredDimension(size, size)
    }

    override fun onDraw(canvas: Canvas) {
        val trackWidth = context.dp(43f)
        val trackHeight = context.dp(24f)
        val left = (width - trackWidth) / 2
        val top = (height - trackHeight) / 2
        track.set(left, top, left + trackWidth, top + trackHeight)
        paint.color = blend(R.color.toggle_off, R.color.toggle_on)
        canvas.drawRoundRect(track, trackHeight / 2, trackHeight / 2, paint)

        val knob = context.dp(18f)
        val inset = context.dp(3f)
        val startX = left + inset + knob / 2
        val endX = left + trackWidth - inset - knob / 2
        paint.color = blend(R.color.toggle_knob_off, R.color.toggle_knob_on)
        canvas.drawCircle(startX + (endX - startX) * progress, top + trackHeight / 2, knob / 2, paint)
    }

    override fun onInitializeAccessibilityNodeInfo(info: AccessibilityNodeInfo) {
        super.onInitializeAccessibilityNodeInfo(info)
        info.className = Switch::class.java.name
        info.isCheckable = true
        info.isChecked = isChecked
    }

    private fun blend(off: Int, on: Int): Int =
        evaluator.evaluate(progress, context.color(off), context.color(on)) as Int

    private fun updateStateDescription() {
        ViewCompat.setStateDescription(this, if (isChecked) "开启" else "关闭")
    }
}
