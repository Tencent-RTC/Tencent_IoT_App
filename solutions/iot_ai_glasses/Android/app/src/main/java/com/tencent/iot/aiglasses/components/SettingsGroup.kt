package com.tencent.iot.aiglasses.components

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.text.TextUtils
import android.util.AttributeSet
import android.view.Gravity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.Space
import android.widget.TextView
import androidx.annotation.ColorRes
import com.tencent.iot.aiglasses.R
import com.tencent.iot.aiglasses.designsystem.color
import com.tencent.iot.aiglasses.designsystem.colorList
import com.tencent.iot.aiglasses.designsystem.dp
import com.tencent.iot.aiglasses.designsystem.dpInt
import com.tencent.iot.aiglasses.designsystem.isDarkTheme
import com.tencent.iot.aiglasses.designsystem.ovalDrawable
import com.tencent.iot.aiglasses.designsystem.surface

class SettingsGroup @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : LinearLayout(context, attrs) {
    init {
        orientation = VERTICAL
        val horizontal = context.dpInt(18f)
        setPadding(horizontal, 0, horizontal, 0)
        surface()
    }
}

class SettingRow @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : LinearLayout(context, attrs) {

    private val iconView = ImageView(context).apply {
        imageTintList = context.colorList(R.color.text_secondary)
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    private val titleView = TextView(context).apply {
        setTextAppearance(R.style.TextAppearance_Suisheng_Callout)
        maxLines = 1
        ellipsize = TextUtils.TruncateAt.END
    }

    private val dividerPaint = Paint().apply { color = context.color(R.color.separator) }

    var showsDivider = false
        set(value) {
            field = value
            invalidate()
        }

    var title: CharSequence
        get() = titleView.text
        set(value) {
            titleView.text = value
        }

    init {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        minimumHeight = context.dpInt(68f)
        setWillNotDraw(false)
        addView(iconView, LayoutParams(context.dpInt(21f), context.dpInt(21f)))
        addView(titleView, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
            marginStart = context.dpInt(12f)
        })
        addView(Space(context), LayoutParams(0, 0, 1f).apply { marginStart = context.dpInt(12f) })
        context.obtainStyledAttributes(attrs, R.styleable.SettingRow).apply {
            getResourceId(R.styleable.SettingRow_icon, 0).takeIf { it != 0 }?.let(iconView::setImageResource)
            titleView.text = getString(R.styleable.SettingRow_title).orEmpty()
            showsDivider = getBoolean(R.styleable.SettingRow_showsDivider, false)
            recycle()
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (showsDivider) canvas.drawRect(0f, 0f, width.toFloat(), context.dp(1f), dividerPaint)
    }
}

class StatusDot @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : LinearLayout(context, attrs) {

    private val dot = View(context)
    private val label = TextView(context).apply {
        setTextAppearance(R.style.TextAppearance_Suisheng_Caption)
    }

    init {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        addView(dot, LayoutParams(context.dpInt(5f), context.dpInt(5f)))
        addView(label, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
            marginStart = context.dpInt(6f)
        })
        context.obtainStyledAttributes(attrs, R.styleable.StatusDot).apply {
            label.text = getString(R.styleable.StatusDot_text).orEmpty()
            recycle()
        }
        setColor(R.color.success)
    }

    fun set(text: CharSequence, @ColorRes colorRes: Int = R.color.success) {
        label.text = text
        setColor(colorRes)
    }

    private fun setColor(@ColorRes colorRes: Int) {
        dot.background = context.ovalDrawable(if (colorRes == R.color.success && !context.isDarkTheme) R.color.success_dot else colorRes)
        label.setTextColor(context.color(colorRes))
    }
}
