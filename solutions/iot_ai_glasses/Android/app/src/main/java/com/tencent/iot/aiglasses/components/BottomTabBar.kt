package com.tencent.iot.aiglasses.components

import android.content.Context
import android.util.AttributeSet
import android.view.Gravity
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import com.tencent.iot.aiglasses.R
import com.tencent.iot.aiglasses.app.AppTab
import com.tencent.iot.aiglasses.designsystem.Elevation
import com.tencent.iot.aiglasses.designsystem.Radius
import com.tencent.iot.aiglasses.designsystem.color
import com.tencent.iot.aiglasses.designsystem.dpInt
import com.tencent.iot.aiglasses.designsystem.isDarkTheme
import com.tencent.iot.aiglasses.designsystem.roundedDrawable
import com.tencent.iot.aiglasses.designsystem.setAppIcon
import com.tencent.iot.aiglasses.designsystem.surface

class BottomTabBar @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : LinearLayout(context, attrs) {

    var onSelect: ((AppTab) -> Unit)? = null

    var selection: AppTab = AppTab.HOME
        set(value) {
            field = value
            refresh()
        }

    private class Item(val root: LinearLayout, val icon: ImageView, val label: TextView)

    private val items: Map<AppTab, Item>

    init {
        orientation = HORIZONTAL
        val inset = context.dpInt(4f)
        setPadding(inset, inset, inset, inset)
        surface(Radius.CAPSULE, Elevation.FLOATING, if (context.isDarkTheme) R.color.surface else R.color.glass_strong)
        items = AppTab.entries.associateWith { tab ->
            val item = createItem(tab)
            addView(item.root, LayoutParams(0, LayoutParams.MATCH_PARENT, 1f).apply {
                marginStart = context.dpInt(2f)
                marginEnd = context.dpInt(2f)
            })
            item
        }
        refresh()
    }

    private fun createItem(tab: AppTab): Item {
        val icon = ImageView(context)
        val label = TextView(context).apply {
            setTextAppearance(R.style.TextAppearance_Suisheng_TabLabel)
            text = tab.title
            includeFontPadding = false
        }
        val root = LinearLayout(context).apply {
            orientation = VERTICAL
            gravity = Gravity.CENTER
            minimumHeight = context.dpInt(50f)
            contentDescription = tab.title
            isClickable = true
            isFocusable = true
            setOnClickListener { onSelect?.invoke(tab) }
            addView(icon, LayoutParams(context.dpInt(23f), context.dpInt(23f)))
            addView(label, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
                topMargin = context.dpInt(2f)
            })
        }
        return Item(root, icon, label)
    }

    private fun refresh() {
        items.forEach { (tab, item) ->
            val selected = tab == selection
            val tint = if (selected) R.color.tab_selected_foreground else R.color.text_secondary
            item.icon.setAppIcon(tab.icon, tint)
            item.label.setTextColor(context.color(tint))
            item.root.background = if (selected) context.roundedDrawable(Radius.CAPSULE, R.color.tab_selected_background) else null
            item.root.isSelected = selected
        }
    }
}
