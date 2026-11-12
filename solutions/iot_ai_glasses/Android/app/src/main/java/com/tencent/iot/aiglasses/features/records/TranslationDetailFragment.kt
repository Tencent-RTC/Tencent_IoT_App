package com.tencent.iot.aiglasses.features.records

import com.tencent.iot.aiglasses.components.attachTopScrollShadow
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import androidx.core.os.bundleOf
import androidx.core.view.isVisible
import androidx.fragment.app.Fragment
import com.tencent.iot.aiglasses.R
import com.tencent.iot.aiglasses.app.router
import com.tencent.iot.aiglasses.components.CircleIconButton
import com.tencent.iot.aiglasses.databinding.FragmentTranslationDetailBinding
import com.tencent.iot.aiglasses.designsystem.AppIcon
import com.tencent.iot.aiglasses.designsystem.Elevation
import com.tencent.iot.aiglasses.designsystem.elevation
import com.tencent.iot.aiglasses.designsystem.dpInt
import com.tencent.iot.aiglasses.features.translation.SentenceCard
import com.tencent.iot.aiglasses.models.Record
import com.tencent.iot.aiglasses.models.RecordKind
import com.tencent.iot.aiglasses.observeState
import com.tencent.iot.aiglasses.state
import java.util.UUID

class TranslationDetailFragment : Fragment(R.layout.fragment_translation_detail) {

    private var _binding: FragmentTranslationDetailBinding? = null
    private var leaving = false
    private var rendered: Record? = null
    private val recordID: UUID
        get() = UUID.fromString(requireArguments().getString(ARG_ID))

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        val binding = FragmentTranslationDetailBinding.bind(view)
        binding.scroll.attachTopScrollShadow(binding.root)
        _binding = binding
        binding.header.setOnBack { router.pop() }
        binding.header.trailing.addView(CircleIconButton(requireContext()).apply {
            style = CircleIconButton.Style.PLAIN
            setIcon(AppIcon.DOWNLOAD)
            contentDescription = "导出文字"
            setOnClickListener { record()?.let(::export) }
        }, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        observeState(::render)
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
        rendered = null
    }

    private fun record(): Record? = state.records.firstOrNull { it.id == recordID && it.kind == RecordKind.TRANSLATION }

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
        if (record == rendered) return
        rendered = record
        binding.header.title = record.translationHeading
        binding.header.subtitle = record.translationSubtitle()
        val lines = record.transcript.orEmpty()
        binding.empty.isVisible = lines.isEmpty()
        binding.list.removeAllViews()
        lines.forEachIndexed { index, line ->
            binding.list.addView(SentenceCard(requireContext()).apply {
                set(index, line, isLatest = false)
                elevation(Elevation.HERO)
            },
                LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
                    if (index > 0) topMargin = requireContext().dpInt(16f)
                })
        }
    }

    private fun export(record: Record) {
        val lines = mutableListOf(record.title, record.subtitle(), "", "—— 双语对照 ——")
        record.transcript.orEmpty().forEach { lines += listOf(it.translated, it.original, "") }
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_SUBJECT, record.title)
            putExtra(Intent.EXTRA_TEXT, lines.joinToString("\n"))
        }
        startActivity(Intent.createChooser(send, "导出文字"))
    }

    companion object {
        private const val ARG_ID = "recordID"

        fun newInstance(recordID: UUID) = TranslationDetailFragment().apply { arguments = bundleOf(ARG_ID to recordID.toString()) }
    }
}
