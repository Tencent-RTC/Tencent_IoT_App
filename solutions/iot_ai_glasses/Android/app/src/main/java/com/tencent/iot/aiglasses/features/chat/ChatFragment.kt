package com.tencent.iot.aiglasses.features.chat

import com.tencent.iot.aiglasses.components.attachTopScrollShadow
import android.content.Context
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.view.isVisible
import androidx.fragment.app.Fragment
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.tencent.iot.aiglasses.R
import com.tencent.iot.aiglasses.app.AppDialog
import com.tencent.iot.aiglasses.app.RootActivity
import com.tencent.iot.aiglasses.app.router
import com.tencent.iot.aiglasses.components.InlineHint
import com.tencent.iot.aiglasses.components.ThinkingDots
import com.tencent.iot.aiglasses.databinding.FragmentChatBinding
import com.tencent.iot.aiglasses.designsystem.AppIcon
import com.tencent.iot.aiglasses.designsystem.color
import com.tencent.iot.aiglasses.designsystem.dp
import com.tencent.iot.aiglasses.designsystem.dpInt
import com.tencent.iot.aiglasses.designsystem.ovalDrawable
import com.tencent.iot.aiglasses.designsystem.roundedDrawable
import com.tencent.iot.aiglasses.designsystem.setAppIcon
import com.tencent.iot.aiglasses.observeState
import com.tencent.iot.aiglasses.state
import java.util.UUID

class ChatFragment : Fragment(R.layout.fragment_chat) {

    private var _binding: FragmentChatBinding? = null
    private val adapter = TurnAdapter(
        onRetry = { id ->
            if (_binding != null && isResumed && !isHidden && state.canStartCapture) {
                if (state.session != null) state.dialog = AppDialog.Conflict else state.chat.retry(id)
            }
        }
    )
    private var lastKey: Pair<Int, String>? = null
    private var captureRequestID: UUID? = null

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        val binding = FragmentChatBinding.bind(view)
        binding.thread.attachTopScrollShadow(binding.root)
        _binding = binding
        val context = requireContext()
        binding.header.setBackLabel("返回首页")
        binding.header.setOnBack { router.pop() }
        binding.thread.layoutManager = LinearLayoutManager(context)
        binding.thread.adapter = adapter
        binding.thread.itemAnimator = null
        binding.thread.addItemDecoration(object : RecyclerView.ItemDecoration() {
            override fun getItemOffsets(outRect: android.graphics.Rect, view: View, parent: RecyclerView, state: RecyclerView.State) {
                if (parent.getChildAdapterPosition(view) > 0) outRect.top = context.dpInt(16f)
            }
        })
        binding.liveBar.leading.setOnClickListener { state.chat.toggleReadsAloud() }
        binding.liveBar.pill.setOnClickListener { toggleAsk() }
        binding.liveBar.trailing.setOnClickListener {
            captureRequestID = null
            state.chat.interrupt("已停止")
        }
        observeState(::render)
    }

    override fun onHiddenChanged(hidden: Boolean) {
        super.onHiddenChanged(hidden)
        if (hidden) {
            captureRequestID = null
            state.chat.interrupt("已停止聆听", quiet = true)
        }
    }

    override fun onStop() {
        super.onStop()
        captureRequestID = null
        state.chat.interrupt("已停止聆听", quiet = true)
    }

    override fun onDestroyView() {
        captureRequestID = null
        state.chat.interrupt("已停止聆听", quiet = true)
        _binding?.thread?.adapter = null
        super.onDestroyView()
        _binding = null
        lastKey = null
    }

    private fun toggleAsk() {
        val binding = _binding ?: return
        val chat = state.chat
        if (chat.isListening) {
            captureRequestID = null
            chat.pauseListening()
            return
        }
        if (!isResumed || isHidden || !state.canStartCapture) return
        if (state.session != null) {
            state.dialog = AppDialog.Conflict
            return
        }
        val requestID = UUID.randomUUID()
        captureRequestID = requestID
        (requireActivity() as RootActivity).withMicrophone {
            if (captureRequestID != requestID) return@withMicrophone
            captureRequestID = null
            if (_binding !== binding || !isAdded || !isResumed || isHidden || !state.canStartCapture) return@withMicrophone
            if (state.session != null) {
                state.dialog = AppDialog.Conflict
                return@withMicrophone
            }
            state.chat.beginQuestion()
        }
    }

    private fun render() {
        val binding = _binding ?: return
        val chat = state.chat
        binding.header.setConnected(state.isConnected)
        binding.empty.isVisible = chat.isEmpty
        binding.thread.isVisible = !chat.isEmpty
        val key = chat.turns.size to chat.turns.lastOrNull()?.let { it.displayQuestion + it.phase + it.answer }.orEmpty()
        val canRetry = chat.canRetry && state.canStartCapture && state.session == null
        adapter.submitList(chat.turns.map { TurnRow(it, canRetry, chat.speakingTurnID == it.id) }) {
            if (_binding === binding) {
                if (key != lastKey && chat.turns.isNotEmpty()) binding.thread.smoothScrollToPosition(chat.turns.lastIndex)
                lastKey = key
            }
        }
        when {
            !state.isConnected -> {
                binding.hint.isVisible = true
                binding.hint.set(InlineHint.Tone.ERROR, "眼镜未连接，无法收音提问。", "重新连接") { state.reconnect() }
            }
            !state.isOnline -> {
                binding.hint.isVisible = true
                binding.hint.set(InlineHint.Tone.WARNING, "网络中断，暂不能提问。")
            }
            else -> binding.hint.isVisible = false
        }
        binding.liveBar.setButton(
            binding.liveBar.leading,
            AppIcon.SPEAKER.res,
            if (chat.readsAloud) "关闭回答播报" else "开启回答播报",
            tint = if (chat.readsAloud) R.color.text_primary else R.color.icon_muted
        )
        val listening = chat.isListening
        binding.liveBar.setPill(
            if (listening) AppIcon.PAUSE.res else AppIcon.MIC.res,
            if (listening) "正在聆听" else "点击开始提问",
            if (listening) "暂停聆听" else "开始聆听",
            enabled = listening || state.canStartCapture
        )
        binding.liveBar.setButton(binding.liveBar.trailing, AppIcon.STOP.res, "停止", enabled = chat.isBusy || chat.speakingTurnID != null)
    }
}

