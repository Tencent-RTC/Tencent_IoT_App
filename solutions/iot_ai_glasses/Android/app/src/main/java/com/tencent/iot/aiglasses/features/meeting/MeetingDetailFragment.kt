package com.tencent.iot.aiglasses.features.meeting

import com.tencent.iot.aiglasses.components.attachTopScrollShadow
import android.content.Context
import android.content.Intent
import android.graphics.Paint
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.annotation.ColorRes
import androidx.core.os.bundleOf
import androidx.fragment.app.Fragment
import com.tencent.iot.aiglasses.R
import com.tencent.iot.aiglasses.app.router
import com.tencent.iot.aiglasses.components.CircleIconButton
import com.tencent.iot.aiglasses.components.ThinkingDots
import com.tencent.iot.aiglasses.databinding.FragmentMeetingDetailBinding
import com.tencent.iot.aiglasses.designsystem.AppIcon
import com.tencent.iot.aiglasses.designsystem.color
import com.tencent.iot.aiglasses.designsystem.dp
import com.tencent.iot.aiglasses.designsystem.dpInt
import com.tencent.iot.aiglasses.designsystem.ovalDrawable
import com.tencent.iot.aiglasses.designsystem.pressable
import com.tencent.iot.aiglasses.designsystem.roundedDrawable
import com.tencent.iot.aiglasses.designsystem.setAppIcon
import com.tencent.iot.aiglasses.designsystem.Elevation
import com.tencent.iot.aiglasses.designsystem.elevation
import com.tencent.iot.aiglasses.designsystem.surface
import com.tencent.iot.aiglasses.models.MeetingSummary
import com.tencent.iot.aiglasses.models.MeetingTodo
import com.tencent.iot.aiglasses.models.Record
import com.tencent.iot.aiglasses.observeState
import com.tencent.iot.aiglasses.state
import java.util.UUID

class MeetingDetailFragment : Fragment(R.layout.fragment_meeting_detail) {

    private enum class Tab(val title: String) {
        SUMMARY("摘要"),
        TRANSCRIPT("原文"),
        TODOS("待办")
    }

    private var _binding: FragmentMeetingDetailBinding? = null
    private var tab = Tab.SUMMARY
    private var leaving = false
    private val recordID: UUID
        get() = UUID.fromString(requireArguments().getString(ARG_ID))

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        val binding = FragmentMeetingDetailBinding.bind(view)
        binding.scroll.attachTopScrollShadow(binding.root)
        _binding = binding
        tab = savedInstanceState?.getString(KEY_TAB)?.let(Tab::valueOf) ?: Tab.SUMMARY
        binding.header.setOnBack { router.pop() }
        binding.header.trailing.addView(CircleIconButton(requireContext()).apply {
            style = CircleIconButton.Style.PLAIN
            setIcon(AppIcon.DOWNLOAD)
            contentDescription = "导出文字"
            setOnClickListener { record()?.let(::export) }
        }, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        binding.tabs.background = requireContext().roundedDrawable(14f, R.color.surface)
        observeState(::render)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putString(KEY_TAB, tab.name)
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }

    private fun record(): Record? = state.records.firstOrNull { it.id == recordID }

    private fun render() {
        val binding = _binding ?: return
        val record = record()
        if (record == null) {
            if (!leaving) {
                leaving = true
                binding.root.post { if (isAdded) router.pop() }
            }
            return
        }
        binding.header.title = record.title
        binding.header.subtitle = record.subtitle()
        renderTabs()
        binding.body.removeAllViews()
        when (tab) {
            Tab.SUMMARY -> summaryBody(record)
            Tab.TRANSCRIPT -> transcriptBody(record)
            Tab.TODOS -> todosBody(record)
        }
    }

