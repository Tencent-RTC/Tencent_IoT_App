package com.tencent.iot.aiglasses.components

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.util.AttributeSet
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.annotation.ColorRes
import com.tencent.iot.aiglasses.R
import com.tencent.iot.aiglasses.designsystem.AppIcon
import com.tencent.iot.aiglasses.designsystem.Radius
import com.tencent.iot.aiglasses.designsystem.color
import com.tencent.iot.aiglasses.designsystem.dp
import com.tencent.iot.aiglasses.designsystem.dpInt
import com.tencent.iot.aiglasses.designsystem.isDarkTheme
import com.tencent.iot.aiglasses.designsystem.pressable
import com.tencent.iot.aiglasses.designsystem.roundedDrawable
import com.tencent.iot.aiglasses.designsystem.setAppIcon

class ProductHero @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : FrameLayout(context, attrs) {

    private val connection = ConnectionBadge(context)
    private val battery = BatteryBadge(context)

    init {
        val radius = if (context.isDarkTheme) 16f else 26f
        background = context.roundedDrawable(radius, R.color.hero_background)
        foreground = context.pressable(null, context.roundedDrawable(radius, R.color.hero_background))
        clipToOutline = true
        elevation = context.dp(10f)
        outlineSpotShadowColor = context.color(R.color.hero_shadow)
        outlineAmbientShadowColor = context.color(R.color.hero_shadow)
        addView(ImageView(context).apply {
            setImageResource(R.drawable.product)
            scaleType = ImageView.ScaleType.CENTER_CROP
            contentDescription = if (context.isDarkTheme) "石墨黑AI眼镜外观" else "AI眼镜外观"
        }, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        val margin = context.dpInt(10f)
        addView(connection, LayoutParams(LayoutParams.WRAP_CONTENT, context.dpInt(25f), Gravity.TOP or Gravity.START).apply { setMargins(margin, margin, margin, margin) })
        addView(battery, LayoutParams(LayoutParams.WRAP_CONTENT, context.dpInt(25f), Gravity.TOP or Gravity.END).apply { setMargins(margin, margin, margin, margin) })
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, MeasureSpec.makeMeasureSpec(context.dpInt(176f), MeasureSpec.EXACTLY))
    }

    fun set(isConnected: Boolean, batteryLevel: Int?) {
        connection.set(isConnected)
        battery.set(batteryLevel)
    }
}

open class GlassBadge(context: Context) : LinearLayout(context) {
    protected val label = TextView(context).apply {
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 9.5f)
        letterSpacing = 0.02f
        fontFeatureSettings = "tnum"
        includeFontPadding = false
    }

    init {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        val horizontal = context.dpInt(7f)
        setPadding(horizontal, 0, horizontal, 0)
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        if (!context.isDarkTheme) {
            elevation = context.dp(6f)
            outlineSpotShadowColor = context.color(R.color.badge_shadow)
            outlineAmbientShadowColor = context.color(R.color.badge_shadow)
        }
    }

    protected fun style(@ColorRes background: Int, @ColorRes border: Int, @ColorRes foreground: Int) {
        this.background = context.roundedDrawable(Radius.CAPSULE, background, border)
        label.setTextColor(context.color(foreground))
    }
}

class ConnectionBadge(context: Context) : GlassBadge(context) {
    private val icon = ImageView(context)

    init {
        addView(icon, LayoutParams(context.dpInt(11f), context.dpInt(11f)))
        addView(label, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply { marginStart = context.dpInt(4f) })
        set(true)
    }

    fun set(isConnected: Boolean) {
        val foreground = if (isConnected) R.color.badge_on_text else R.color.badge_off_text
        if (isConnected) {
            style(R.color.badge_on_background, R.color.badge_on_border, foreground)
        } else {
            style(R.color.badge_off_background, R.color.badge_off_border, foreground)
        }
        icon.setAppIcon(AppIcon.SIGNAL, foreground)
        label.text = if (isConnected) "已连接" else "未连接"
        contentDescription = if (isConnected) "眼镜已连接" else "眼镜未连接"
    }
}

class BatteryBadge(context: Context) : GlassBadge(context) {
    private val glyph = BatteryGlyph(context)

    init {
        addView(glyph, LayoutParams(context.dpInt(11f), context.dpInt(11f)))
        addView(label, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply { marginStart = context.dpInt(4f) })
        set(null)
    }

    fun set(level: Int?) {
        val foreground = if (level == null) R.color.badge_off_text else R.color.badge_neutral_text
        if (level == null) {
            style(R.color.badge_off_background, R.color.badge_off_border, foreground)
        } else {
            style(R.color.badge_neutral_background, R.color.badge_neutral_border, foreground)
        }
        glyph.set(level, context.color(foreground))
        label.text = level?.let { "$it%" } ?: "—"
        contentDescription = level?.let { "眼镜电量 $it%" } ?: "眼镜电量未知"
    }
}

private class BatteryGlyph(context: Context) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val rect = RectF()
    private var level: Int? = null

    fun set(level: Int?, color: Int) {
        this.level = level
        paint.color = color
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        val bodyWidth = context.dp(8.4f)
        val bodyHeight = context.dp(4.4f)
        val nubWidth = context.dp(0.9f)
        val gap = context.dp(0.6f)
        val left = (width - bodyWidth - gap - nubWidth) / 2
        val top = (height - bodyHeight) / 2
        val stroke = context.dp(0.9f)

        paint.style = Paint.Style.STROKE
        paint.strokeWidth = stroke
        rect.set(left + stroke / 2, top + stroke / 2, left + bodyWidth - stroke / 2, top + bodyHeight - stroke / 2)
        canvas.drawRoundRect(rect, context.dp(1.1f), context.dp(1.1f), paint)

        paint.style = Paint.Style.FILL
        val fill = context.dp(5.4f) * (level ?: 0) / 100f
        val fillHeight = context.dp(2.2f)
        val fillLeft = left + context.dp(1.5f)
        val fillTop = top + (bodyHeight - fillHeight) / 2
        rect.set(fillLeft, fillTop, fillLeft + fill, fillTop + fillHeight)
        canvas.drawRoundRect(rect, context.dp(0.5f), context.dp(0.5f), paint)

        val nubHeight = context.dp(1.8f)
        val nubLeft = left + bodyWidth + gap
        rect.set(nubLeft, (height - nubHeight) / 2, nubLeft + nubWidth, (height + nubHeight) / 2)
        canvas.drawRoundRect(rect, nubWidth / 2, nubWidth / 2, paint)
    }
}
