package com.tencent.iot.aiglasses.designsystem

import android.content.Context
import android.content.res.ColorStateList
import android.content.res.Configuration
import androidx.annotation.ColorInt
import androidx.annotation.ColorRes
import androidx.core.content.ContextCompat

@ColorInt
fun Context.color(@ColorRes id: Int): Int = ContextCompat.getColor(this, id)

fun Context.colorList(@ColorRes id: Int): ColorStateList = ColorStateList.valueOf(color(id))

val Context.isDarkTheme: Boolean
    get() = (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