    private fun renderTabs() {
        val binding = _binding ?: return
        val context = requireContext()
        binding.tabs.removeAllViews()
        Tab.entries.forEachIndexed { index, item ->
            val selected = item == tab
            binding.tabs.addView(TextView(context).apply {
                text = item.title
                setTextAppearance(R.style.TextAppearance_Suisheng_Footnote)
                setTextColor(context.color(if (selected) R.color.accent_text else R.color.text_secondary))
                gravity = Gravity.CENTER
                minHeight = context.dpInt(40f)
                isClickable = true
                isFocusable = true
                isSelected = selected
                background = context.pressable(if (selected) context.roundedDrawable(12f, R.color.accent_soft) else null, context.roundedDrawable(12f, R.color.surface))
                setOnClickListener {
                    if (tab != item) {
                        tab = item
                        render()
                    }
                }
            }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                if (index > 0) marginStart = context.dpInt(8f)
            })
        }
    }

    private fun summaryBody(record: Record) {
        val body = _binding?.body ?: return
        val summary = record.summary
        when (summary?.phase) {
            null -> body.add(card { addText("AI 服务未配置，无法生成摘要。", R.color.text_secondary) })
            MeetingSummary.Phase.PENDING -> {
                val generating = state.isSummaryGenerating(record.id)
                if (state.isOnline) {
                    body.add(card {
                        addView(LinearLayout(context).apply {
                            orientation = LinearLayout.HORIZONTAL
                            gravity = Gravity.CENTER_VERTICAL
                            if (generating) addView(ThinkingDots(context), LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { marginEnd = context.dpInt(10f) })
                            addView(footnote(if (generating) "正在生成摘要…" else "待联网处理。恢复网络后自动生成，也可以手动重试。", R.color.text_secondary))
                        })
                    })
                    if (!generating) body.add(retryButton(record.id), gap = 14f)
                } else {
                    body.add(card { addText("待联网处理。此段内容还没有生成摘要。", R.color.caption_warn_text) })
                    body.add(retryButton(record.id), gap = 14f)
                }
            }
            MeetingSummary.Phase.FAILED -> {
                body.add(card { addText("摘要生成失败，请重试。", R.color.caption_error_text) })
                body.add(retryButton(record.id), gap = 14f)
            }
            MeetingSummary.Phase.READY -> {
                body.add(card("一句话总结") {
                    addView(TextView(context).apply {
                        setTextAppearance(R.style.TextAppearance_Suisheng_Body)
                        setTextColor(context.color(R.color.caption_text))
                        setLineSpacing(context.dp(4f), 1f)
                        text = summary.headline
                    })
                })
                if (summary.consensus.isNotEmpty()) body.add(card("已达成共识") { addBullets(summary.consensus) }, gap = 14f)
                if (summary.questions.isNotEmpty()) body.add(card("待确认问题") { addBullets(summary.questions) }, gap = 14f)
            }
        }
    }

    private fun transcriptBody(record: Record) {
        val body = _binding?.body ?: return
        val context = requireContext()
        val lines = record.transcript.orEmpty()
        val index = MeetingSpeakerIndex.map(lines)
        body.add(LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            minimumHeight = context.dpInt(40f)
            setPadding(context.dpInt(14f), 0, context.dpInt(14f), 0)
            background = context.roundedDrawable(12f, R.color.surface)
            addView(ImageView(context).apply { setAppIcon(AppIcon.PLAY, R.color.text_secondary) }, LinearLayout.LayoutParams(context.dpInt(16f), context.dpInt(16f)))
            addView(caption(if (record.keepsAudio) "录音回听" else "未保留原始录音"), LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
                marginStart = context.dpInt(8f)
            })
        })
        if (lines.isEmpty()) {
            body.add(emptyText("没有识别到文字"), gap = 14f)
            return
        }
        lines.forEachIndexed { position, line ->
            body.add(MeetingCard(context).apply {
                set(position, line, isLatest = false, speakerIndex = index[line.speakerLabel.orEmpty()] ?: 0)
                elevation(Elevation.HERO)
            }, gap = 14f)
        }
    }

    private fun todosBody(record: Record) {
        val body = _binding?.body ?: return
        val todos = record.summary?.todos.orEmpty()
        if (todos.isEmpty()) {
            body.add(emptyText("本条记录未提取到待办。"))
            return
        }
        body.add(card {
            todos.forEachIndexed { position, todo ->
                if (position > 0) addView(View(context).apply { setBackgroundColor(context.color(R.color.separator)) }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, context.dpInt(1f)))
                addView(todoRow(record.id, todo))
            }
        }.apply { setPadding(paddingLeft, context.dpInt(2f), paddingRight, context.dpInt(2f)) })
    }

    private fun todoRow(recordID: UUID, todo: MeetingTodo): View {
        val context = requireContext()
        return LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.TOP
            setPadding(0, context.dpInt(14f), 0, context.dpInt(14f))
            isClickable = true
            isFocusable = true
            background = context.pressable(null, context.roundedDrawable(8f, R.color.surface))
            contentDescription = (if (todo.isDone) "完成待办：" else "待办：") + todo.text + (if (todo.isDone) "，双击取消完成" else "，双击完成")
            setOnClickListener { state.toggleMeetingTodo(recordID, todo.id) }
            addView(TodoCheck(context, todo.isDone), LinearLayout.LayoutParams(context.dpInt(20f), context.dpInt(20f)).apply { topMargin = context.dpInt(2f) })
            addView(LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
                addView(TextView(context).apply {
                    setTextAppearance(R.style.TextAppearance_Suisheng_Body)
                    text = todo.text
                    if (todo.isDone) {
                        paintFlags = paintFlags or Paint.STRIKE_THRU_TEXT_FLAG
                        setTextColor(context.color(R.color.text_secondary))
                    }
                })
                addView(caption(todo.note), LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
                    topMargin = context.dpInt(3f)
                })
            }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply { marginStart = context.dpInt(12f) })
        }
    }

    private fun retryButton(recordID: UUID): View = Button(requireContext(), null, 0, R.style.Widget_Suisheng_Button_Pill).apply {
        text = "重试"
        setOnClickListener { state.retrySummary(recordID) }
    }.let { button ->
        FrameLayout(requireContext()).apply {
            addView(button, FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.CENTER_HORIZONTAL))
        }
    }

    private fun card(title: String? = null, content: LinearLayout.() -> Unit): LinearLayout = LinearLayout(requireContext()).apply {
        orientation = LinearLayout.VERTICAL
        val padding = context.dpInt(16f)
        setPadding(padding, padding, padding, padding)
        surface(radius = 18f, level = Elevation.HERO)
        if (title != null) {
            addView(TextView(context).apply {
                setTextAppearance(R.style.TextAppearance_Suisheng_BodyMedium)
                text = title
            }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
                bottomMargin = context.dpInt(10f)
            })
        }
        content()
    }

    private fun LinearLayout.addText(text: String, @ColorRes tint: Int) = addView(footnote(text, tint))

    private fun LinearLayout.addBullets(items: List<String>) {
        items.forEachIndexed { index, item ->
            addView(LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.TOP
                addView(View(context).apply { background = context.ovalDrawable(R.color.accent_text) }, LinearLayout.LayoutParams(context.dpInt(4f), context.dpInt(4f)).apply {
                    topMargin = context.dpInt(8f)
                })
                addView(footnote(item, R.color.caption_text).apply { setLineSpacing(context.dp(4f), 1f) }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                    marginStart = context.dpInt(8f)
                })
            }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
                if (index > 0) topMargin = context.dpInt(8f)
            })
        }
    }

    private fun footnote(text: String, @ColorRes tint: Int) = TextView(requireContext()).apply {
        setTextAppearance(R.style.TextAppearance_Suisheng_Footnote)
        setTextColor(context.color(tint))
        this.text = text
    }

    private fun caption(text: String) = TextView(requireContext()).apply {
        setTextAppearance(R.style.TextAppearance_Suisheng_Caption)
        setTextColor(context.color(R.color.text_secondary))
        this.text = text
    }

    private fun emptyText(text: String) = footnote(text, R.color.text_secondary).apply {
        gravity = Gravity.CENTER
        setPadding(0, context.dpInt(28f), 0, context.dpInt(28f))
    }

    private fun LinearLayout.add(view: View, gap: Float = 0f) {
        addView(view, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
            if (childCount > 0) topMargin = context.dpInt(gap)
        })
    }

    private fun export(record: Record) {
        val lines = mutableListOf(record.title, record.subtitle(), "", "—— 原文 ——")
        record.transcript.orEmpty().forEach { lines += "[${it.speakerLabel ?: "发言"}] ${it.original}" }
        val summary = record.summary
        if (summary != null && summary.phase == MeetingSummary.Phase.READY) {
            lines += listOf("", "—— 摘要 ——", summary.headline)
            if (summary.consensus.isNotEmpty()) lines += listOf("已达成共识：") + summary.consensus.map { "· $it" }
            if (summary.questions.isNotEmpty()) lines += listOf("待确认问题：") + summary.questions.map { "· $it" }
            if (summary.todos.isNotEmpty()) lines += listOf("待办：") + summary.todos.map { "· ${it.text}（${it.note}）" }
        }
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_SUBJECT, record.title)
            putExtra(Intent.EXTRA_TEXT, lines.joinToString("\n"))
        }
        startActivity(Intent.createChooser(send, "导出文字"))
    }

    companion object {
        private const val ARG_ID = "recordID"
        private const val KEY_TAB = "tab"

        fun newInstance(recordID: UUID) = MeetingDetailFragment().apply { arguments = bundleOf(ARG_ID to recordID.toString()) }
    }
}

private class TodoCheck(context: Context, isOn: Boolean) : FrameLayout(context) {
    init {
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        background = if (isOn) context.ovalDrawable(R.color.accent) else context.ovalDrawable(android.R.color.transparent, R.color.checkbox_border).apply {
            setStroke(context.dpInt(1.5f), context.color(R.color.checkbox_border))
        }
        if (isOn) addView(ImageView(context).apply { setAppIcon(AppIcon.CHECK, R.color.on_accent) }, LayoutParams(context.dpInt(12f), context.dpInt(12f), Gravity.CENTER))
    }
}
