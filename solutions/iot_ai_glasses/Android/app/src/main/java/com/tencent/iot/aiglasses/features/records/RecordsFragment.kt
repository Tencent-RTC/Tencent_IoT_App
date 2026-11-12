package com.tencent.iot.aiglasses.features.records

import android.content.Context
import android.os.Bundle
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.LinearLayout
import android.widget.Space
import android.widget.TextView
import androidx.core.view.isVisible
import androidx.core.widget.doAfterTextChanged
import androidx.fragment.app.Fragment
import com.tencent.iot.aiglasses.R
import com.tencent.iot.aiglasses.app.AppRoute
import com.tencent.iot.aiglasses.app.router
import com.tencent.iot.aiglasses.databinding.FragmentRecordsBinding
import com.tencent.iot.aiglasses.designsystem.color
import com.tencent.iot.aiglasses.designsystem.dpInt
import com.tencent.iot.aiglasses.designsystem.pressable
import com.tencent.iot.aiglasses.designsystem.roundedDrawable
import com.tencent.iot.aiglasses.features.meeting.SpeakerTag
import com.tencent.iot.aiglasses.features.meeting.SpeakerTonePalette
import com.tencent.iot.aiglasses.models.MeetingSummary
import com.tencent.iot.aiglasses.models.Record
import com.tencent.iot.aiglasses.models.RecordKind
import com.tencent.iot.aiglasses.observeState
import com.tencent.iot.aiglasses.state

class RecordsFragment : Fragment(R.layout.fragment_records) {

    private enum class RecordFilter(val title: String, val kind: RecordKind?) {
        ALL("全部", null),
        MEETING("会议", RecordKind.MEETING),
        TRANSLATION("翻译", RecordKind.TRANSLATION)
    }

    private var _binding: FragmentRecordsBinding? = null
    private var filter = RecordFilter.ALL
    private var query = ""
    private var renderedKey: Any? = null

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        val binding = FragmentRecordsBinding.bind(view)
        _binding = binding
        filter = savedInstanceState?.getString(KEY_FILTER)?.let(RecordFilter::valueOf) ?: RecordFilter.ALL
        binding.searchField.background = requireContext().roundedDrawable(14f, R.color.surface)
        binding.searchInput.doAfterTextChanged {
            query = it?.toString().orEmpty()
            binding.clearButton.isVisible = query.isNotEmpty()
            render()
        }
        binding.searchInput.setOnEditorActionListener { input, action, _ ->
            if (action == EditorInfo.IME_ACTION_SEARCH) {
                input.clearFocus()
                requireContext().getSystemService(InputMethodManager::class.java).hideSoftInputFromWindow(input.windowToken, 0)
            }
            false
        }
        binding.clearButton.setOnClickListener { binding.searchInput.setText("") }
        observeState(::render)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putString(KEY_FILTER, filter.name)
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
        renderedKey = null
    }

    private fun render() {
        val binding = _binding ?: return
        val records = state.records
        val key = listOf(records.map { Triple(it.id, it.title, it.summary?.phase) }, filter, query, records.firstOrNull()?.subtitle())
        if (key == renderedKey) return
        renderedKey = key

        binding.title.trailingText = "${records.size} 条"
        renderFilters()
        val results = records.filter { record ->
            (filter.kind == null || record.kind == filter.kind) &&
                (query.isEmpty() || record.title.contains(query, ignoreCase = true))
        }
        binding.empty.isVisible = results.isEmpty()
        binding.empty.text = if (query.isEmpty() && filter.kind == null) "你的第一条记录，会从这里开始。" else "没有找到匹配的记录"
        binding.list.removeAllViews()
        results.forEachIndexed { index, record ->
            binding.list.addView(RecordCard(requireContext()).apply {
                set(record)
                setOnClickListener { router.push(AppRoute.RecordDetail(record.id)) }
            }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
                if (index > 0) topMargin = requireContext().dpInt(12f)
            })
        }
    }

    private fun renderFilters() {
        val binding = _binding ?: return
        val context = requireContext()
        binding.filters.removeAllViews()
        RecordFilter.entries.forEachIndexed { index, item ->
            val active = item == filter
            binding.filters.addView(TextView(context).apply {
                text = item.title
                setTextAppearance(R.style.TextAppearance_Suisheng_CaptionMedium)
                setTextColor(context.color(if (active) R.color.accent_text else R.color.text_secondary))
                gravity = Gravity.CENTER
                minHeight = context.dpInt(34f)
                setPadding(context.dpInt(16f), 0, context.dpInt(16f), 0)
                isClickable = true
                isFocusable = true
                isSelected = active
                background = context.pressable(
                    context.roundedDrawable(999f, if (active) R.color.accent_soft else R.color.surface, if (active) R.color.notice_border else R.color.line)
                )
                setOnClickListener {
                    if (filter != item) {
                        filter = item
                        render()
                    }
                }
            }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
                if (index > 0) marginStart = context.dpInt(8f)
            })
        }
    }

    private companion object {
        const val KEY_FILTER = "filter"
    }
}

class RecordCard(context: Context) : LinearLayout(context) {

    private val kindTag = SpeakerTag(context)
    private val pending = TextView(context).apply {
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
        setTextColor(context.color(R.color.caption_warn_text))
        text = "待联网处理"
    }
    private val titleView = TextView(context).apply {
        setTextAppearance(R.style.TextAppearance_Suisheng_BodyMedium)
        maxLines = 1
        ellipsize = TextUtils.TruncateAt.END
    }
    private val subtitleView = TextView(context).apply {
        setTextAppearance(R.style.TextAppearance_Suisheng_Caption)
        setTextColor(context.color(R.color.text_secondary))
        maxLines = 1
        ellipsize = TextUtils.TruncateAt.END
    }
    private val star = android.widget.ImageView(context).apply {
        setImageResource(R.drawable.mi_star)
        setColorFilter(context.color(R.color.accent))
    }

    init {
        orientation = VERTICAL
        val padding = context.dpInt(16f)
        setPadding(padding, padding, padding, padding)
        isClickable = true
        isFocusable = true
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        background = context.pressable(context.roundedDrawable(16f, R.color.surface, R.color.line))
        addView(LinearLayout(context).apply {
            orientation = HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
            addView(kindTag)
            addView(Space(context), LayoutParams(0, 0, 1f))
            addView(pending)
        })
        addView(LinearLayout(context).apply {
            orientation = HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
            addView(titleView, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT, 0f))
            addView(star, LayoutParams(context.dpInt(14f), context.dpInt(14f)).apply { marginStart = context.dpInt(6f) })
        }, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
            topMargin = context.dpInt(10f)
        })
        addView(subtitleView.apply { importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO }, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
            topMargin = context.dpInt(10f)
        })
    }

    fun set(record: Record) {
        val meeting = record.kind == RecordKind.MEETING
        val label = if (meeting) "会议" else "翻译"
        kindTag.set(label, SpeakerTonePalette.tone(context, if (meeting) 4 else 0))
        pending.isVisible = meeting && record.summary?.phase != MeetingSummary.Phase.READY
        titleView.text = record.title
        star.isVisible = record.isStarred
        subtitleView.text = record.subtitle()
        contentDescription = "${label}记录，${if (record.isStarred) "星标，" else ""}${record.title}，${record.subtitle()}" + if (pending.isVisible) "，待联网处理" else ""
    }
}
