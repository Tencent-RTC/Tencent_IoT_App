package com.tencent.iot.aiglasses.designsystem

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.view.View
import androidx.annotation.ColorRes
import com.tencent.iot.aiglasses.R
import kotlin.math.roundToInt

object Radius {
    const val CARD = 20f
    const val CAPSULE = 999f
}

object Spacing {
    const val SCREEN_HORIZONTAL = 22f
    const val SCREEN_TOP = 8f
    const val SCREEN_BOTTOM = 24f
    const val SECTION = 20f
}

enum class Elevation(val dp: Float, @ColorRes val shadow: Int) {
    NONE(0f, R.color.shadow_card),
    HERO(10f, R.color.hero_shadow),
    CARD(6f, R.color.shadow_card),
    RAISED(6f, R.color.shadow_raised),
    FLOATING(12f, R.color.shadow_floating)
}

fun Context.dp(value: Float): Float = value * resources.displayMetrics.density

fun Context.dpInt(value: Float): Int = dp(value).roundToInt()

fun Context.roundedDrawable(radius: Float, @ColorRes fill: Int, @ColorRes stroke: Int? = null): GradientDrawable =
    GradientDrawable().apply {
        shape = GradientDrawable.RECTANGLE
        cornerRadius = dp(radius)
        setColor(color(fill))
        if (stroke != null) setStroke(dpInt(1f), color(stroke))
    }

fun Context.ovalDrawable(@ColorRes fill: Int, @ColorRes stroke: Int? = null): GradientDrawable =
    GradientDrawable().apply {
        shape = GradientDrawable.OVAL
        setColor(color(fill))
        if (stroke != null) setStroke(dpInt(1f), color(stroke))
    }

fun Context.primaryGradient(): GradientDrawable =
    GradientDrawable(GradientDrawable.Orientation.TL_BR, intArrayOf(color(R.color.primary_gradient_start), color(R.color.primary_gradient_end)))

fun Context.pressable(content: Drawable?, mask: Drawable? = null): RippleDrawable =
    RippleDrawable(ColorStateList.valueOf(color(R.color.ripple)), content, mask)

fun View.elevation(level: Elevation) {
    if (context.isDarkTheme || level == Elevation.NONE) {
        elevation = 0f
        return
    }
    elevation = context.dp(level.dp)
    val shadow = context.color(level.shadow)
    outlineSpotShadowColor = shadow
    outlineAmbientShadowColor = shadow
}

fun View.surface(radius: Float = Radius.CARD, level: Elevation = Elevation.CARD, @ColorRes fill: Int = R.color.surface) {
    background = context.roundedDrawable(radius, fill, if (context.isDarkTheme) R.color.line else R.color.glass_border)
    elevation(level)
}
