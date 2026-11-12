package com.tencent.iot.aiglasses.features.translation

import android.os.Bundle
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.OnBackPressedCallback
import androidx.core.view.isVisible
import androidx.fragment.app.Fragment
import com.tencent.iot.aiglasses.R
import com.tencent.iot.aiglasses.app.AppDialog
import com.tencent.iot.aiglasses.app.router
import com.tencent.iot.aiglasses.components.InlineHint
import com.tencent.iot.aiglasses.databinding.FragmentInterpretLiveBinding
import com.tencent.iot.aiglasses.designsystem.AppIcon
import com.tencent.iot.aiglasses.designsystem.color
import com.tencent.iot.aiglasses.designsystem.colorList
import com.tencent.iot.aiglasses.designsystem.dp
import com.tencent.iot.aiglasses.designsystem.dpInt
import com.tencent.iot.aiglasses.designsystem.isDarkTheme
import com.tencent.iot.aiglasses.designsystem.ovalDrawable
import com.tencent.iot.aiglasses.designsystem.pressable
import com.tencent.iot.aiglasses.designsystem.primaryGradient
import com.tencent.iot.aiglasses.designsystem.roundedDrawable
import com.tencent.iot.aiglasses.designsystem.surface
import com.tencent.iot.aiglasses.models.ActiveSession
import com.tencent.iot.aiglasses.models.SessionKind
import com.tencent.iot.aiglasses.models.Speaker
import com.tencent.iot.aiglasses.observeState
import com.tencent.iot.aiglasses.state

class InterpretLiveFragment : Fragment(R.layout.fragment_interpret_live) {

    private var _binding: FragmentInterpretLiveBinding? = null
    private var leaving = false
    private val backCallback = object : OnBackPressedCallback(true) {
        override fun handleOnBackPressed() {
            state.dialog = if (state.dialog == null) AppDialog.LeaveSession else null
        }
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        val binding = FragmentInterpretLiveBinding.bind(view)
        binding.transcript.attachTopShadow(binding.root)
        _binding = binding
        binding.header.setOnBack { state.dialog = AppDialog.LeaveSession }
        if (requireContext().isDarkTheme) {
            binding.speakingSwitch.background = requireContext().roundedDrawable(14f, R.color.surface)
        } else {
            binding.speakingSwitch.surface(radius = 16f)
        }
        binding.pauseButton.setOnClickListener { state.togglePause() }
        binding.pauseButton.background = if (view.context.isDarkTheme) {
            view.context.pressable(view.context.ovalDrawable(R.color.accent))
        } else {
            view.context.pressable(view.context.primaryGradient().apply { shape = GradientDrawable.OVAL })
        }
        binding.pauseButton.imageTintList = view.context.colorList(R.color.on_accent)
        if (!view.context.isDarkTheme) {
            binding.pauseButton.elevation = view.context.dp(8f)
            binding.pauseButton.outlineSpotShadowColor = view.context.color(R.color.primary_glow)
            binding.pauseButton.outlineAmbientShadowColor = view.context.color(R.color.primary_glow)
        }
        requireActivity().onBackPressedDispatcher.addCallback(viewLifecycleOwner, backCallback)
        backCallback.isEnabled = !isHidden
        binding.transcript.bindCard = { card, item ->
            (card as SentenceCard).set(item.index, item.line, item.isLatest, showSpeaker = true)
        }
        observeState(::render)
    }

    override fun onHiddenChanged(hidden: Boolean) {
        super.onHiddenChanged(hidden)
        backCallback.isEnabled = !hidden
        if (!hidden) render()
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }

    private fun render() {
        val binding = _binding ?: return
        val session = state.session
        if (session == null || session.kind != SessionKind.INTERPRET) {
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
        renderSpeakingSwitch(session)
        binding.transcript.set(session.entries, session.isPaused)
        binding.wave.isActive = state.canProcess
        binding.waveMirror.isActive = state.canProcess
        binding.pauseButton.contentDescription = if (session.isPaused) "继续同传" else "暂停同传"
        binding.pauseButton.setImageResource(if (session.isPaused) AppIcon.PLAY.res else AppIcon.PAUSE.res)
        binding.pauseButton.isSelected = session.isPaused
    }

    private fun renderSpeakingSwitch(session: ActiveSession) {
        val binding = _binding ?: return
        val context = requireContext()
        binding.speakingSwitch.removeAllViews()
        Speaker.entries.forEachIndexed { index, item ->
            val selected = item == session.speaking
            val gradient = selected && item == Speaker.ME && !context.isDarkTheme
            val label = if (item == Speaker.ME) "我说" else "对方说"
            binding.speakingSwitch.addView(TextView(context).apply {
                text = label
                setTextAppearance(R.style.TextAppearance_Suisheng_Footnote)
                setTextColor(context.color(if (gradient) R.color.on_accent else if (selected) R.color.accent_text else R.color.text_secondary))
                gravity = Gravity.CENTER
                minHeight = context.dpInt(40f)
                isClickable = true
                isFocusable = true
                isSelected = selected
                contentDescription = if (selected) "$label，正在翻译这一方" else "切换到$label"
                val fill = when {
                    gradient -> context.primaryGradient().apply { cornerRadius = context.dp(12f) }
                    selected -> context.roundedDrawable(12f, R.color.accent_soft)
                    else -> null
                }
                background = context.pressable(fill, context.roundedDrawable(12f, R.color.surface))
                setOnClickListener { if (session.speaking != item) state.switchSpeaking() }
            }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                if (index > 0) marginStart = context.dpInt(8f)
            })
        }
    }
}
