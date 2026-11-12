package com.tencent.iot.aiglasses.features.device

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.os.Bundle
import android.util.AttributeSet
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.Space
import android.widget.TextView
import androidx.fragment.app.Fragment
import com.tencent.iot.aiglasses.R
import com.tencent.iot.aiglasses.databinding.FragmentDeviceBinding
import com.tencent.iot.aiglasses.designsystem.color
import com.tencent.iot.aiglasses.designsystem.dp
import com.tencent.iot.aiglasses.designsystem.dpInt
import com.tencent.iot.aiglasses.designsystem.roundedDrawable
import com.tencent.iot.aiglasses.observeState
import com.tencent.iot.aiglasses.state

class DeviceFragment : Fragment(R.layout.fragment_device) {

    private var _binding: FragmentDeviceBinding? = null

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        val binding = FragmentDeviceBinding.bind(view)
        _binding = binding
        binding.connectButton.setOnClickListener { state.setConnected(!state.isConnected) }
        binding.micStatus.background = requireContext().roundedDrawable(999f, android.R.color.transparent, R.color.line)
        observeState(::render)
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }

    private fun render() {
        val binding = _binding ?: return
        binding.hero.set(state.isConnected, state.batteryLevel)
        binding.connectButton.text = if (state.isConnected) "断开" else "连接"
        binding.connectButton.contentDescription = if (state.isConnected) "断开眼镜" else "连接眼镜"
        binding.micStatus.text = if (state.isConnected) "就绪" else "等待连接"
    }
}

class DeviceRow @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : LinearLayout(context, attrs) {

    private val linePaint = Paint().apply { color = context.color(R.color.line) }

    init {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        minimumHeight = context.dpInt(69f)
        setWillNotDraw(false)
        val title = context.obtainStyledAttributes(attrs, R.styleable.SettingRow).run {
            getString(R.styleable.SettingRow_title).orEmpty().also { recycle() }
        }
        addView(TextView(context).apply {
            setTextAppearance(R.style.TextAppearance_Suisheng_Callout)
            text = title
        })
        addView(Space(context), LayoutParams(0, 0, 1f))
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.drawRect(0f, height - context.dp(1f), width.toFloat(), height.toFloat(), linePaint)
    }
}
