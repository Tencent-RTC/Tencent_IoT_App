package com.tencent.iot.aiglasses.features.translation

import android.content.Context
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.util.AttributeSet
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.PopupWindow
import android.widget.Space
import android.widget.TextView
import com.tencent.iot.aiglasses.R
import com.tencent.iot.aiglasses.designsystem.AppIcon
import com.tencent.iot.aiglasses.designsystem.color
import com.tencent.iot.aiglasses.designsystem.dp
import com.tencent.iot.aiglasses.designsystem.dpInt
import com.tencent.iot.aiglasses.designsystem.isDarkTheme
import com.tencent.iot.aiglasses.designsystem.pressable
import com.tencent.iot.aiglasses.designsystem.roundedDrawable
import com.tencent.iot.aiglasses.designsystem.setAppIcon
import com.tencent.iot.aiglasses.models.Language

enum class LanguageSide {
    SOURCE,
    TARGET
}

class LanguageTrigger @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : LinearLayout(context, attrs) {

    private val labelView = TextView(context).apply {
        setTextAppearance(R.style.TextAppearance_Suisheng_Caption)
        setTextColor(context.color(R.color.text_secondary))
        gravity = Gravity.CENTER
    }

    private val valueView = TextView(context).apply {
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 23f)
        typeface = Typeface.create(Typeface.DEFAULT, 500, false)
        letterSpacing = -0.017f
        setTextColor(context.color(R.color.text_primary))
        includeFontPadding = false
    }

    private val chevron = ImageView(context)

    var label: CharSequence = ""
        set(value) {
            field = value
            labelView.text = value
        }

    var boxed = false
        set(value) {
            field = value
            labelView.setTextSize(TypedValue.COMPLEX_UNIT_SP, if (value) 11f else 12f)
            valueView.setTextSize(TypedValue.COMPLEX_UNIT_SP, if (value) 16f else 23f)
            valueView.typeface = Typeface.create(Typeface.DEFAULT, if (value) 600 else 500, false)
            chevron.visibility = if (value) GONE else VISIBLE
            (valueView.parent as? View)?.let { (it.layoutParams as LayoutParams).topMargin = context.dpInt(if (value) 3f else 6f) }
            minimumHeight = if (value) context.dpInt(52f) else 0
            gravity = if (value) Gravity.CENTER else Gravity.CENTER_HORIZONTAL
            val v = context.dpInt(if (value) 8f else 12f)
            setPadding(context.dpInt(8f), v, context.dpInt(8f), v)
        }


    init {
        orientation = VERTICAL
        gravity = Gravity.CENTER_HORIZONTAL
        isClickable = true
        isFocusable = true
        setPadding(context.dpInt(8f), context.dpInt(12f), context.dpInt(8f), context.dpInt(12f))
        addView(labelView)
        addView(LinearLayout(context).apply {
            orientation = HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(valueView)
            addView(chevron, LayoutParams(context.dpInt(14f), context.dpInt(14f)).apply { marginStart = context.dpInt(7f) })
        }, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply { topMargin = context.dpInt(6f) })
        set(Language.ENGLISH, isOpen = false)
    }

    fun set(value: Language, isOpen: Boolean) {
        valueView.text = value.rawValue
        chevron.setAppIcon(AppIcon.CHEVRON_DOWN, if (isOpen) R.color.picker_selected_text else R.color.text_secondary)
        chevron.rotation = if (isOpen) 180f else 0f
        background = if (boxed) {
            valueView.setTextColor(context.color(if (isOpen) R.color.picker_selected_text else R.color.text_primary))
            context.pressable(
                context.roundedDrawable(14f, if (isOpen) R.color.picker_selected_background else R.color.lang_box_background),
                context.roundedDrawable(14f, R.color.surface)
            )
        } else {
            context.pressable(
                if (isOpen) context.roundedDrawable(14f, R.color.picker_trigger_open) else null,
                context.roundedDrawable(14f, R.color.surface)
            )
        }
        contentDescription = "$label，${value.rawValue}，选择语言${if (isOpen) "，已展开" else ""}"
    }
}

class LanguageMenu(
    context: Context,
    private val selection: Language,
    private val onSelect: (Language) -> Unit
) : LinearLayout(context) {
    init {
        orientation = VERTICAL
        val inset = context.dpInt(6f)
        setPadding(inset, inset, inset, inset)
        background = if (context.isDarkTheme) {
            context.roundedDrawable(16f, R.color.surface, R.color.line)
        } else {
            context.roundedDrawable(16f, R.color.sheet, R.color.glass_border)
        }
        elevation = context.dp(if (context.isDarkTheme) 16f else 14f)
        outlineSpotShadowColor = context.color(R.color.picker_menu_shadow)
        outlineAmbientShadowColor = context.color(R.color.picker_menu_shadow)
        Language.entries.forEachIndexed { index, language ->
            addView(row(language), LayoutParams(LayoutParams.MATCH_PARENT, context.dpInt(44f)).apply {
                if (index > 0) topMargin = context.dpInt(2f)
            })
        }
    }

    private fun row(language: Language): View {
        val selected = language == selection
        val tint = if (selected) R.color.picker_selected_text else R.color.text_primary
        return LinearLayout(context).apply {
            orientation = HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            val horizontal = context.dpInt(12f)
            setPadding(horizontal, 0, horizontal, 0)
            isClickable = true
            isFocusable = true
            isSelected = selected
            contentDescription = language.rawValue + if (selected) "，已选中" else ""
            background = context.pressable(
                if (selected) context.roundedDrawable(10f, R.color.picker_selected_background) else null,
                context.roundedDrawable(10f, R.color.surface)
            )
            setOnClickListener { onSelect(language) }
            addView(TextView(context).apply {
                text = language.rawValue
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                typeface = Typeface.create(Typeface.DEFAULT, if (selected) 500 else 400, false)
                setTextColor(context.color(tint))
            })
            addView(Space(context), LayoutParams(0, 0, 1f))
            if (selected) addView(ImageView(context).apply { setAppIcon(AppIcon.CHECK, tint) }, LayoutParams(context.dpInt(16f), context.dpInt(16f)))
        }
    }

    companion object {
        fun show(anchor: View, selection: Language, onDismiss: () -> Unit, onSelect: (Language) -> Unit): PopupWindow {
            val context = anchor.context
            lateinit var popup: PopupWindow
            val menu = LanguageMenu(context, selection) { language ->
                onSelect(language)
                popup.dismiss()
            }
            popup = PopupWindow(menu, context.dpInt(156f), LayoutParams.WRAP_CONTENT, true).apply {
                setBackgroundDrawable(ColorDrawable(android.graphics.Color.TRANSPARENT))
                elevation = context.dp(14f)
                isOutsideTouchable = true
                setOnDismissListener { onDismiss() }
                showAsDropDown(anchor, 0, context.dpInt(8f), Gravity.START)
            }
            return popup
        }
    }
}