private data class TurnRow(val turn: ChatTurn, val canRetry: Boolean, val isSpeaking: Boolean)

private class TurnAdapter(
    private val onRetry: (UUID) -> Unit
) : ListAdapter<TurnRow, RecyclerView.ViewHolder>(DIFF) {
    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
        val view = ChatTurnView(parent.context).apply {
            layoutParams = RecyclerView.LayoutParams(RecyclerView.LayoutParams.MATCH_PARENT, RecyclerView.LayoutParams.WRAP_CONTENT)
        }
        return object : RecyclerView.ViewHolder(view) {}
    }

    override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
        val row = getItem(position)
        (holder.itemView as ChatTurnView).set(row.turn, row.canRetry, row.isSpeaking, onRetry)
    }

    private companion object {
        val DIFF = object : DiffUtil.ItemCallback<TurnRow>() {
            override fun areItemsTheSame(oldItem: TurnRow, newItem: TurnRow) = oldItem.turn.id == newItem.turn.id
            override fun areContentsTheSame(oldItem: TurnRow, newItem: TurnRow) = oldItem == newItem
        }
    }
}

private class ChatTurnView(context: Context) : LinearLayout(context) {

    private val bubbleText = TextView(context).apply {
        setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 14.5f)
        setTextColor(context.color(R.color.caption_text))
        setLineSpacing(context.dp(4f), 1f)
        setPadding(context.dpInt(14f), context.dpInt(10f), context.dpInt(14f), context.dpInt(10f))
        background = context.roundedDrawable(16f, R.color.accent_soft, R.color.caption_latest_active_border)
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
    }
    private val liveLabel = tag("实时识别中")
    private val interruptedLabel = TextView(context).apply {
        text = "本轮已中断"
        setTextAppearance(R.style.TextAppearance_Suisheng_Caption)
        setTextColor(context.color(R.color.text_secondary))
    }
    private val answerRow = LinearLayout(context)
    private val answerBody = LinearLayout(context).apply { orientation = VERTICAL }
    private val speakingLabel = LinearLayout(context).apply {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        addView(ImageView(context).apply { setAppIcon(AppIcon.SPEAKER, R.color.caption_latest_active_tag) }, LayoutParams(context.dpInt(13f), context.dpInt(13f)))
        addView(TextView(context).apply {
            text = "正在眼镜中播报"
            setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 11f)
            setTextColor(context.color(R.color.caption_latest_active_tag))
        }, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply { marginStart = context.dpInt(5f) })
    }

    init {
        orientation = VERTICAL
        clipChildren = false
        addView(bubbleText, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
            gravity = Gravity.END
            marginStart = context.dpInt(56f)
        })
        addView(liveLabel, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
            gravity = Gravity.END
            topMargin = context.dpInt(6f)
        })
        addView(interruptedLabel, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
            gravity = Gravity.END
            topMargin = context.dpInt(6f)
        })
        addView(answerRow.apply {
            orientation = HORIZONTAL
            addView(ImageView(context).apply {
                setImageResource(R.drawable.mi_sparkle)
                setColorFilter(context.color(R.color.accent))
                val inset = context.dpInt(7f)
                setPadding(inset, inset, inset, inset)
                background = context.ovalDrawable(R.color.accent_soft)
                importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
            }, LayoutParams(context.dpInt(30f), context.dpInt(30f)).apply { marginEnd = context.dpInt(10f) })
            addView(LinearLayout(context).apply {
                orientation = VERTICAL
                setPadding(context.dpInt(14f), context.dpInt(12f), context.dpInt(14f), context.dpInt(12f))
                background = context.roundedDrawable(18f, R.color.caption_card, R.color.caption_border)
                addView(answerBody, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))
                addView(speakingLabel, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply { topMargin = context.dpInt(10f) })
            }, LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f))
        }, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
            marginEnd = context.dpInt(24f)
            topMargin = context.dpInt(12f)
        })
    }

    fun set(turn: ChatTurn, canRetry: Boolean, isSpeaking: Boolean, onRetry: (UUID) -> Unit) {
        val live = turn.phase == ChatTurn.Phase.LISTENING
        bubbleText.text = turn.displayQuestion
        bubbleText.isVisible = turn.displayQuestion.isNotEmpty()
        bubbleText.contentDescription = if (live) "提问，识别中：${turn.displayQuestion}" else "提问：${turn.displayQuestion}"
        liveLabel.isVisible = live
        interruptedLabel.isVisible = turn.phase == ChatTurn.Phase.INTERRUPTED
        answerRow.isVisible = turn.phase == ChatTurn.Phase.THINKING || turn.phase == ChatTurn.Phase.DONE || turn.phase == ChatTurn.Phase.FAILED
        speakingLabel.isVisible = isSpeaking
        answerBody.removeAllViews()
        when (turn.phase) {
            ChatTurn.Phase.DONE -> {
                answerBody.addView(body(turn.answer.orEmpty(), R.color.caption_text).apply { setLineSpacing(context.dp(5f), 1f) })
            }
            ChatTurn.Phase.THINKING -> answerBody.addView(row(ThinkingDots(context), "思考中…"))
            ChatTurn.Phase.LISTENING, ChatTurn.Phase.INTERRUPTED -> Unit
            ChatTurn.Phase.FAILED -> {
                answerBody.addView(body("回答生成失败，请检查网络后重试。", R.color.caption_error_text))
                if (turn.question.isNotEmpty()) {
                    answerBody.addView(Button(context, null, 0, R.style.Widget_Suisheng_Button_Pill).apply {
                        text = "重试"
                        isEnabled = canRetry
                        setOnClickListener { onRetry(turn.id) }
                    }, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply { topMargin = context.dpInt(10f) })
                }
            }
        }
    }

    private fun tag(label: String) = LinearLayout(context).apply {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        addView(View(context).apply { background = context.ovalDrawable(R.color.caption_latest_active_tag) }, LayoutParams(context.dpInt(5f), context.dpInt(5f)))
        addView(TextView(context).apply {
            text = label
            setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 11f)
            setTextColor(context.color(R.color.caption_latest_active_tag))
        }, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply { marginStart = context.dpInt(5f) })
    }

    private fun body(text: String, tint: Int) = TextView(context).apply {
        setTextAppearance(R.style.TextAppearance_Suisheng_Body)
        setTextColor(context.color(tint))
        this.text = text
    }

    private fun row(indicator: View, label: String) = LinearLayout(context).apply {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        addView(indicator)
        addView(body(label, R.color.text_secondary), LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply {
            marginStart = context.dpInt(8f)
        })
    }
}
