package com.tencent.iot.aiglasses.features.meeting

import android.os.Bundle
import android.view.View
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AlertDialog
import androidx.core.view.isVisible
import androidx.fragment.app.Fragment
import com.tencent.iot.aiglasses.R
import com.tencent.iot.aiglasses.app.AppDialog
import com.tencent.iot.aiglasses.app.router
import com.tencent.iot.aiglasses.components.InlineHint
import com.tencent.iot.aiglasses.databinding.FragmentMeetingLiveBinding
import com.tencent.iot.aiglasses.designsystem.AppIcon
import com.tencent.iot.aiglasses.models.Clock
import com.tencent.iot.aiglasses.models.SessionKind
import com.tencent.iot.aiglasses.observeState
import com.tencent.iot.aiglasses.state

class MeetingLiveFragment : Fragment(R.layout.fragment_meeting_live) {

    private var _binding: FragmentMeetingLiveBinding? = null
    private var leaving = false
    private var speakerIndex: Map<String, Int> = emptyMap()
    private var speaking = false
    private val backCallback = object : OnBackPressedCallback(true) {
        override fun handleOnBackPressed() {
            state.dialog = if (state.dialog == null) AppDialog.EndSession else null
        }
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        val binding = FragmentMeetingLiveBinding.bind(view)
        binding.transcript.attachTopShadow(binding.root)
        _binding = binding
        binding.header.setBackLabel("返回")
        binding.header.setOnBack { state.dialog = AppDialog.EndSession }
        binding.header.setOnSettings(::showSettings)
        binding.liveBar.leading.setOnClickListener { state.toggleStar() }
        binding.liveBar.setButton(binding.liveBar.trailing, AppIcon.STOP.res, "结束记录")
        binding.liveBar.pill.setOnClickListener { state.togglePause() }
        binding.liveBar.trailing.setOnClickListener { state.dialog = AppDialog.EndSession }
        requireActivity().onBackPressedDispatcher.addCallback(viewLifecycleOwner, backCallback)
        backCallback.isEnabled = !isHidden
        binding.transcript.createCard = { MeetingCard(it) }
        binding.transcript.bindCard = { card, item ->
            (card as MeetingCard).set(item.index, item.line, item.isLatest, speakerIndex[item.line.speakerLabel.orEmpty()] ?: 0, item.isLatest && speaking)
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

    private fun showSettings() {
        AlertDialog.Builder(requireContext())
            .setTitle("会议设置")
            .setMultiChoiceItems(arrayOf("保留原始录音"), booleanArrayOf(state.keepsMeetingAudio)) { _, _, isChecked ->
                state.updateKeepsMeetingAudio(isChecked)
            }
            .setPositiveButton("完成", null)
            .show()
    }

    private fun render() {
        val binding = _binding ?: return
        val session = state.session
        if (session == null || session.kind != SessionKind.MEETING) {
            if (!leaving && !isHidden) {
                leaving = true
                binding.root.post { if (isAdded) router.popToRoot() }
            }
            return
        }
        binding.header.setConnected(state.isConnected)
        when {
            !state.isConnected -> {
                binding.hint.isVisible = true
                binding.hint.set(InlineHint.Tone.ERROR, "眼镜已断开，已有文字已保留。断连期间的音频无法补回。", "重新连接") { state.reconnect() }
            }
            !state.isOnline -> {
                binding.hint.isVisible = true
                binding.hint.set(InlineHint.Tone.WARNING, "网络中断，转录暂停更新。")
            }
            else -> binding.hint.isVisible = false
        }
        speakerIndex = MeetingSpeakerIndex.map(session.entries)
        speaking = !session.isPaused && state.canProcess
        binding.transcript.set(session.entries, session.isPaused)
        val starred = session.isStarred
        binding.liveBar.setButton(
            binding.liveBar.leading,
            if (starred) R.drawable.mi_star else R.drawable.mi_star_border,
            if (starred) "取消星标" else "将本场会议标为星标",
            tint = if (starred) R.color.accent else R.color.text_primary
        )
        val paused = session.isPaused
        binding.liveBar.setPill(
            if (paused) AppIcon.PLAY.res else AppIcon.PAUSE.res,
            "${if (paused) "已暂停" else "正在转录"} · ${Clock.text(session.seconds)}",
            if (paused) "继续记录" else "暂停记录"
        )
    }
}
