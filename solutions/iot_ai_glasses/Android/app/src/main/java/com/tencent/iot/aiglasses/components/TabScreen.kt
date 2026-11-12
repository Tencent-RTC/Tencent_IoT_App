package com.tencent.iot.aiglasses.components

import android.content.Context
import android.util.AttributeSet
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.Space
import android.widget.TextView
import androidx.core.view.isVisible
import androidx.core.widget.NestedScrollView
import com.tencent.iot.aiglasses.R
import com.tencent.iot.aiglasses.designsystem.Spacing
import com.tencent.iot.aiglasses.designsystem.color
import com.tencent.iot.aiglasses.designsystem.dpInt
import com.tencent.iot.aiglasses.designsystem.pageBackground

class TabScreen @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : NestedScrollView(context, attrs) {

    private val content = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        clipChildren = false
        clipToPadding = false
    }

    private val spacing: Int

    init {
        val a = context.obtainStyledAttributes(attrs, R.styleable.TabScreen)
        spacing = a.getDimensionPixelSize(R.styleable.TabScreen_spacing, context.dpInt(Spacing.SECTION))
        val reservesTabBar = a.getBoolean(R.styleable.TabScreen_reservesTabBar, true)
        a.recycle()
        isFillViewport = true
        isVerticalScrollBarEnabled = false
        clipToPadding = false
        overScrollMode = OVER_SCROLL_IF_CONTENT_SCROLLS
        background = context.pageBackground()
        val horizontal = context.dpInt(Spacing.SCREEN_HORIZONTAL)
        val bottom = context.dpInt(Spacing.SCREEN_BOTTOM) +
            if (reservesTabBar) resources.getDimensionPixelSize(R.dimen.bottom_tab_bar_reserved) else 0
        content.setPadding(horizontal, context.dpInt(Spacing.SCREEN_TOP), horizontal, bottom)
        super.addView(content, -1, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))
    }

    override fun addView(child: View) = addContent(child, null)

    override fun addView(child: View, index: Int) = addContent(child, null)

    override fun addView(child: View, params: ViewGroup.LayoutParams) = addContent(child, params)

    override fun addView(child: View, index: Int, params: ViewGroup.LayoutParams) {
        if (child === content) super.addView(child, index, params) else addContent(child, params)
    }

    private fun addContent(child: View, params: ViewGroup.LayoutParams?) {
        val lp = when (params) {
            null -> LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            is MarginLayoutParams -> LinearLayout.LayoutParams(params)
            else -> LinearLayout.LayoutParams(params)
        }
        if (content.childCount > 0) lp.topMargin += spacing
        content.addView(child, lp)
    }
}

class ScreenTitle @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : LinearLayout(context, attrs) {

    private val titleView = TextView(context).apply {
        setTextAppearance(R.style.TextAppearance_Suisheng_PageTitle)
        isAccessibilityHeading = true
    }

    private val trailingView = TextView(context).apply {
        setTextAppearance(R.style.TextAppearance_Suisheng_Caption)
        setTextColor(context.color(R.color.text_secondary))
    }

    var title: CharSequence
        get() = titleView.text
        set(value) {
            titleView.text = value
        }

    var trailingText: CharSequence?
        get() = trailingView.text
        set(value) {
            trailingView.text = value
            trailingView.isVisible = !value.isNullOrEmpty()
        }

    init {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        minimumHeight = context.dpInt(44f)
        addView(titleView, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT))
        addView(Space(context), LayoutParams(0, 0, 1f))
        addView(trailingView, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT))
        context.obtainStyledAttributes(attrs, R.styleable.ScreenTitle).apply {
            title = getString(R.styleable.ScreenTitle_title).orEmpty()
            trailingText = getString(R.styleable.ScreenTitle_trailingText)
            recycle()
        }
    }
}
