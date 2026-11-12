package com.tencent.iot.aiglasses.features.meeting

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.util.TypedValue
import android.view.Gravity
import android.widget.LinearLayout
import android.widget.Space
import android.widget.TextView
import androidx.annotation.ColorInt
import androidx.core.view.isVisible
import com.tencent.iot.aiglasses.R
import com.tencent.iot.aiglasses.designsystem.color
import com.tencent.iot.aiglasses.designsystem.dp
import com.tencent.iot.aiglasses.designsystem.dpInt
import com.tencent.iot.aiglasses.designsystem.isDarkTheme
import com.tencent.iot.aiglasses.designsystem.roundedDrawable
import com.tencent.iot.aiglasses.models.Clock
import com.tencent.iot.aiglasses.models.TranscriptLine

class SpeakerTonePalette(@ColorInt val text: Int, @ColorInt val border: Int, @ColorInt val background: Int) {
    companion object {
        private class Tone(val lightText: Int, val dark: Int, val lightBorder: Int, val lightBorderAlpha: Float, val lightBackgroundAlpha: Float)

        private val tones = listOf(
            Tone(0x4D6F2A, 0xD2EDAD, 0x7A9C3C, 0.45f, 0.35f),
            Tone(0x3D6A99, 0xA9CBE8, 0x5E85B0, 0.45f, 0.30f),
            Tone(0x9A7425, 0xE8CFA9, 0xBA9858, 0.45f, 0.30f),
            Tone(0xA94A68, 0xE8A9BD, 0xC4718B, 0.45f, 0.30f),
            Tone(0x6B4AA0, 0xC4A9E8, 0x8F71BF, 0.45f, 0.30f)
        )

        fun tone(context: Context, index: Int): SpeakerTonePalette {
            val tone = tones[((index % 5) + 5) % 5]
            return if (context.isDarkTheme) {
                SpeakerTonePalette(rgb(tone.dark), rgb(tone.dark, 0.38f), rgb(tone.dark, 0.10f))
            } else {
                SpeakerTonePalette(rgb(tone.lightText), rgb(tone.lightBorder, tone.lightBorderAlpha), rgb(tone.dark, tone.lightBackgroundAlpha))
            }
        }

        private fun rgb(value: Int, alpha: Float = 1f): Int =
            Color.argb((alpha * 255).toInt(), (value shr 16) and 0xFF, (value shr 8) and 0xFF, value and 0xFF)
    }
}

class SpeakerTag(context: Context) : androidx.appcompat.widget.AppCompatTextView(context) {
    init {
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
        typeface = Typeface.create(Typeface.DEFAULT, 500, false)
        letterSpacing = 0.02f
        includeFontPadding = false
        gravity = Gravity.CENTER
        setPadding(context.dpInt(9f), context.dpInt(3f), context.dpInt(9f), context.dpInt(3f))
    }

    fun set(label: String, tone: SpeakerTonePalette) {
        text = label
        setTextColor(tone.text)
        background = GradientDrawable().apply {
            cornerRadius = context.dp(999f)
            setColor(tone.background)
            setStroke(context.dpInt(1f), tone.border)
        }
        contentDescription = "发言人：$label"
    }
}

class MeetingCard(context: Context) : LinearLayout(context) {

    private val dot = android.view.View(context)
    private val name = TextView(context).apply {
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
        typeface = Typeface.create(Typeface.DEFAULT, 600, false)
        setTextColor(context.color(R.color.caption_text))
        includeFontPadding = false
    }
    private val time = TextView(context).apply {
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
        fontFeatureSettings = "tnum"
        includeFontPadding = false
    }
    private val body = TextView(context).apply {
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
        setLineSpacing(context.dp(5f), 1f)
        setTextColor(context.color(R.color.caption_text))
    }

    init {
        orientation = VERTICAL
        setPadding(context.dpInt(16f), context.dpInt(14f), context.dpInt(16f), context.dpInt(14f))
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        addView(LinearLayout(context).apply {
            orientation = HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
            addView(dot, LayoutParams(context.dpInt(7f), context.dpInt(7f)).apply { marginEnd = context.dpInt(6f) })
            addView(name, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply { marginEnd = context.dpInt(6f) })
            addView(time)
            addView(Space(context), LayoutParams(0, 0, 1f))
        }, LayoutParams(LayoutParams.MATCH_PARENT, context.dpInt(20f)).apply { bottomMargin = context.dpInt(6f) })
        addView(body.apply { importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO })
    }

    fun set(index: Int, line: TranscriptLine, isLatest: Boolean, speakerIndex: Int, isSpeaking: Boolean = false) {
        val label = line.speakerLabel ?: "发言人"
        dot.background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(DOTS[((speakerIndex % DOTS.size) + DOTS.size) % DOTS.size])
        }
        name.text = label
        time.text = if (isSpeaking) "正在说话…" else Clock.text(line.time)
        time.typeface = Typeface.create(Typeface.DEFAULT, if (isSpeaking) 500 else 400, false)
        time.setTextColor(context.color(if (isSpeaking) R.color.caption_latest_active_tag else R.color.caption_time))
        body.text = line.original
        background = context.roundedDrawable(
            18f,
            if (isSpeaking) R.color.caption_latest_active_card else R.color.caption_card,
            if (isSpeaking) R.color.caption_latest_active_border else R.color.caption_border
        )
        contentDescription = "第 ${index + 1} 段，$label，${line.original}" + if (isSpeaking) "，正在说话" else if (isLatest) "，最新" else ""
    }

    private companion object {
        val DOTS = intArrayOf(0xFFF2762E.toInt(), 0xFF2F6BD8.toInt(), 0xFF1F8A5A.toInt(), 0xFF8B5CF6.toInt(), 0xFFD9488B.toInt())
    }
}

object MeetingSpeakerIndex {
    fun map(lines: List<TranscriptLine>): Map<String, Int> =
        lines.mapNotNull { it.speakerLabel }.distinct().withIndex().associate { it.value to it.index }
}
