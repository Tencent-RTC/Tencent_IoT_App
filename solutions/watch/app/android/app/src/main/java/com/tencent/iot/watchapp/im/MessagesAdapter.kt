package com.tencent.iot.watchapp.im
import com.tencent.iot.watchapp.R
import com.tencent.iot.watchapp.watch.GroupAvatarComposer

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MessagesAdapter(
    private val onConversationClick: (MessageConversation) -> Unit,
) : RecyclerView.Adapter<MessagesAdapter.ConversationViewHolder>() {
    private val items = mutableListOf<MessageConversation>()

    fun submitConversations(conversations: List<WatchImConversation>) {
        items.clear()
        items.addAll(conversations.map(ConversationMapper::toMessageConversation))
        notifyDataSetChanged()
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ConversationViewHolder {
        return ConversationViewHolder(
            LayoutInflater.from(parent.context).inflate(R.layout.watch_message_dynamic_item, parent, false),
        )
    }

    override fun onBindViewHolder(holder: ConversationViewHolder, position: Int) {
        holder.bind(items[position])
    }

    override fun getItemCount(): Int = items.size

    inner class ConversationViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        private val avatar: ImageView = itemView.findViewById(R.id.watch_message_dynamic_avatar)
        private val title: TextView = itemView.findViewById(R.id.watch_message_dynamic_title)
        private val preview: TextView = itemView.findViewById(R.id.watch_message_dynamic_preview)
        private val time: TextView = itemView.findViewById(R.id.watch_message_dynamic_time)
        private val unread: TextView = itemView.findViewById(R.id.watch_message_dynamic_unread)

        fun bind(conversation: MessageConversation) {
            if (conversation.isGroup && conversation.groupMemberAvatarRes.size > 1) {
                avatar.setImageDrawable(
                    GroupAvatarComposer.create(itemView.context, conversation.groupMemberAvatarRes),
                )
            } else {
                avatar.setImageResource(conversation.avatarRes)
            }
            title.text = conversation.displayName ?: itemView.context.getString(conversation.titleRes)
            preview.text = conversation.preview
            time.text = formatTime(conversation.timestamp)
            unread.visibility = if (conversation.unreadCount > 0) View.VISIBLE else View.GONE
            unread.text = if (conversation.unreadCount > 99) "99+" else conversation.unreadCount.toString()
            itemView.setOnClickListener { onConversationClick(conversation) }
        }

        private fun formatTime(timestamp: Long): String {
            if (timestamp <= 0L) return ""
            val millis = if (timestamp < 10_000_000_000L) timestamp * 1000L else timestamp
            val format = when {
                android.text.format.DateUtils.isToday(millis) -> SimpleDateFormat("HH:mm", Locale.getDefault())
                isYesterday(millis) -> return itemView.context.getString(R.string.watch_time_yesterday)
                else -> SimpleDateFormat("MM/dd", Locale.getDefault())
            }
            return format.format(Date(millis))
        }

        private fun isYesterday(millis: Long): Boolean {
            val yesterday = java.util.Calendar.getInstance().apply { add(java.util.Calendar.DAY_OF_YEAR, -1) }
            val target = java.util.Calendar.getInstance().apply { timeInMillis = millis }
            return yesterday.get(java.util.Calendar.ERA) == target.get(java.util.Calendar.ERA) &&
                yesterday.get(java.util.Calendar.YEAR) == target.get(java.util.Calendar.YEAR) &&
                yesterday.get(java.util.Calendar.DAY_OF_YEAR) == target.get(java.util.Calendar.DAY_OF_YEAR)
        }
    }
}
