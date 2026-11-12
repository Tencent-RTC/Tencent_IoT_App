package com.tencent.iot.aiglasses.features.call

import android.graphics.Canvas
import android.graphics.ColorFilter
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.RadialGradient
import android.graphics.Rect
import android.graphics.Shader
import android.graphics.drawable.Drawable
import android.os.Bundle
import android.view.View
import androidx.core.view.isVisible
import androidx.fragment.app.Fragment
import com.tencent.iot.aiglasses.R
import com.tencent.iot.aiglasses.app.router
import com.tencent.iot.aiglasses.components.InlineHint
import com.tencent.iot.aiglasses.databinding.FragmentCallLiveBinding
import com.tencent.iot.aiglasses.designsystem.colorList
import com.tencent.iot.aiglasses.designsystem.isDarkTheme
import com.tencent.iot.aiglasses.designsystem.ovalDrawable
import com.tencent.iot.aiglasses.designsystem.pressable
import com.tencent.iot.aiglasses.models.Clock
import com.tencent.iot.aiglasses.models.SessionKind
import com.tencent.iot.aiglasses.observeState
import com.tencent.iot.aiglasses.state

class CallLiveFragment : Fragment(R.layout.fragment_call_live) {

    private var _binding: FragmentCallLiveBinding? = null
    private var leaving = false

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        val binding = FragmentCallLiveBinding.bind(view)
        _binding = binding
        val context = requireContext()
        val dark = context.isDarkTheme
        if (!dark) binding.root.background = CallGlowDrawable()
        binding.header.showsStatus = false
        binding.header.setBackLabel("返回，保持通话")
        binding.header.setOnBack { router.pop() }
        binding.avatarRing.background = context.ovalDrawable(if (dark) R.color.surface_raised else R.color.surface)
        binding.avatar.background = context.ovalDrawable(R.color.accent_soft)
        val circle = if (dark) R.color.surface_raised else R.color.surface
        binding.muteButton.background = context.pressable(context.ovalDrawable(circle))
        binding.muteButton.imageTintList = context.colorList(R.color.text_primary)
        binding.muteButton.setOnClickListener { state.call.toggleMute() }
        binding.hangUpButton.background = context.pressable(context.ovalDrawable(R.color.call_hangup))
        binding.hangUpButton.setOnClickListener { state.hangUp() }
        observeState(::render)
    }

    override fun onHiddenChanged(hidden: Boolean) {
        super.onHiddenChanged(hidden)
        if (!hidden) render()
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }

    private fun render() {
        val binding = _binding ?: return
        val session = state.session
        if (session == null || session.kind != SessionKind.CALL) {
            if (!leaving && !isHidden) {
                leaving = true
                binding.root.post { if (isAdded) router.pop() }
            }
            return
        }
        val call = state.call
        val inCall = call.phase == CallController.Phase.IN_CALL
        binding.room.text = "房间 ${session.title}"
        binding.timer.text = Clock.text(session.seconds)
        binding.status.text = statusText(call)

        binding.hint.isVisible = !state.isConnected
        if (!state.isConnected) {
            binding.hint.set(InlineHint.Tone.ERROR, "眼镜已断开，通话收音中断。", "重新连接") { state.reconnect() }
        }

        binding.muteButton.setImageResource(if (call.isMuted) R.drawable.mi_mic_off else R.drawable.mi_mic)
        binding.muteButton.contentDescription = if (call.isMuted) "取消静音" else "麦克风"
        binding.muteLabel.text = if (call.isMuted) "取消静音" else "麦克风"
        binding.muteButton.isEnabled = inCall
        binding.muteButton.alpha = if (inCall) 1f else 0.45f
    }

    private fun statusText(call: CallController): String = when {
        !state.isConnected -> "眼镜断开 · 通话中断"
        call.phase == CallController.Phase.IDLE -> "通话已结束"
        call.phase == CallController.Phase.JOINING -> "正在进入房间…"
        call.isReconnecting -> "网络波动，正在重连…"
        call.isMuted -> "已静音 · 对方听不到你"
        call.remoteUsers.isEmpty() -> "等待对方进入房间…"
        else -> "通话中"
    }
}

private class CallGlowDrawable : Drawable() {
    private val base = Paint()
    private val blobs = listOf(Paint(Paint.ANTI_ALIAS_FLAG), Paint(Paint.ANTI_ALIAS_FLAG))
    private val fade = Paint()

    override fun onBoundsChange(bounds: Rect) {
        val w = bounds.width().toFloat()
        val h = bounds.height().toFloat()
        if (w <= 0 || h <= 0) return
        base.color = 0xFFF4ECEA.toInt()
        val specs = listOf(
            Triple(floatArrayOf(0.45f, 0.30f, 0.55f, 0.21f), 0x8CF7A27E.toInt(), blobs[0]),
            Triple(floatArrayOf(0.55f, 0.62f, 0.60f, 0.20f), 0x80F39A7A.toInt(), blobs[1])
        )
        specs.forEach { (s, color, paint) ->
            paint.shader = RadialGradient(0f, 0f, 1f, intArrayOf(color, color and 0x00FFFFFF), null, Shader.TileMode.CLAMP).apply {
                setLocalMatrix(Matrix().apply {
                    setScale(w * s[2], h * s[3])
                    postTranslate(w * s[0], h * s[1])
                })
            }
        }
        fade.shader = LinearGradient(0f, h * 0.5f, 0f, h, 0x00E9E9F0, 0xFFE9E9F0.toInt(), Shader.TileMode.CLAMP)
    }

    override fun draw(canvas: Canvas) {
        canvas.drawRect(bounds, base)
        blobs.forEach { canvas.drawRect(bounds, it) }
        canvas.drawRect(bounds, fade)
    }

    override fun setAlpha(alpha: Int) = Unit

    override fun setColorFilter(colorFilter: ColorFilter?) = Unit

    @Deprecated("Deprecated in Java")
    override fun getOpacity(): Int = PixelFormat.OPAQUE
}
