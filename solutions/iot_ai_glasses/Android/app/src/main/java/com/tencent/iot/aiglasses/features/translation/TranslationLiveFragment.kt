package com.tencent.iot.aiglasses.features.translation

import android.os.Bundle
import android.view.View
import android.widget.PopupWindow
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AlertDialog
import androidx.core.view.isVisible
import androidx.fragment.app.Fragment
import com.tencent.iot.aiglasses.R
import com.tencent.iot.aiglasses.app.AppDialog
import com.tencent.iot.aiglasses.app.router
import com.tencent.iot.aiglasses.components.InlineHint
import com.tencent.iot.aiglasses.databinding.FragmentTranslationLiveBinding
import com.tencent.iot.aiglasses.designsystem.AppIcon
import com.tencent.iot.aiglasses.designsystem.ovalDrawable
import com.tencent.iot.aiglasses.designsystem.pressable
import com.tencent.iot.aiglasses.designsystem.surface
import com.tencent.iot.aiglasses.models.Clock
import com.tencent.iot.aiglasses.models.SessionKind
import com.tencent.iot.aiglasses.observeState
import com.tencent.iot.aiglasses.state

class TranslationLiveFragment : Fragment(R.layout.fragment_translation_live) {

    private var _binding: FragmentTranslationLiveBinding? = null
    private var leaving = false
    private var openSide: LanguageSide? = null
    private var popup: PopupWindow? = null
    private val backCallback = object : OnBackPressedCallback(true) {
        override fun handleOnBackPressed() {
            state.dialog = if (state.dialog == null) AppDialog.EndSession else null
        }
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        val binding = FragmentTranslationLiveBinding.bind(view)
        binding.transcript.attachTopShadow(binding.root)
        _binding = binding
        val context = view.context
        binding.header.setBackLabel("返回")
        binding.header.setOnBack { state.dialog = AppDialog.EndSession }
        binding.header.setOnSettings(::showSettings)
        binding.sourceTrigger.boxed = true
        binding.targetTrigger.boxed = true
        binding.sourceTrigger.label = "听到的语言"
        binding.targetTrigger.label = "我的期望语言"
        binding.sourceTrigger.setOnClickListener { toggle(LanguageSide.SOURCE, it) }
        binding.targetTrigger.setOnClickListener { toggle(LanguageSide.TARGET, it) }
        binding.swapButton.background = context.pressable(context.ovalDrawable(R.color.accent_soft))
        binding.swapButton.setOnClickListener {
            popup?.dismiss()
            state.swapLanguages()
        }
        binding.languageBar.surface(radius = 20f)
        binding.liveBar.leading.setOnClickListener { state.toggleReadAloud() }
        binding.liveBar.pill.setOnClickListener { state.togglePause() }
        binding.liveBar.trailing.setOnClickListener { state.dialog = AppDialog.EndSession }
        binding.liveBar.setButton(binding.liveBar.trailing, AppIcon.STOP.res, "结束翻译")
        requireActivity().onBackPressedDispatcher.addCallback(viewLifecycleOwner, backCallback)
        backCallback.isEnabled = !isHidden
        observeState(::render)
    }

    override fun onHiddenChanged(hidden: Boolean) {
        super.onHiddenChanged(hidden)
        backCallback.isEnabled = !hidden
        if (hidden) popup?.dismiss()
        if (!hidden) render()
    }

    override fun onDestroyView() {
        popup?.dismiss()
        super.onDestroyView()
        _binding = null
    }

    private fun showSettings() {
        val checked = booleanArrayOf(state.savesTranslationText, state.readsTranslationAloud)
        AlertDialog.Builder(requireContext())
            .setTitle("翻译设置")
            .setMultiChoiceItems(arrayOf("保存双语文字", "自动播放译文"), checked) { _, which, isChecked ->
                when (which) {
                    0 -> state.updateSavesTranslationText(isChecked)
                    1 -> if (isChecked != state.readsTranslationAloud) state.toggleReadAloud()
                }
            }
            .setPositiveButton("完成", null)
            .apply {
                if (state.availableEngines.size > 1) setNeutralButton("识别方式：${state.captionEngine.title}") { _, _ -> showEngines() }
            }
            .show()
    }

    private fun showEngines() {
        val engines = state.availableEngines
        AlertDialog.Builder(requireContext())
            .setTitle("识别方式")
            .setSingleChoiceItems(engines.map { it.title }.toTypedArray(), engines.indexOf(state.captionEngine)) { dialog, which ->
                state.updateCaptionEngine(engines[which])
                dialog.dismiss()
            }
            .show()
    }

    private fun toggle(side: LanguageSide, anchor: View) {
        if (openSide == side) {
            popup?.dismiss()
            return
        }
        popup?.dismiss()
        openSide = side
        render()
        val selection = if (side == LanguageSide.SOURCE) state.sourceLanguage else state.targetLanguage
        popup = LanguageMenu.show(anchor, selection, onDismiss = {
            if (openSide == side) {
                openSide = null
                popup = null
                render()
            }
        }) { language ->
            if (side == LanguageSide.SOURCE) state.setSourceLanguage(language) else state.setTargetLanguage(language)
        }
    }

    private fun render() {
        val binding = _binding ?: return
        val session = state.session
        if (session == null || session.kind != SessionKind.TRANSLATION) {
            if (!leaving && !isHidden) {
                leaving = true
                binding.root.post { if (isAdded) router.popToRoot() }
            }
            return
        }
        when {
            !state.isConnected -> {
                binding.hint.isVisible = true
                binding.hint.set(InlineHint.Tone.ERROR, "眼镜已断开，已有文字已保留。断连期间的音频无法补回。", "重新连接") { state.reconnect() }
            }
            !state.isOnline -> {
                binding.hint.isVisible = true
                binding.hint.set(InlineHint.Tone.WARNING, "网络中断，字幕暂停更新。")
            }
            else -> binding.hint.isVisible = false
        }
        binding.header.setConnected(state.isConnected)
        binding.sourceTrigger.set(state.sourceLanguage, openSide == LanguageSide.SOURCE)
        binding.targetTrigger.set(state.targetLanguage, openSide == LanguageSide.TARGET)
        binding.transcript.set(session.entries, session.isPaused)
        val reads = state.readsTranslationAloud
        binding.liveBar.setButton(
            binding.liveBar.leading,
            AppIcon.SPEAKER.res,
            if (reads) "关闭译文播报" else "开启译文播报",
            tint = if (reads) R.color.text_primary else R.color.icon_muted
        )
        val paused = session.isPaused
        binding.liveBar.setPill(
            if (paused) AppIcon.PLAY.res else AppIcon.PAUSE.res,
            "${if (paused) "已暂停" else "正在翻译"} · ${Clock.text(session.seconds)}",
            if (paused) "继续翻译" else "暂停翻译"
        )
    }
}
