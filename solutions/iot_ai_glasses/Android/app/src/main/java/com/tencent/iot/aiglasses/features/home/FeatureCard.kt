package com.tencent.iot.aiglasses.features.home

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.util.TypedValue
import android.view.Gravity
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.graphics.ColorUtils
import com.tencent.iot.aiglasses.R
import com.tencent.iot.aiglasses.app.AppRoute
import com.tencent.iot.aiglasses.designsystem.AppIcon
import com.tencent.iot.aiglasses.designsystem.color
import com.tencent.iot.aiglasses.designsystem.dp
import com.tencent.iot.aiglasses.designsystem.dpInt
import com.tencent.iot.aiglasses.designsystem.isDarkTheme
import com.tencent.iot.aiglasses.designsystem.roundedDrawable
import com.tencent.iot.aiglasses.models.SessionKind

enum class Feature(
    val title: String,
    val subtitle: String,
    val route: AppRoute,
    val sessionKind: SessionKind?
) {
    LISTEN("实时翻译", "跨语言即时互译", AppRoute.Live(SessionKind.TRANSLATION), SessionKind.TRANSLATION),
    MEETING("会议转录", "每句话都不遗漏", AppRoute.Live(SessionKind.MEETING), SessionKind.MEETING),
    INTERPRET("双向传译", "面对面，自在聊", AppRoute.InterpretPrep, SessionKind.INTERPRET),
    CALL("语音通话", "用眼镜轻松接听", AppRoute.Calls, SessionKind.CALL),
    CHAT("AI 对话", "随时问一句", AppRoute.Chat, null);

    val icon: AppIcon
        get() = when (this) {
            LISTEN -> AppIcon.LANGUAGE
            MEETING -> AppIcon.MEETING
            INTERPRET -> AppIcon.INTERPRET
            CALL -> AppIcon.CALL_FEATURE
            CHAT -> AppIcon.CHAT_FEATURE
        }

    val iconTint: Pair<Int, Int>
        get() = when (this) {
            LISTEN -> R.color.icon_tint_purple to R.color.icon_bg_purple
            MEETING -> R.color.icon_tint_blue to R.color.icon_bg_blue
            INTERPRET -> R.color.icon_tint_green to R.color.icon_bg_green
            CALL -> R.color.icon_tint_green to R.color.icon_bg_green
            CHAT -> R.color.icon_tint_orange to R.color.icon_bg_orange
        }

    internal val tint: CardTint
        get() = when (this) {
            LISTEN -> CardTint(listOf(0xFFF0E4 to 0x432925, 0xFFDFC9 to 0x55352C, 0xFFC5A8 to 0x664134), 0x653D2E to 0xFFE4D2)
            MEETING -> CardTint(listOf(0xF1EDFF to 0x302C49, 0xE1DBFF to 0x3D3759, 0xC9C4F5 to 0x4A4269), 0x443966 to 0xECE6FF)
            INTERPRET -> CardTint(listOf(0xE8F7EF to 0x233E3A, 0xCDE9DD to 0x33524B), 0x355B50 to 0xDDF5ED)
            CALL -> CardTint(listOf(0xECF3FF to 0x29374B, 0xD4E5F7 to 0x3C536B), 0x395474 to 0xE2EDFF)
            CHAT -> CardTint(listOf(0xF4EDFC to 0x392E4A, 0xE4D9F5 to 0x514365), 0x5A4776 to 0xF0E5FF)
        }
}

internal class CardTint(val stops: List<Pair<Int, Int>>, val text: Pair<Int, Int>) {
    fun stops(dark: Boolean): IntArray = stops.map { opaque(if (dark) it.second else it.first) }.toIntArray()
    fun foreground(dark: Boolean): Int = opaque(if (dark) text.second else text.first)

    private fun opaque(rgb: Int) = rgb or 0xFF000000.toInt()
}

class FeatureCard(
    context: Context,
    val feature: Feature,
    private val compact: Boolean
) : FrameLayout(context) {

    private val dark = context.isDarkTheme
    private val iconTintRes = feature.iconTint.first
    private val iconBgRes = feature.iconTint.second

    init {
        val radius = context.dp(20f)
        background = if (dark) {
            GradientDrawable().apply {
                cornerRadius = radius
                orientation = GradientDrawable.Orientation.TL_BR
                colors = feature.tint.stops(dark)
            }
        } else {
            context.roundedDrawable(20f, R.color.surface_raised)
        }
        foreground = GradientDrawable().apply {
            cornerRadius = radius
            setStroke(context.dpInt(1f), white(if (dark) 0.1f else 0.88f))
        }
        clipToOutline = true
        if (dark) {
            elevation = context.dp(5f)
        } else {
            elevation = context.dp(10f)
            val shadow = context.color(R.color.hero_shadow)
            outlineSpotShadowColor = shadow
            outlineAmbientShadowColor = shadow
        }
        isClickable = true
        isFocusable = true
        contentDescription = "${feature.title}，${feature.subtitle}"

        val iconTile = ImageView(context).apply {
            setImageResource(feature.icon.res)
            setColorFilter(context.color(iconTintRes))
            background = context.roundedDrawable(12f, if (dark) R.color.white_alpha_12 else iconBgRes)
            val inset = context.dpInt(11f)
            setPadding(inset, inset, inset, inset)
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        }

        val copy = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
            addView(TextView(context).apply {
                text = feature.title
                setTextSize(TypedValue.COMPLEX_UNIT_SP, if (compact) 14f else 15f)
                typeface = Typeface.create(Typeface.DEFAULT, 600, false)
                setTextColor(if (dark) feature.tint.foreground(true) else context.color(R.color.text_primary))
                maxLines = 1
                includeFontPadding = false
            })
            addView(TextView(context).apply {
                text = feature.subtitle
                setTextSize(TypedValue.COMPLEX_UNIT_SP, if (compact) 10f else 11f)
                setTextColor(
                    if (dark) ColorUtils.setAlphaComponent(feature.tint.foreground(true), (0.7f * 255).toInt())
                    else context.color(R.color.text_secondary)
                )
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
                includeFontPadding = false
            }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
                topMargin = context.dpInt(2f)
            })
        }

        val row = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(iconTile, LinearLayout.LayoutParams(context.dpInt(44f), context.dpInt(44f)).apply {
                marginEnd = context.dpInt(12f)
            })
            addView(copy, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        }

        val pad = context.dpInt(if (compact) 12f else 14f)
        addView(row, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT, Gravity.CENTER_VERTICAL).apply {
            setMargins(pad, 0, pad, 0)
        })
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val height = context.dpInt(84f)
        super.onMeasure(widthMeasureSpec, MeasureSpec.makeMeasureSpec(height, MeasureSpec.EXACTLY))
    }

    override fun setPressed(pressed: Boolean) {
        super.setPressed(pressed)
        animate().scaleX(if (pressed) 0.97f else 1f).scaleY(if (pressed) 0.97f else 1f).setDuration(150).start()
    }

    private fun white(alpha: Float) = ColorUtils.setAlphaComponent(Color.WHITE, (alpha * 255).toInt())
}
