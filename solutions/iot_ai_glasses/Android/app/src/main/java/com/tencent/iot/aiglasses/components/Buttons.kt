package com.tencent.iot.aiglasses.components

import android.content.Context
import android.util.AttributeSet
import android.widget.ImageView
import androidx.appcompat.widget.AppCompatImageButton
import com.tencent.iot.aiglasses.R
import com.tencent.iot.aiglasses.designsystem.AppIcon
import com.tencent.iot.aiglasses.designsystem.Elevation
import com.tencent.iot.aiglasses.designsystem.colorList
import com.tencent.iot.aiglasses.designsystem.dpInt
import com.tencent.iot.aiglasses.designsystem.elevation
import com.tencent.iot.aiglasses.designsystem.isDarkTheme
import com.tencent.iot.aiglasses.designsystem.ovalDrawable
import com.tencent.iot.aiglasses.designsystem.pressable

class CircleIconButton @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : AppCompatImageButton(context, attrs, 0) {

    enum class Style {
        RAISED,
        PLAIN
    }

    var style: Style = Style.RAISED
        set(value) {
            field = value
            applyStyle()
        }

    init {
        scaleType = ImageView.ScaleType.FIT_CENTER
        imageTintList = context.colorList(R.color.text_primary)
        context.obtainStyledAttributes(attrs, R.styleable.CircleIconButton).apply {
            getResourceId(R.styleable.CircleIconButton_icon, 0).takeIf { it != 0 }?.let(::setImageResource)
            style = if (getInt(R.styleable.CircleIconButton_circleStyle, 0) == 1) Style.PLAIN else Style.RAISED
            recycle()
        }
        applyStyle()
    }

    fun setIcon(icon: AppIcon) {
        setImageResource(icon.res)
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val size = MeasureSpec.makeMeasureSpec(context.dpInt(40f), MeasureSpec.EXACTLY)
        super.onMeasure(size, size)
    }

    private fun applyStyle() {
        val inset = context.dpInt(10.5f)
        setPadding(inset, inset, inset, inset)
        if (!context.isDarkTheme) {
            background = context.pressable(context.ovalDrawable(R.color.glass_strong, R.color.glass_border))
            elevation(Elevation.RAISED)
        } else if (style == Style.RAISED) {
            background = context.pressable(context.ovalDrawable(R.color.surface, R.color.line))
            elevation(Elevation.RAISED)
        } else {
            background = context.pressable(null, context.ovalDrawable(R.color.surface))
            elevation(Elevation.NONE)
        }
    }
}

class ActionButton @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : android.widget.LinearLayout(context, attrs) {

    enum class Variant {
        PRIMARY,
        SECONDARY
    }

    private val iconView = ImageView(context).apply { importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO }
    private val label = android.widget.TextView(context).apply { includeFontPadding = false }
    private val variant: Variant
    private val radius: Float

    var text: CharSequence
        get() = label.text
        set(value) {
            label.text = value
            contentDescription = value
        }

    init {
        orientation = HORIZONTAL
        gravity = android.view.Gravity.CENTER
        isClickable = true
        isFocusable = true
        minimumHeight = context.dpInt(56f)
        val a = context.obtainStyledAttributes(attrs, R.styleable.ActionButton)
        variant = if (a.getInt(R.styleable.ActionButton_variant, 0) == 1) Variant.SECONDARY else Variant.PRIMARY
        radius = a.getDimension(R.styleable.ActionButton_cornerRadius, context.dpInt(if (variant == Variant.PRIMARY) 18f else 16f).toFloat()) / resources.displayMetrics.density
        val iconRes = a.getResourceId(R.styleable.ActionButton_icon, 0)
        val labelSize = a.getDimension(R.styleable.ActionButton_labelSize, context.dpInt(16f).toFloat())
        val weight = a.getInt(R.styleable.ActionButton_labelWeight, 600)
        text = a.getString(R.styleable.ActionButton_text).orEmpty()
        a.recycle()

        val tint = if (variant == Variant.PRIMARY) R.color.on_accent else R.color.text_primary
        label.setTextSize(android.util.TypedValue.COMPLEX_UNIT_PX, labelSize)
        label.typeface = android.graphics.Typeface.create(android.graphics.Typeface.DEFAULT, weight, false)
        label.letterSpacing = 0.02f
        label.setTextColor(context.colorList(tint))
        iconView.imageTintList = context.colorList(tint)
        if (iconRes != 0) iconView.setImageResource(iconRes)
        iconView.visibility = if (iconRes != 0) VISIBLE else GONE
        addView(iconView, LayoutParams(context.dpInt(20f), context.dpInt(20f)).apply { marginEnd = context.dpInt(10f) })
        addView(label)
        applyBackground()
    }

    fun setIcon(icon: AppIcon) {
        iconView.setImageResource(icon.res)
        iconView.visibility = VISIBLE
    }

    override fun setEnabled(enabled: Boolean) {
        super.setEnabled(enabled)
        alpha = if (enabled) 1f else 0.4f
        if (variant == Variant.PRIMARY && !context.isDarkTheme) elevation = if (enabled) context.dpInt(8f).toFloat() else 0f
    }

    override fun getAccessibilityClassName(): CharSequence = android.widget.Button::class.java.name

    private fun applyBackground() {
        val corner = context.dpInt(radius).toFloat()
        val shape = android.graphics.drawable.GradientDrawable().apply { cornerRadius = corner }
        when {
            variant == Variant.SECONDARY -> {
                shape.setColor(context.getColor(R.color.surface))
                shape.setStroke(context.dpInt(1f), context.getColor(if (context.isDarkTheme) R.color.line else R.color.glass_border))
                elevation(Elevation.RAISED)
            }
            context.isDarkTheme -> shape.setColor(context.getColor(R.color.accent))
            else -> {
                shape.orientation = android.graphics.drawable.GradientDrawable.Orientation.TL_BR
                shape.colors = intArrayOf(context.getColor(R.color.primary_gradient_start), context.getColor(R.color.primary_gradient_end))
                elevation = context.dpInt(8f).toFloat()
                outlineSpotShadowColor = context.getColor(R.color.primary_glow)
                outlineAmbientShadowColor = context.getColor(R.color.primary_glow)
            }
        }
        background = context.pressable(shape)
    }
}
