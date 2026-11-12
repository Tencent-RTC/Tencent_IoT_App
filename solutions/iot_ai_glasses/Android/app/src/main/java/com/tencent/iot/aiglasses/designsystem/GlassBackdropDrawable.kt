package com.tencent.iot.aiglasses.designsystem

import android.content.Context
import android.graphics.Canvas
import android.graphics.ColorFilter
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.Shader
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.Drawable
import com.tencent.iot.aiglasses.R

class GlassBackdropDrawable : Drawable() {

    private val base = Paint()
    private var insetTop = 0
    private var insetBottom = 0

    fun setInsets(top: Int, bottom: Int) {
        if (top == insetTop && bottom == insetBottom) return
        insetTop = top
        insetBottom = bottom
        onBoundsChange(bounds)
        invalidateSelf()
    }

    override fun onBoundsChange(bounds: Rect) {
        val height = bounds.height().toFloat()
        if (bounds.width() <= 0 || height <= 0) return
        base.shader = LinearGradient(0f, bounds.top.toFloat(), 0f, bounds.top + height, BASE_COLORS, BASE_STOPS, Shader.TileMode.CLAMP)
    }

    override fun draw(canvas: Canvas) {
        canvas.drawRect(bounds, base)
    }

    override fun setAlpha(alpha: Int) = Unit

    override fun setColorFilter(colorFilter: ColorFilter?) = Unit

    @Deprecated("Deprecated in Java")
    override fun getOpacity(): Int = PixelFormat.OPAQUE

    private companion object {
        val BASE_COLORS = intArrayOf(0xFFFCE4D6.toInt(), 0xFFF3E9E6.toInt(), 0xFFEEEEF3.toInt())
        val BASE_STOPS = floatArrayOf(0f, 0.1f, 0.2f)
    }
}

fun Context.pageBackground(): Drawable =
    if (isDarkTheme) ColorDrawable(color(R.color.background)) else GlassBackdropDrawable()
