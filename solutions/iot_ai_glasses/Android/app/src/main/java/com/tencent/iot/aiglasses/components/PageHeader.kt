package com.tencent.iot.aiglasses.components

import android.content.Context
import android.text.TextUtils
import android.util.AttributeSet
import android.util.TypedValue
import android.view.Gravity
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import com.tencent.iot.aiglasses.R
import com.tencent.iot.aiglasses.designsystem.AppIcon
import com.tencent.iot.aiglasses.designsystem.color
import com.tencent.iot.aiglasses.designsystem.dpInt
import kotlin.math.max

fun Context.backButton(description: String = "返回"): CircleIconButton = CircleIconButton(this).apply {
    style = CircleIconButton.Style.PLAIN
    setIcon(AppIcon.BACK)
    contentDescription = description
}

internal val Context.headerSize: Int
    get() = dpInt(40f)

fun Context.backButtonLayoutParams(): LinearLayout.LayoutParams =
    LinearLayout.LayoutParams(headerSize, headerSize)

class PageHeader @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : LinearLayout(context, attrs) {

    private val backButton = context.backButton()

    private val titleView = TextView(context).apply {
        setTextAppearance(R.style.TextAppearance_Suisheng_NavTitle)
        gravity = Gravity.CENTER
        maxLines = 1
        ellipsize = TextUtils.TruncateAt.END
        includeFontPadding = false
        isAccessibilityHeading = true
    }

    private val subtitleView = TextView(context).apply {
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
        setTextColor(context.color(R.color.text_secondary))
        gravity = Gravity.CENTER
        maxLines = 1
        ellipsize = TextUtils.TruncateAt.END
        includeFontPadding = false
        visibility = GONE
    }

    private val titleBox = LinearLayout(context).apply {
        orientation = VERTICAL
        gravity = Gravity.CENTER
        addView(titleView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))
        addView(subtitleView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))
    }

    val trailing = FrameLayout(context)

    var title: CharSequence
        get() = titleView.text
        set(value) {
            titleView.text = value
        }

    var subtitle: CharSequence?
        get() = subtitleView.text
        set(value) {
            subtitleView.text = value
            subtitleView.visibility = if (value.isNullOrEmpty()) GONE else VISIBLE
        }

    init {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        val size = context.headerSize
        minimumHeight = size
        clipChildren = false
        addView(backButton, context.backButtonLayoutParams())
        addView(titleBox, LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f).apply {
            marginStart = context.dpInt(TITLE_GAP)
            marginEnd = context.dpInt(TITLE_GAP)
        })
        trailing.minimumWidth = size
        addView(trailing, LayoutParams(LayoutParams.WRAP_CONTENT, size))
        context.obtainStyledAttributes(attrs, R.styleable.PageHeader).apply {
            title = getString(R.styleable.PageHeader_title).orEmpty()
            backButton.contentDescription = getString(R.styleable.PageHeader_backLabel) ?: "返回"
            recycle()
        }
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
        val gap = context.dpInt(TITLE_GAP)
        val offset = trailing.measuredWidth - backButton.measuredWidth
        val params = titleBox.layoutParams as LayoutParams
        val start = gap + max(offset, 0)
        val end = gap + max(-offset, 0)
        if (params.marginStart == start && params.marginEnd == end) return
        params.marginStart = start
        params.marginEnd = end
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
    }

    fun setOnBack(action: () -> Unit) {
        backButton.setOnClickListener { action() }
    }

    private companion object {
        const val TITLE_GAP = 10f
    }
}
