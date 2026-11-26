package com.tencent.iot.watchapp.im
import com.tencent.iot.watchapp.R

/** 将 IM 服务模型转换为页面使用的会话模型。 */
object ConversationMapper {
    fun toMessageConversation(conversation: WatchImConversation): MessageConversation = MessageConversation(
        key = conversation.conversationId,
        titleRes = if (conversation.isGroup) R.string.watch_message_family else R.string.watch_chat_default_title,
        avatarRes = conversation.avatarRes,
        isGroup = conversation.isGroup,
        conversationId = conversation.conversationId,
        peerId = conversation.peerId,
        groupId = conversation.groupId,
        displayName = conversation.title,
        preview = conversation.preview,
        timestamp = conversation.timestamp,
        unreadCount = conversation.unreadCount,
        isPinned = conversation.isPinned,
        isMuted = conversation.isMuted,
        isLocalBinding = conversation.isLocalBinding,
        groupMemberAvatarRes = conversation.groupMemberAvatarRes,
    )
}
