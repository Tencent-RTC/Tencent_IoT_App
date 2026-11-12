package com.tencent.iot.aiglasses.features.translation

import android.content.Context
import android.graphics.Typeface
import android.util.TypedValue
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.view.isVisible
import com.tencent.iot.aiglasses.R
import com.tencent.iot.aiglasses.designsystem.color
import com.tencent.iot.aiglasses.designsystem.dp
import com.tencent.iot.aiglasses.designsystem.dpInt
import com.tencent.iot.aiglasses.designsystem.isDarkTheme
import com.tencent.iot.aiglasses.designsystem.ovalDrawable
import com.tencent.iot.aiglasses.designsystem.roundedDrawable
import com.tencent.iot.aiglasses.models.Clock
import com.tencent.iot.aiglasses.models.Speaker
import com.tencent.iot.aiglasses.models.TranscriptLine

class SentenceCard(context: Context) : LinearLayout(context) {

    private val speakerTag = TextView(context).apply {
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
        typeface = Typeface.create(Typeface.DEFAULT, 500, false)
        isVisible = false
    }

    private val activeDot = View(context).apply {
        background = context.ovalDrawable(R.color.caption_latest_active_tag)
        isVisible = false
    }

    private val time = TextView(context).apply {
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
        fontFeatureSettings = "tnum"
    }

    private val original = TextView(context).apply {
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 13.5f)
        setLineSpacing(context.dp(4f), 1f)
        setTextColor(context.color(R.color.caption_source))
    }

    private val translated = TextView(context).apply {
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        typeface = Typeface.create(Typeface.DEFAULT, 600, false)
        setLineSpacing(context.dp(5f), 1f)
    }

    init {
        orientation = VERTICAL
        setPadding(context.dpInt(16f), context.dpInt(14f), context.dpInt(16f), context.dpInt(14f))
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        addView(LinearLayout(context).apply {
            orientation = HORIZONTAL
            gravity = android.view.Gravity.CENTER_VERTICAL
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
            addView(speakerTag)
            addView(activeDot, LayoutParams(context.dpInt(5f), context.dpInt(5f)).apply { marginEnd = context.dpInt(5f) })
            addView(time)
        }, LayoutParams(LayoutParams.MATCH_PARENT, context.dpInt(16f)).apply { bottomMargin = context.dpInt(8f) })
        addView(original.apply { importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO })
        addView(translated.apply { importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO },
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply { topMargin = context.dpInt(8f) })
    }

    fun set(index: Int, line: TranscriptLine, isLatest: Boolean, showSpeaker: Boolean = false) {
        val pending = line.translated.isEmpty()
        val active = isLatest && pending
        speakerTag.isVisible = showSpeaker
        if (showSpeaker) {
            val mine = line.speaker == Speaker.ME
            speakerTag.text = if (mine) "我说" else "对方说"
            speakerTag.setTextColor(context.color(if (mine) R.color.accent_text else R.color.text_secondary))
            val horizontal = context.dpInt(8f)
            val vertical = context.dpInt(2f)
            speakerTag.setPadding(horizontal, vertical, horizontal, vertical)
            speakerTag.background = context.roundedDrawable(999f, if (mine) R.color.accent_soft else if (context.isDarkTheme) R.color.caption_border else R.color.speaker_background)
            (speakerTag.layoutParams as? LayoutParams)?.marginEnd = context.dpInt(6f)
        }
        activeDot.isVisible = active
        time.text = if (active) "识别并翻译中" else Clock.text(line.time)
        time.typeface = Typeface.create(Typeface.DEFAULT, if (active) 500 else 400, false)
        time.setTextColor(context.color(if (active) R.color.caption_latest_active_tag else R.color.caption_time))
        original.text = line.original
        translated.text = if (pending) "翻译中…" else line.translated
        translated.setTextColor(context.color(if (pending) R.color.caption_time else R.color.caption_text))
        background = context.roundedDrawable(
            18f,
            if (active) R.color.caption_latest_active_card else R.color.caption_card,
            if (active) R.color.caption_latest_active_border else R.color.caption_border
        )
        contentDescription = (if (pending) "第 ${index + 1} 句，${line.original}" else "第 ${index + 1} 句，${line.translated}。原文：${line.original}") +
            if (isLatest) "，最新" else ""
    }
}
