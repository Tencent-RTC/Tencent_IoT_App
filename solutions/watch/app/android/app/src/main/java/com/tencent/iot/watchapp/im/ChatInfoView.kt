package com.tencent.iot.watchapp.im
import com.tencent.iot.watchapp.R
import com.tencent.iot.watchapp.app.MainActivity

import android.content.Context
import android.util.AttributeSet
import android.view.LayoutInflater
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.widget.SwitchCompat

class ChatInfoView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0,
) : FrameLayout(context, attrs, defStyleAttr) {
    private val title: TextView
    private val personalContent: View
    private val groupContent: View
    private val groupMemberStrip: LinearLayout
    private var conversation: MessageConversation? = null
    private var inviteAction: ((MessageConversation) -> Unit)? = null

    fun setInviteAction(action: (MessageConversation) -> Unit) {
        inviteAction = action
    }

    init {
        LayoutInflater.from(context).inflate(R.layout.watch_chat_info_view, this, true)
        title = findViewById(R.id.watch_chat_info_title)
        personalContent = findViewById(R.id.watch_personal_chat_info)
        groupContent = findViewById(R.id.watch_group_chat_info)
        groupMemberStrip = findViewById(R.id.watch_group_member_strip)
    }

    fun configure(conversation: MessageConversation) {
        this.conversation = conversation
        title.setText(if (conversation.isGroup) R.string.watch_group_info_title else R.string.watch_chat_info_title)
        personalContent.visibility = if (conversation.isGroup) View.GONE else View.VISIBLE
        groupContent.visibility = if (conversation.isGroup) View.VISIBLE else View.GONE
        val activeContent = if (conversation.isGroup) groupContent else personalContent
        val muteSwitch = activeContent.findViewById<SwitchCompat>(R.id.watch_chat_mute_switch)
        val pinSwitch = activeContent.findViewById<SwitchCompat>(R.id.watch_chat_pin_switch)
        muteSwitch.setOnCheckedChangeListener(null)
        pinSwitch.setOnCheckedChangeListener(null)
        muteSwitch.isChecked = conversation.isMuted
        pinSwitch.isChecked = conversation.isPinned
        muteSwitch.setOnCheckedChangeListener { _, checked ->
            conversation?.let { (context as? MainActivity)?.onChatMuteChanged(it, checked) }
        }
        pinSwitch.setOnCheckedChangeListener { _, checked ->
            conversation?.let { (context as? MainActivity)?.onChatPinChanged(it, checked) }
        }
        activeContent.findViewById<TextView>(R.id.watch_chat_clear_action).setOnClickListener {
            conversation?.let { (context as? MainActivity)?.onChatClearRequested(it) }
        }
        if (conversation.isGroup) {
            activeContent.findViewById<TextView>(R.id.watch_chat_group_name_value).text = conversation.displayName.orEmpty()
            renderGroupMembers(emptyList())
            ImService.loadGroupMembers(conversation) { result ->
                post { renderGroupMembers(result.getOrDefault(emptyList())) }
            }
        } else {
            val memberAvatar = personalContent.findViewById<ImageView>(R.id.watch_chat_member_avatar)
            val memberName = personalContent.findViewById<TextView>(R.id.watch_chat_member_name)
            val displayName = conversation.displayName ?: conversation.peerId
            memberAvatar.setImageResource(conversation.avatarRes)
            memberAvatar.contentDescription = displayName
            memberName.text = displayName
            personalContent.findViewById<ImageButton>(R.id.watch_chat_member_add).setOnClickListener {
                inviteAction?.invoke(conversation)
            }
        }
    }

    private fun renderGroupMembers(members: List<WatchImGroupMember>) {
        groupMemberStrip.removeAllViews()
        members.forEach { member ->
            groupMemberStrip.addView(memberView(member.displayName, member.avatarRes))
        }
        groupMemberStrip.addView(ImageButton(context).apply {
            layoutParams = LinearLayout.LayoutParams(dp(56), dp(56)).apply { marginStart = dp(2) }
            background = context.getDrawable(R.drawable.watch_chat_member_add)
            contentDescription = context.getString(R.string.watch_chat_invite_member)
            setPadding(dp(18), dp(18), dp(18), dp(18))
            setImageResource(R.drawable.watch_icon_plus)
            setOnClickListener { conversation?.let { inviteAction?.invoke(it) } }
        })
    }

    private fun memberView(name: String, avatarRes: Int): View = LinearLayout(context).apply {
        layoutParams = LinearLayout.LayoutParams(dp(56), LayoutParams.WRAP_CONTENT)
        gravity = android.view.Gravity.CENTER_HORIZONTAL
        orientation = LinearLayout.VERTICAL
        addView(ImageView(context).apply {
            layoutParams = LinearLayout.LayoutParams(dp(48), dp(48))
            setImageResource(avatarRes)
            contentDescription = name
        })
        addView(TextView(context).apply {
            layoutParams = LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply { topMargin = dp(5) }
            gravity = android.view.Gravity.CENTER
            text = name
            setTextColor(context.getColor(R.color.watch_text_secondary))
            textSize = 11f
        })
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
}
