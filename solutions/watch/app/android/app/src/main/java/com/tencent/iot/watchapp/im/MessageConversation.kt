package com.tencent.iot.watchapp.im
import com.tencent.iot.watchapp.R
import com.tencent.iot.watchapp.watch.WatchAvatarResolver
import com.tencent.iot.watchapp.watch.BoundWatch

data class MessageConversation(
    val key: String,
    val titleRes: Int,
    val avatarRes: Int,
    val isGroup: Boolean,
    val conversationId: String = key,
    val peerId: String = key,
    val groupId: String? = null,
    val displayName: String? = null,
    val preview: String = "",
    val timestamp: Long = 0L,
    val unreadCount: Int = 0,
    val isPinned: Boolean = false,
    val isMuted: Boolean = false,
    val isLocalBinding: Boolean = false,
    val groupMemberAvatarRes: List<Int> = emptyList(),
)

fun BoundWatch.toMessageConversation(): MessageConversation = MessageConversation(
    key = "c2c_$deviceName",
    titleRes = R.string.watch_chat_default_title,
    avatarRes = WatchAvatarResolver.resourceFor(deviceName),
    isGroup = false,
    conversationId = "c2c_$deviceName",
    peerId = deviceName,
    displayName = deviceName,
    isLocalBinding = true,
)
