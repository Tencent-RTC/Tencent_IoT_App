package com.tencent.iot.watchapp.im
import com.tencent.iot.watchapp.R
import com.tencent.iot.watchapp.app.MainActivity
import com.tencent.iot.watchapp.watch.WatchAvatarResolver

import android.content.Context
import android.util.AttributeSet
import android.view.Gravity
import android.view.KeyEvent
import android.view.LayoutInflater
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast

class ChatView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0,
) : FrameLayout(context, attrs, defStyleAttr) {
    private val title: TextView
    private val infoButton: ImageButton
    private val draftInput: EditText
    private val inputModeButton: ImageButton
    private val sendButton: ImageButton
    private val voiceAction: TextView
    private val historyScroll: ScrollView
    private val dynamicHistory: LinearLayout

    private var conversation: MessageConversation? = null
    private var textMode = false
    private var sending = false

    init {
        LayoutInflater.from(context).inflate(R.layout.watch_chat_view, this, true)
        title = findViewById(R.id.watch_chat_title)
        infoButton = findViewById(R.id.watch_chat_info)
        draftInput = findViewById(R.id.watch_chat_draft)
        inputModeButton = findViewById(R.id.watch_chat_input_mode)
        sendButton = findViewById(R.id.watch_chat_send)
        voiceAction = findViewById(R.id.watch_chat_voice_action)
        historyScroll = findViewById(R.id.watch_chat_history)
        dynamicHistory = findViewById(R.id.watch_dynamic_chat_history)

        inputModeButton.setOnClickListener { setTextMode(!textMode) }
        sendButton.setOnClickListener { sendCurrentText() }
        draftInput.setOnEditorActionListener { _, actionId, event ->
            val sendByEnter = actionId == EditorInfo.IME_ACTION_SEND ||
                (event?.keyCode == KeyEvent.KEYCODE_ENTER && !event.isShiftPressed)
            if (sendByEnter) {
                sendCurrentText()
                true
            } else {
                false
            }
        }
    }

    fun configure(conversation: MessageConversation, draft: String) {
        this.conversation = conversation
        title.text = conversation.displayName ?: context.getString(conversation.titleRes)
        infoButton.contentDescription = context.getString(if (conversation.isGroup) R.string.watch_group_info else R.string.watch_chat_members)
        draftInput.setText(draft)
        draftInput.setSelection(draftInput.text.length)
        dynamicHistory.visibility = VISIBLE
        setTextMode(false)
    }

    fun renderMessages(messages: List<WatchImMessage>) {
        dynamicHistory.removeAllViews()
        dynamicHistory.visibility = VISIBLE
        dynamicHistory.setTag(R.id.watch_dynamic_message_cache, messages.toMutableList())
        dynamicHistory.tag = messages.map { it.messageId }.toMutableSet()
        if (messages.isEmpty()) {
            dynamicHistory.addView(TextView(context).apply {
                text = context.getString(R.string.watch_chat_empty)
                setTextColor(context.getColor(R.color.watch_text_tertiary))
                textSize = 13f
                gravity = Gravity.CENTER
                setPadding(0, dp(48), 0, dp(48))
            })
            scrollHistoryToBottom()
            return
        }
        messages.forEachIndexed { index, message ->
            if (index == 0 || !sameDay(messages[index - 1].timestamp, message.timestamp)) {
                dynamicHistory.addView(TextView(context).apply {
                    text = formatTimestamp(message.timestamp)
                    setTextColor(context.getColor(R.color.watch_text_tertiary))
                    textSize = 11f
                    gravity = Gravity.CENTER
                    setPadding(0, dp(if (index == 0) 0 else 16), 0, dp(10))
                })
            }
            if (!message.isSelf && conversation?.isGroup == true) {
                dynamicHistory.addView(TextView(context).apply {
                    text = message.senderName
                    setTextColor(context.getColor(R.color.watch_text_secondary))
                    textSize = 11f
                    setPadding(0, 0, 0, dp(5))
                })
            }
            dynamicHistory.addView(createMessageRow(message))
        }
        scrollHistoryToBottom()
    }

    fun appendMessage(message: WatchImMessage) {
        val existing = dynamicHistory.tag as? MutableSet<String> ?: mutableSetOf<String>().also { dynamicHistory.tag = it }
        if (!existing.add(message.messageId)) return
        val current = (dynamicHistory.getTag(R.id.watch_dynamic_message_cache) as? MutableList<WatchImMessage> ?: mutableListOf()).also {
            it.add(message)
            dynamicHistory.setTag(R.id.watch_dynamic_message_cache, it)
        }
        renderMessages(current.sortedBy { it.timestamp })
    }

    fun mergeMessages(messages: List<WatchImMessage>) {
        if (messages.isEmpty()) return
        val current = (dynamicHistory.getTag(R.id.watch_dynamic_message_cache) as? List<WatchImMessage>).orEmpty()
        val merged = (current + messages).distinctBy { it.messageId }.sortedBy { it.timestamp }
        if (merged.size == current.size) return
        renderMessages(merged)
    }

    fun messageCount(): Int =
        (dynamicHistory.getTag(R.id.watch_dynamic_message_cache) as? List<WatchImMessage>).orEmpty().size

    private fun scrollHistoryToBottom() {
        historyScroll.post { historyScroll.fullScroll(FOCUS_DOWN) }
    }

    fun renderMessagesWithDraftCleared(message: WatchImMessage) {
        draftInput.text?.clear()
        appendMessage(message)
    }

    fun clearHistory() {
        renderMessages(emptyList())
    }

    fun currentDraft(): String = draftInput.text.toString()

    fun currentConversation(): MessageConversation? = conversation

    fun setSending(value: Boolean) {
        sending = value
        sendButton.isEnabled = !value
        inputModeButton.isEnabled = !value
    }

    fun showSendFailed() {
        Toast.makeText(context, R.string.watch_chat_send_failed, Toast.LENGTH_SHORT).show()
    }

    private fun sendCurrentText() {
        if (sending) return
        val text = draftInput.text.toString().trim()
        if (text.isBlank()) return
        (context as? MainActivity)?.onChatSendRequested(conversation, text)
    }

    private fun setTextMode(enabled: Boolean) {
        textMode = enabled
        inputModeButton.setImageResource(if (enabled) R.drawable.watch_icon_voice_design else R.drawable.watch_icon_keyboard_design)
        inputModeButton.contentDescription = context.getString(if (enabled) R.string.watch_chat_switch_voice_input else R.string.watch_chat_switch_text)
        draftInput.visibility = if (enabled) VISIBLE else GONE
        sendButton.visibility = if (enabled) VISIBLE else GONE
        voiceAction.visibility = if (enabled) GONE else VISIBLE
        if (enabled) draftInput.requestFocus()
    }

    private fun createMessageRow(message: WatchImMessage): LinearLayout {
        val row = LinearLayout(context).apply {
            layoutParams = LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
                topMargin = dp(8)
            }
            gravity = if (message.isSelf) Gravity.TOP or Gravity.END else Gravity.TOP or Gravity.START
            orientation = LinearLayout.HORIZONTAL
        }
        val avatar = ImageView(context).apply {
            layoutParams = LinearLayout.LayoutParams(dp(30), dp(30)).apply {
                if (message.isSelf) marginStart = dp(8) else marginEnd = dp(8)
            }
            setImageResource(if (message.isSelf) WatchAvatarResolver.resourceFor(ImService.loggedInUserId) else incomingAvatar(message))
        }
        val bubble = TextView(context).apply {
            layoutParams = LinearLayout.LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT)
            setPadding(dp(12), dp(10), dp(12), dp(10))
            setTextColor(context.getColor(R.color.watch_text_primary))
            textSize = 14f
            text = message.text
            background = context.getDrawable(if (message.isSelf) R.drawable.watch_chat_bubble_outgoing else R.drawable.watch_chat_bubble_incoming)
        }
        if (message.isSelf) {
            row.addView(bubble)
            row.addView(avatar)
        } else {
            row.addView(avatar)
            row.addView(bubble)
        }
        return row
    }

    private fun incomingAvatar(message: WatchImMessage): Int {
        return WatchAvatarResolver.resourceFor(
            message.senderId.ifBlank { conversation?.peerId.orEmpty() },
        )
    }

    private fun formatTimestamp(timestamp: Long): String {
        val millis = if (timestamp < 10_000_000_000L) timestamp * 1000L else timestamp
        return java.text.SimpleDateFormat("MM-dd HH:mm", java.util.Locale.getDefault()).format(java.util.Date(millis))
    }

    private fun sameDay(first: Long, second: Long): Boolean {
        val firstCalendar = java.util.Calendar.getInstance().apply { timeInMillis = if (first < 10_000_000_000L) first * 1000L else first }
        val secondCalendar = java.util.Calendar.getInstance().apply { timeInMillis = if (second < 10_000_000_000L) second * 1000L else second }
        return firstCalendar.get(java.util.Calendar.YEAR) == secondCalendar.get(java.util.Calendar.YEAR) &&
            firstCalendar.get(java.util.Calendar.DAY_OF_YEAR) == secondCalendar.get(java.util.Calendar.DAY_OF_YEAR)
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
}
