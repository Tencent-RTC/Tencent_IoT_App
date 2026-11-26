package com.tencent.iot.watchapp.ui
import com.tencent.iot.watchapp.R
import com.tencent.iot.watchapp.app.MainActivity
import com.tencent.iot.watchapp.call.*
import com.tencent.iot.watchapp.im.ImService
import com.tencent.iot.watchapp.watch.*

import android.content.Context
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.util.AttributeSet
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.content.ContextCompat
import androidx.core.view.doOnLayout

class CallTargetPickerView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : FrameLayout(context, attrs, defStyleAttr) {
    private val boundWatches = WatchBindingStore.all(context, ImService.loggedInUserId)
    private var selectedWatch: BoundWatch? = boundWatches.firstOrNull()
    private var dismissing = false

    init {
        id = R.id.watch_call_picker_root
        LayoutInflater.from(context).inflate(R.layout.watch_call_target_picker, this, true)
        findViewById<View>(R.id.watch_call_picker_scrim).setOnClickListener { dismiss() }
        findViewById<TextView>(R.id.watch_picker_cancel).setOnClickListener { dismiss() }
        val targets = findViewById<LinearLayout>(R.id.watch_picker_targets)
        val empty = findViewById<TextView>(R.id.watch_picker_empty)
        if (boundWatches.isEmpty()) {
            empty.visibility = View.VISIBLE
        } else {
            empty.visibility = View.GONE
            boundWatches.forEach { targets.addView(createTargetView(it)) }
        }
        val enabled = boundWatches.isNotEmpty()
        listOf(R.id.watch_picker_video_action, R.id.watch_picker_voice_action).forEach { id ->
            findViewById<View>(id).apply {
                isEnabled = enabled
                alpha = if (enabled) 1f else 0.42f
            }
        }
        findViewById<View>(R.id.watch_picker_video_action).setOnClickListener { startCall(voiceMode = false) }
        findViewById<View>(R.id.watch_picker_voice_action).setOnClickListener { startCall(voiceMode = true) }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        val sheet = findViewById<View>(R.id.watch_call_picker_sheet)
        val scrim = findViewById<View>(R.id.watch_call_picker_scrim)
        sheet.doOnLayout {
            if (!isAttachedToWindow || dismissing) return@doOnLayout
            sheet.translationY = sheet.height.toFloat()
            scrim.alpha = 0f
            sheet.animate()
                .translationY(0f)
                .setDuration(280L)
                .setInterpolator(android.view.animation.DecelerateInterpolator(1.7f))
                .start()
            scrim.animate()
                .alpha(1f)
                .setDuration(220L)
                .start()
        }
    }

    override fun onDetachedFromWindow() {
        findViewById<View>(R.id.watch_call_picker_sheet).animate().cancel()
        findViewById<View>(R.id.watch_call_picker_scrim).animate().cancel()
        super.onDetachedFromWindow()
    }

    private fun startCall(voiceMode: Boolean) {
        val watch = selectedWatch ?: return
        val target = CallTarget(
            productId = watch.productId,
            deviceName = watch.deviceName,
        )
        (context as? MainActivity)?.startCall(
            target = target,
            voiceMode = voiceMode,
            targetName = watch.deviceName,
            avatarId = watch.deviceName,
        )
    }

    private fun createTargetView(watch: BoundWatch): View {
        val item = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = android.view.Gravity.CENTER_HORIZONTAL
            isClickable = true
            isFocusable = true
            setPadding(dp(2), 0, dp(2), 0)
        }
        item.layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)

        val avatar = FrameLayout(context).apply {
            layoutParams = LinearLayout.LayoutParams(dp(56), dp(56))
            background = if (watch == selectedWatch) {
                ContextCompat.getDrawable(context, R.drawable.watch_call_picker_avatar_selected)
            } else {
                ColorDrawable(Color.TRANSPARENT)
            }
        }
        avatar.addView(ImageView(context).apply {
            layoutParams = FrameLayout.LayoutParams(dp(48), dp(48), android.view.Gravity.CENTER)
            contentDescription = context.getString(R.string.watch_bound_watches)
            setImageResource(WatchAvatarResolver.resourceFor(watch.deviceName))
        })
        val check = ImageView(context).apply {
            layoutParams = FrameLayout.LayoutParams(dp(18), dp(18), android.view.Gravity.BOTTOM or android.view.Gravity.END)
            contentDescription = null
            setImageResource(R.drawable.watch_icon_check)
            visibility = if (watch == selectedWatch) View.VISIBLE else View.GONE
        }
        avatar.addView(check)
        item.addView(avatar)

        val title = TextView(context).apply {
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT)
            setPadding(0, dp(4), 0, 0)
            text = watch.deviceName
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
            setTextColor(ContextCompat.getColor(context, if (watch == selectedWatch) R.color.watch_trust_blue else R.color.watch_text_primary))
            textSize = 11f
        }
        item.addView(title)
        item.tag = TargetViews(avatar, check, title)
        item.setOnClickListener {
            selectedWatch = watch
            updateTargetSelection(item)
        }
        return item
    }

    private fun updateTargetSelection(selected: View) {
        val targets = findViewById<LinearLayout>(R.id.watch_picker_targets)
        for (index in 0 until targets.childCount) {
            val item = targets.getChildAt(index)
            val state = item.tag as? TargetViews ?: continue
            val isSelected = item === selected
            state.avatar.background = if (isSelected) {
                ContextCompat.getDrawable(context, R.drawable.watch_call_picker_avatar_selected)
            } else {
                ColorDrawable(Color.TRANSPARENT)
            }
            state.check.visibility = if (isSelected) View.VISIBLE else View.GONE
            state.title.setTextColor(ContextCompat.getColor(context, if (isSelected) R.color.watch_trust_blue else R.color.watch_text_primary))
        }
    }

    private data class TargetViews(val avatar: FrameLayout, val check: ImageView, val title: TextView)

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private fun dismiss() {
        if (dismissing) return
        dismissing = true
        val sheet = findViewById<View>(R.id.watch_call_picker_sheet)
        val scrim = findViewById<View>(R.id.watch_call_picker_scrim)
        scrim.animate().alpha(0f).setDuration(160L).start()
        sheet.animate()
            .translationY(sheet.height.toFloat())
            .setDuration(220L)
            .setInterpolator(android.view.animation.DecelerateInterpolator(1.7f))
            .withEndAction { (parent as? android.view.ViewGroup)?.removeView(this) }
            .start()
    }

}
