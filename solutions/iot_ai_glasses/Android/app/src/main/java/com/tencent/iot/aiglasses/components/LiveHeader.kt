package com.tencent.iot.aiglasses.components

import android.content.Context
import android.text.TextUtils
import android.util.AttributeSet
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.Space
import android.widget.TextView
import androidx.core.view.isVisible
import com.tencent.iot.aiglasses.R
import com.tencent.iot.aiglasses.designsystem.AppIcon
import com.tencent.iot.aiglasses.designsystem.color
import com.tencent.iot.aiglasses.designsystem.dp
import com.tencent.iot.aiglasses.designsystem.dpInt
import com.tencent.iot.aiglasses.designsystem.isDarkTheme
import com.tencent.iot.aiglasses.designsystem.ovalDrawable
import com.tencent.iot.aiglasses.designsystem.pressable
import com.tencent.iot.aiglasses.designsystem.roundedDrawable
import com.tencent.iot.aiglasses.designsystem.surface
import com.tencent.iot.aiglasses.models.Clock

class LiveHeader @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : LinearLayout(context, attrs) {

    private val backButton = context.backButton("返回首页，保留当前会话")

    private val titleView = TextView(context).apply {
        setTextAppearance(R.style.TextAppearance_Suisheng_NavTitle)
        gravity = Gravity.CENTER
        maxLines = 1
        ellipsize = TextUtils.TruncateAt.END
        isAccessibilityHeading = true
    }

    var title: CharSequence
        get() = titleView.text
        set(value) {
            titleView.text = value
        }

    init {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        val size = context.headerSize
        minimumHeight = size
        clipChildren = false
        addView(backButton, context.backButtonLayoutParams())
        addView(titleView, LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f).apply {
            marginStart = context.dpInt(12f)
            marginEnd = context.dpInt(12f)
        })
        addView(Space(context), LayoutParams(size, size))
        context.obtainStyledAttributes(attrs, R.styleable.PageHeader).apply {
            title = getString(R.styleable.PageHeader_title).orEmpty()
            recycle()
        }
    }

    fun setOnBack(action: () -> Unit) {
        backButton.setOnClickListener { action() }
    }
}

class InlineHint @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : LinearLayout(context, attrs) {

    enum class Tone {
        ERROR,
        WARNING
    }

    private val label = TextView(context).apply {
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
        setLineSpacing(context.dp(3f), 1f)
    }

    val action: Button = Button(context, null, 0, R.style.Widget_Suisheng_Button).apply {
        setTextAppearance(R.style.TextAppearance_Suisheng_Caption)
        setTextColor(context.color(R.color.caption_error_text))
        minHeight = context.dpInt(36f)
        val horizontal = context.dpInt(12f)
        setPadding(horizontal, 0, horizontal, 0)
        background = context.pressable(context.roundedDrawable(12f, R.color.surface_raised, R.color.line))
        isVisible = false
    }

    init {
        orientation = VERTICAL
        setPadding(context.dpInt(12f), context.dpInt(10f), context.dpInt(12f), context.dpInt(10f))
        addView(label, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))
        addView(action, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply { topMargin = context.dpInt(8f) })
    }

    fun set(tone: Tone, text: String, actionTitle: String? = null, onAction: (() -> Unit)? = null) {
        val error = tone == Tone.ERROR
        label.text = text
        label.setTextColor(context.color(if (error) R.color.caption_error_text else R.color.caption_warn_text))
        background = context.roundedDrawable(
            10f,
            if (error) R.color.caption_error_background else R.color.caption_warn_background,
            if (error) R.color.caption_error_border else R.color.caption_warn_border
        )
        action.isVisible = actionTitle != null
        action.text = actionTitle
        action.setOnClickListener { onAction?.invoke() }
    }
}
