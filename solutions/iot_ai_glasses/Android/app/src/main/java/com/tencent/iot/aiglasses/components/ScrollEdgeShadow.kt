package com.tencent.iot.aiglasses.components

import android.animation.ValueAnimator
import android.graphics.Rect
import android.graphics.drawable.GradientDrawable
import android.view.View
import android.view.ViewTreeObserver
import com.tencent.iot.aiglasses.designsystem.dpInt
import com.tencent.iot.aiglasses.designsystem.isDarkTheme

fun View.attachTopScrollShadow(host: View) {
    clipToSelfBounds()
    val color = if (context.isDarkTheme) 0x42FFFFFF else 0x521C1C28
    val shadow = GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, intArrayOf(color, 0)).apply { alpha = 0 }
    host.overlay.add(shadow)
    val height = context.dpInt(20f)
    val self = IntArray(2)
    val origin = IntArray(2)
    var shown = false
    var animator: ValueAnimator? = null

    fun place() {
        getLocationInWindow(self)
        host.getLocationInWindow(origin)
        val top = self[1] - origin[1]
        shadow.setBounds(0, top, host.width, top + height)
    }

    fun update() {
        val scrolled = isShown && canScrollVertically(-1)
        if (scrolled == shown) return
        shown = scrolled
        animator?.cancel()
        animator = ValueAnimator.ofInt(shadow.alpha, if (scrolled) 255 else 0).apply {
            duration = 200
            addUpdateListener { shadow.alpha = it.animatedValue as Int }
            start()
        }
    }

    val listener = ViewTreeObserver.OnScrollChangedListener { update() }
    addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
        place()
        update()
    }
    addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(v: View) = v.viewTreeObserver.addOnScrollChangedListener(listener)
        override fun onViewDetachedFromWindow(v: View) = v.viewTreeObserver.removeOnScrollChangedListener(listener)
    })
    if (isAttachedToWindow) viewTreeObserver.addOnScrollChangedListener(listener)
}

private fun View.clipToSelfBounds() {
    addOnLayoutChangeListener { v, _, _, _, _, _, _, _, _ ->
        clipBounds = if (v.width > 0 && v.height > 0) Rect(0, 0, v.width, v.height) else null
    }
}
