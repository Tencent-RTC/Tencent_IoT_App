package com.tencent.iot.aiglasses.features.translation

import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.PopupWindow
import androidx.core.view.isVisible
import androidx.core.view.updateLayoutParams
import androidx.fragment.app.Fragment
import com.tencent.iot.aiglasses.R
import com.tencent.iot.aiglasses.app.router
import com.tencent.iot.aiglasses.app.startCapture
import com.tencent.iot.aiglasses.databinding.FragmentInterpretPrepBinding
import com.tencent.iot.aiglasses.designsystem.color
import com.tencent.iot.aiglasses.designsystem.colorList
import com.tencent.iot.aiglasses.designsystem.dp
import com.tencent.iot.aiglasses.designsystem.dpInt
import com.tencent.iot.aiglasses.designsystem.isDarkTheme
import com.tencent.iot.aiglasses.designsystem.pressable
import com.tencent.iot.aiglasses.designsystem.primaryGradient
import com.tencent.iot.aiglasses.designsystem.surface
import com.tencent.iot.aiglasses.models.SessionKind
import com.tencent.iot.aiglasses.observeState
import com.tencent.iot.aiglasses.state

class InterpretPrepFragment : Fragment(R.layout.fragment_interpret_prep) {

    private var _binding: FragmentInterpretPrepBinding? = null
    private var openSide: LanguageSide? = null
    private var popup: PopupWindow? = null

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        val binding = FragmentInterpretPrepBinding.bind(view)
        _binding = binding
        binding.languageCard.surface(radius = 22f)
        binding.styleSwapButton()
        binding.sourceTrigger.label = "对方说"
        binding.targetTrigger.label = "我说"
        binding.sourceTrigger.setOnClickListener { toggle(LanguageSide.SOURCE, it) }
        binding.targetTrigger.setOnClickListener { toggle(LanguageSide.TARGET, it) }
        binding.swapButton.setOnClickListener {
            popup?.dismiss()
            state.swapLanguages()
        }
        binding.saveSwitch.onCheckedChange = { state.savesTranslationText = it }
        binding.startButton.setOnClickListener {
            popup?.dismiss()
            startCapture(SessionKind.INTERPRET)
        }
        observeState(::render)
    }

    override fun onDestroyView() {
        popup?.dismiss()
        super.onDestroyView()
        _binding = null
    }

    override fun onHiddenChanged(hidden: Boolean) {
        super.onHiddenChanged(hidden)
        if (hidden) popup?.dismiss()
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
        binding.sourceTrigger.set(state.sourceLanguage, openSide == LanguageSide.SOURCE)
        binding.targetTrigger.set(state.targetLanguage, openSide == LanguageSide.TARGET)
        binding.saveSwitch.setChecked(state.savesTranslationText)
        val reason = state.captureBlocker
        binding.blockedReason.isVisible = reason != null
        binding.blockedReason.text = reason
        binding.startButton.isEnabled = state.canStartCapture
    }
}

private fun FragmentInterpretPrepBinding.styleSwapButton() {
    val context = root.context
    if (context.isDarkTheme) return
    swapButton.updateLayoutParams<ViewGroup.MarginLayoutParams> {
        width = context.dpInt(40f)
        height = width
        topMargin = context.dpInt(26f)
        marginStart = context.dpInt(8f)
        marginEnd = context.dpInt(8f)
    }
    val inset = context.dpInt(10.5f)
    swapButton.setPadding(inset, inset, inset, inset)
    swapButton.background = context.pressable(context.primaryGradient().apply { shape = GradientDrawable.OVAL })
    swapButton.imageTintList = context.colorList(R.color.on_accent)
    swapButton.elevation = context.dp(6f)
    swapButton.outlineSpotShadowColor = context.color(R.color.primary_glow)
    swapButton.outlineAmbientShadowColor = context.color(R.color.primary_glow)
}
