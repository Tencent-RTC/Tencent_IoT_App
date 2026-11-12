package com.tencent.iot.aiglasses.components

import android.content.Context
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.text.TextUtils
import android.util.AttributeSet
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.annotation.ColorRes
import androidx.annotation.DrawableRes
import androidx.core.view.isVisible
import com.tencent.iot.aiglasses.R
import com.tencent.iot.aiglasses.designsystem.color
import com.tencent.iot.aiglasses.designsystem.dp
import com.tencent.iot.aiglasses.designsystem.dpInt
import com.tencent.iot.aiglasses.designsystem.isDarkTheme
import com.tencent.iot.aiglasses.designsystem.ovalDrawable
import com.tencent.iot.aiglasses.designsystem.pressable
import com.tencent.iot.aiglasses.designsystem.roundedDrawable

class SessionHeader @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : LinearLayout(context, attrs) {

    private val backButton = context.backButton("返回首页，保留当前会话")

    private val titleView = TextView(context).apply {
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
        typeface = Typeface.create(Typeface.DEFAULT, 600, false)
        setTextColor(context.color(R.color.text_primary))
        gravity = Gravity.CENTER
        maxLines = 1
        ellipsize = TextUtils.TruncateAt.END
        isAccessibilityHeading = true
        includeFontPadding = false
    }

    private val statusDot = View(context)

    private val statusText = TextView(context).apply {
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
        setTextColor(context.color(R.color.text_secondary))
        includeFontPadding = false
    }

    private val statusRow = LinearLayout(context).apply {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        addView(statusDot, LayoutParams(context.dpInt(5f), context.dpInt(5f)).apply { marginEnd = context.dpInt(5f) })
        addView(statusText)
    }

    private val settingsButton = CircleIconButton(context).apply {
        style = CircleIconButton.Style.PLAIN
        setImageResource(R.drawable.mi_settings)
        contentDescription = "设置"
        visibility = INVISIBLE
    }

    var title: CharSequence
        get() = titleView.text
        set(value) {
            titleView.text = value
        }

    var showsStatus = true
        set(value) {
            field = value
            statusRow.isVisible = value
        }

    init {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        minimumHeight = context.dpInt(44f)
        clipChildren = false
        addView(backButton, context.backButtonLayoutParams())
        addView(LinearLayout(context).apply {
            orientation = VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            addView(titleView)
            addView(statusRow, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply { topMargin = context.dpInt(3f) })
        }, LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f).apply {
            marginStart = context.dpInt(10f)
            marginEnd = context.dpInt(10f)
        })
        addView(settingsButton, context.backButtonLayoutParams())
        context.obtainStyledAttributes(attrs, R.styleable.PageHeader).apply {
            title = getString(R.styleable.PageHeader_title).orEmpty()
            recycle()
        }
        setConnected(true)
    }

    fun setOnBack(action: () -> Unit) {
        backButton.setOnClickListener { action() }
    }

    fun setBackLabel(label: String) {
        backButton.contentDescription = label
    }

    fun setOnSettings(action: (() -> Unit)?) {
        settingsButton.visibility = if (action == null) INVISIBLE else VISIBLE
        settingsButton.setOnClickListener { action?.invoke() }
    }

    fun setConnected(connected: Boolean) {
        statusDot.background = context.ovalDrawable(if (connected) R.color.success else R.color.text_secondary)
        statusText.text = if (connected) "AI 眼镜已连接" else "眼镜未连接"
        statusRow.contentDescription = statusText.text
    }
}

class LiveControlBar @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : LinearLayout(context, attrs) {

    val leading = circle()
    val trailing = circle()

    private val pillIcon = ImageView(context).apply {
        setColorFilter(context.color(R.color.on_accent))
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    private val pillText = TextView(context).apply {
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
        typeface = Typeface.create(Typeface.DEFAULT, 500, false)
        setTextColor(context.color(R.color.on_accent))
        fontFeatureSettings = "tnum"
        maxLines = 1
        ellipsize = TextUtils.TruncateAt.END
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    val pill = LinearLayout(context).apply {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER
        isClickable = true
        isFocusable = true
        background = context.pressable(GradientDrawable().apply {
            cornerRadius = context.dp(999f)
            setColor(context.color(R.color.accent))
        })
        addView(pillIcon, LayoutParams(context.dpInt(16f), context.dpInt(16f)).apply { marginEnd = context.dpInt(8f) })
        addView(pillText)
    }

    init {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        val pad = context.dpInt(7f)
        setPadding(pad, pad, pad, pad)
        background = context.roundedDrawable(30f, R.color.live_bar_background, if (context.isDarkTheme) R.color.line else null)
        elevation = if (context.isDarkTheme) 0f else context.dp(6f)
        outlineSpotShadowColor = context.color(R.color.shadow_floating)
        outlineAmbientShadowColor = context.color(R.color.shadow_floating)
        val size = context.dpInt(48f)
        addView(leading, LayoutParams(size, size))
        addView(pill, LayoutParams(0, size, 1f).apply {
            marginStart = context.dpInt(10f)
            marginEnd = context.dpInt(10f)
        })
        addView(trailing, LayoutParams(size, size))
    }

    fun setPill(@DrawableRes icon: Int, text: String, description: String, enabled: Boolean = true) {
        pillIcon.setImageResource(icon)
        pillText.text = text
        pill.contentDescription = description
        pill.isEnabled = enabled
        pill.alpha = if (enabled) 1f else 0.5f
    }

    fun setButton(button: ImageButton, @DrawableRes icon: Int, description: String, enabled: Boolean = true, @ColorRes tint: Int = R.color.text_primary) {
        button.setImageResource(icon)
        button.setColorFilter(context.color(tint))
        button.contentDescription = description
        button.isEnabled = enabled
        button.alpha = if (enabled) 1f else 0.4f
    }

    private fun circle() = ImageButton(context).apply {
        scaleType = ImageView.ScaleType.FIT_CENTER
        val inset = context.dpInt(14f)
        setPadding(inset, inset, inset, inset)
        background = context.pressable(context.ovalDrawable(R.color.live_bar_button_background))
    }
}
