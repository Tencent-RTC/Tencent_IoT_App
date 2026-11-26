package com.tencent.iot.watchapp.im
import com.tencent.iot.watchapp.R
import com.tencent.iot.watchapp.call.*
import com.tencent.iot.watchapp.config.*
import com.tencent.iot.watchapp.watch.*

import android.content.Context
import com.tencent.imsdk.v2.V2TIMAdvancedMsgListener
import com.tencent.imsdk.v2.V2TIMCallback
import com.tencent.imsdk.v2.V2TIMConversation
import com.tencent.imsdk.v2.V2TIMConversationListener
import com.tencent.imsdk.v2.V2TIMCreateGroupMemberInfo
import com.tencent.imsdk.v2.V2TIMFriendInfo
import com.tencent.imsdk.v2.V2TIMGroupInfo
import com.tencent.imsdk.v2.V2TIMGroupMemberFullInfo
import com.tencent.imsdk.v2.V2TIMManager
import com.tencent.imsdk.v2.V2TIMMessage
import com.tencent.imsdk.v2.V2TIMMessageManager
import com.tencent.imsdk.v2.V2TIMReceiveMessageOptInfo
import com.tencent.imsdk.v2.V2TIMSDKConfig
import com.tencent.imsdk.v2.V2TIMSDKListener
import com.tencent.imsdk.v2.V2TIMSimpleMsgListener
import com.tencent.imsdk.v2.V2TIMSendCallback
import com.tencent.imsdk.v2.V2TIMUserInfo
import com.tencent.imsdk.v2.V2TIMValueCallback
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.Collections
import java.util.concurrent.atomic.AtomicInteger

sealed interface ImLoginState {
    object LoggedOut : ImLoginState
    object LoggingIn : ImLoginState
    data class LoggedIn(val userId: String) : ImLoginState
    data class Failed(val code: Int, val message: String) : ImLoginState
}

data class WatchImConversation(
    val conversationId: String,
    val peerId: String,
    val groupId: String?,
    val isGroup: Boolean,
    val title: String,
    val avatarRes: Int,
    val preview: String,
    val timestamp: Long,
    val unreadCount: Int,
    val isPinned: Boolean,
    val isMuted: Boolean,
    val isLocalBinding: Boolean = false,
    val groupMemberAvatarRes: List<Int> = emptyList(),
) {
}

data class WatchImMessage(
    val messageId: String,
    val conversationId: String,
    val senderId: String,
    val senderName: String,
    val isSelf: Boolean,
    val text: String,
    val timestamp: Long,
    val status: Int,
)

data class WatchImGroupCandidate(
    val userId: String,
    val displayName: String,
    val avatarRes: Int,
    val isWatch: Boolean,
    val isCurrentUser: Boolean = false,
)

data class WatchImGroupMember(
    val userId: String,
    val displayName: String,
    val avatarRes: Int,
)

/**
 * 精简版 IMSDK 数据入口。
 *
 * 这里只保留当前设计稿需要的会话、文本消息和会话设置能力，不依赖 TUIKit 页面和主题资源。
 */
object ImService {
    private val _loginState = MutableStateFlow<ImLoginState>(ImLoginState.LoggedOut)
    val loginState: StateFlow<ImLoginState> = _loginState.asStateFlow()

    private val _conversations = MutableStateFlow<List<WatchImConversation>>(emptyList())
    val conversations: StateFlow<List<WatchImConversation>> = _conversations.asStateFlow()

    /**
     * 保留最近入站消息，避免消息到达与聊天页监听建立之间的时间窗口导致实时消息丢失。
     * 聊天页按 conversationId 过滤，并按 messageId 去重，因此回放不会重复显示。
     */
    private val _messageEvents = MutableSharedFlow<WatchImMessage>(replay = 64, extraBufferCapacity = 64)
    val messageEvents: SharedFlow<WatchImMessage> = _messageEvents.asSharedFlow()

    private val _callSignalEvents = MutableSharedFlow<IncomingCallSignal>(extraBufferCapacity = 32)
    val callSignalEvents: SharedFlow<IncomingCallSignal> = _callSignalEvents.asSharedFlow()

    private var initialized = false
    private var appContext: Context? = null
    private var currentUserId: String = ""
    private var conversationRefreshGeneration = 0
    val loggedInUserId: String get() = currentUserId
    private val handledIncomingMessageIds = Collections.synchronizedSet(mutableSetOf<String>())

    fun directConversation(peerId: String, displayName: String = peerId): MessageConversation {
        return MessageConversation(
            key = "c2c_$peerId",
            titleRes = R.string.watch_chat_default_title,
            avatarRes = WatchAvatarResolver.resourceFor(peerId),
            isGroup = false,
            conversationId = "c2c_$peerId",
            peerId = peerId,
            displayName = displayName,
            isLocalBinding = appContext?.let { context ->
                WatchBindingStore.all(context, currentUserId).any { it.deviceName == peerId }
            } == true,
        )
    }

    private val sdkListener = object : V2TIMSDKListener() {
        override fun onConnectSuccess() {
            WatchLogger.i("IMSDK connect success: loginUser=${V2TIMManager.getInstance().loginUser}")
            if (currentUserId.isNotBlank()) {
                _loginState.value = ImLoginState.LoggedIn(currentUserId)
                refreshConversations()
            }
        }

        override fun onConnectFailed(code: Int, error: String?) {
            WatchLogger.e("IMSDK connect failed: code=$code, message=${error.orEmpty()}")
            _loginState.value = ImLoginState.Failed(code, error.orEmpty())
        }

        override fun onKickedOffline() {
            currentUserId = ""
            _loginState.value = ImLoginState.Failed(-1, "IMSDK_KICKED_OFFLINE")
            _conversations.value = emptyList()
        }

        override fun onUserSigExpired() {
            _loginState.value = ImLoginState.Failed(-2, "IMSDK_USER_SIG_EXPIRED")
        }
    }

    private val conversationListener = object : V2TIMConversationListener() {
        override fun onNewConversation(conversationList: MutableList<V2TIMConversation>?) {
            logConversationChanges("new", conversationList)
            refreshConversations()
        }

        override fun onConversationChanged(conversationList: MutableList<V2TIMConversation>?) {
            logConversationChanges("changed", conversationList)
            refreshConversations()
        }

        override fun onConversationDeleted(conversationIDList: MutableList<String>?) {
            refreshConversations()
        }
    }

    private val messageListener = object : V2TIMAdvancedMsgListener() {
        override fun onRecvNewMessage(message: V2TIMMessage?) {
            message ?: return
            val rawText = message.textElem?.text.orEmpty()
            WatchLogger.i(
                "IMSDK recv message: loginUser=$currentUserId, sender=${message.sender.orEmpty()}, " +
                    "peer=${message.userID.orEmpty()}, group=${message.groupID.orEmpty()}, " +
                    "elemType=${message.elemType}, isSelf=${message.isSelf}, " +
                    "text=${rawText.replace(Regex("\\s+"), " ").take(120)}",
            )
            if (message.elemType != V2TIMMessage.V2TIM_ELEM_TYPE_TEXT) {
                WatchLogger.w("IMSDK recv message ignored: unsupported elemType=${message.elemType}")
                return
            }
            handleIncomingText(
                messageId = message.msgID.orEmpty(),
                senderId = message.sender.orEmpty(),
                senderName = message.nickName.orEmpty().ifBlank { message.sender.orEmpty() },
                groupId = message.groupID.orEmpty(),
                isSelf = message.isSelf,
                text = rawText,
                timestamp = message.timestamp,
                status = message.status,
                source = "advanced",
            )
        }
    }

    /**
     * 部分终端或旧版 IM 封装使用 SimpleMsgListener 投递 C2C 文本；保留高级监听的同时接收该回调。
     * 两条回调可能同时到达，统一按 msgID 去重。
     */
    private val simpleMessageListener = object : V2TIMSimpleMsgListener() {
        override fun onRecvC2CTextMessage(msgID: String?, sender: V2TIMUserInfo?, text: String?) {
            val senderId = sender?.userID.orEmpty()
            val messageText = text.orEmpty()
            WatchLogger.i(
                "IMSDK simple recv C2C: loginUser=$currentUserId, msgId=${msgID.orEmpty()}, " +
                    "sender=$senderId, text=${messageText.replace(Regex("\\s+"), " ").take(120)}",
            )
            handleIncomingText(
                messageId = msgID.orEmpty(),
                senderId = senderId,
                senderName = sender?.nickName.orEmpty().ifBlank { senderId },
                groupId = "",
                isSelf = false,
                text = messageText,
                timestamp = System.currentTimeMillis() / 1000,
                status = V2TIMMessage.V2TIM_MSG_STATUS_SEND_SUCC,
                source = "simple",
            )
        }
    }

    fun initialize(context: Context): Boolean {
        if (initialized) return true
        appContext = context.applicationContext
        val config = V2TIMSDKConfig().apply {
            setLogLevel(V2TIMSDKConfig.V2TIM_LOG_WARN)
        }
        val success = V2TIMManager.getInstance().initSDK(
            context.applicationContext,
            WatchSdkConfig.IM_SDK_APP_ID.toInt(),
            config,
        )
        WatchLogger.i("IMSDK initialized: success=$success, sdkAppId=${WatchSdkConfig.IM_SDK_APP_ID}")
        if (!success) {
            _loginState.value = ImLoginState.Failed(-3, "IMSDK_INIT_FAILED")
            return false
        }
        V2TIMManager.getInstance().addIMSDKListener(sdkListener)
        V2TIMManager.getConversationManager().addConversationListener(conversationListener)
        V2TIMManager.getMessageManager().addAdvancedMsgListener(messageListener)
        V2TIMManager.getInstance().addSimpleMsgListener(simpleMessageListener)
        WatchLogger.i("IMSDK listeners registered: advancedMessage=true, simpleMessage=true, conversation=true")
        initialized = true
        return true
    }

    fun login(context: Context, channel: String) {
        if (!initialize(context)) return
        val credentials = try {
            ImSdkAuth.forChannel(channel)
        } catch (error: IllegalArgumentException) {
            currentUserId = ""
            _loginState.value = ImLoginState.Failed(-5, error.message.orEmpty())
            return
        }
        if (credentials.userId.isBlank()) {
            _loginState.value = ImLoginState.Failed(-4, "IMSDK_USER_ID_EMPTY")
            return
        }
        currentUserId = credentials.userId
        _loginState.value = ImLoginState.LoggingIn
        WatchLogger.i("IMSDK login requested: sdkAppId=${credentials.sdkAppId}, userId=${credentials.userId}")
        V2TIMManager.getInstance().login(credentials.userId, credentials.userSig, object : V2TIMCallback {
            override fun onSuccess() {
                WatchLogger.i("IMSDK login success: requested=${credentials.userId}, actual=${V2TIMManager.getInstance().loginUser}")
                _loginState.value = ImLoginState.LoggedIn(credentials.userId)
                appContext?.let { context ->
                    WatchBindingStore.all(context, currentUserId).forEach { enableC2CReceiveMessage(it.deviceName) }
                }
                refreshConversations()
            }

            override fun onError(code: Int, desc: String?) {
                WatchLogger.e("IMSDK login failed: requested=${credentials.userId}, code=$code, message=${desc.orEmpty()}")
                currentUserId = ""
                _loginState.value = ImLoginState.Failed(code, desc.orEmpty())
            }
        })
    }

    fun logout() {
        if (!initialized) return
        V2TIMManager.getInstance().logout(object : V2TIMCallback {
            override fun onSuccess() = clearSession()
            override fun onError(code: Int, desc: String?) = clearSession()
        })
    }

    fun release() {
        if (!initialized) return
        V2TIMManager.getInstance().removeIMSDKListener(sdkListener)
        V2TIMManager.getConversationManager().removeConversationListener(conversationListener)
        V2TIMManager.getMessageManager().removeAdvancedMsgListener(messageListener)
        V2TIMManager.getInstance().removeSimpleMsgListener(simpleMessageListener)
        V2TIMManager.getInstance().unInitSDK()
        initialized = false
        clearSession()
    }

    fun refreshConversations() {
        if (!isLoggedIn()) return
        val refreshGeneration = ++conversationRefreshGeneration
        V2TIMManager.getConversationManager().getConversationList(0, 100, object : V2TIMValueCallback<com.tencent.imsdk.v2.V2TIMConversationResult> {
            override fun onSuccess(result: com.tencent.imsdk.v2.V2TIMConversationResult?) {
                val sdkConversations = result?.conversationList.orEmpty()
                    .mapNotNull(::mapConversation)
                val merged = mergeBoundWatchConversation(sdkConversations)
                    .sortedWith(compareByDescending<WatchImConversation> { it.isPinned }.thenByDescending { it.timestamp })
                if (refreshGeneration != conversationRefreshGeneration) return
                _conversations.value = merged
                enrichGroupAvatars(merged, refreshGeneration)
            }

            override fun onError(code: Int, desc: String?) {
                WatchLogger.w("IMSDK conversation load failed, code=$code, message=${desc.orEmpty()}")
            }
        })
    }

    private fun enrichGroupAvatars(base: List<WatchImConversation>, refreshGeneration: Int) {
        val groups = base.filter { it.isGroup && !it.groupId.isNullOrBlank() }
        if (groups.isEmpty()) return

        val enriched = base.toMutableList()
        val remaining = AtomicInteger(groups.size)
        groups.forEach { group ->
            loadGroupMembers(ConversationMapper.toMessageConversation(group)) { result ->
                if (refreshGeneration != conversationRefreshGeneration) return@loadGroupMembers
                val avatars = result.getOrNull()
                    .orEmpty()
                    .map { it.avatarRes }
                    .take(4)
                synchronized(enriched) {
                    val index = enriched.indexOfFirst { it.conversationId == group.conversationId }
                    if (index >= 0 && avatars.isNotEmpty()) {
                        enriched[index] = enriched[index].copy(groupMemberAvatarRes = avatars)
                    }
                    if (remaining.decrementAndGet() == 0 && refreshGeneration == conversationRefreshGeneration) {
                        _conversations.value = enriched.toList()
                    }
                }
            }
        }
    }

    fun loadMessages(conversation: MessageConversation, callback: (Result<List<WatchImMessage>>) -> Unit) {
        if (!isLoggedIn()) {
            callback(Result.failure(IllegalStateException("IMSDK_NOT_LOGGED_IN")))
            return
        }
        if (!conversation.isGroup) logC2CReceiveOption(conversation.peerId)
        val callbackAdapter = object : V2TIMValueCallback<List<V2TIMMessage>> {
            override fun onSuccess(messages: List<V2TIMMessage>?) {
                callback(Result.success(messages.orEmpty().mapNotNull(::mapMessage).map {
                    it.copy(conversationId = conversation.conversationId)
                }.sortedBy { it.timestamp }))
            }

            override fun onError(code: Int, desc: String?) {
                if (conversation.isLocalBinding) {
                    callback(Result.success(emptyList()))
                } else {
                    callback(Result.failure(IllegalStateException("$code:${desc.orEmpty()}")))
                }
            }
        }
        if (conversation.isGroup) {
            V2TIMManager.getMessageManager().getGroupHistoryMessageList(conversation.groupId ?: conversation.peerId, 50, null, callbackAdapter)
        } else {
            V2TIMManager.getMessageManager().getC2CHistoryMessageList(conversation.peerId, 50, null, callbackAdapter)
        }
    }

    fun loadGroupCandidates(callback: (Result<List<WatchImGroupCandidate>>) -> Unit) {
        if (!isLoggedIn()) {
            callback(Result.failure(IllegalStateException("IMSDK_NOT_LOGGED_IN")))
            return
        }
        V2TIMManager.getFriendshipManager().getFriendList(object : V2TIMValueCallback<List<V2TIMFriendInfo>> {
            override fun onSuccess(friends: List<V2TIMFriendInfo>?) {
                val currentUser = WatchImGroupCandidate(
                    userId = currentUserId,
                    displayName = currentUserId,
                    avatarRes = WatchAvatarResolver.resourceFor(currentUserId),
                    isWatch = false,
                    isCurrentUser = true,
                )
                val contacts = friends.orEmpty().mapNotNull { friend ->
                    val userId = friend.userID.orEmpty()
                    if (userId.isBlank() || userId == currentUserId) return@mapNotNull null
                    WatchImGroupCandidate(
                        userId = userId,
                        displayName = friend.friendRemark.orEmpty().ifBlank {
                            friend.userProfile?.nickName.orEmpty().ifBlank { userId }
                        },
                        avatarRes = WatchAvatarResolver.resourceFor(userId),
                        isWatch = false,
                    )
                }
                callback(Result.success(mergeGroupCandidates(listOf(currentUser) + contacts)))
            }

            override fun onError(code: Int, desc: String?) {
                WatchLogger.w("IMSDK friend list load failed, code=$code, message=${desc.orEmpty()}")
                val currentUser = WatchImGroupCandidate(
                    userId = currentUserId,
                    displayName = currentUserId,
                    avatarRes = WatchAvatarResolver.resourceFor(currentUserId),
                    isWatch = false,
                    isCurrentUser = true,
                )
                callback(Result.success(mergeGroupCandidates(listOf(currentUser))))
            }
        })
    }

    fun loadGroupMembers(conversation: MessageConversation, callback: (Result<List<WatchImGroupMember>>) -> Unit) {
        val groupId = conversation.groupId
        if (!conversation.isGroup || groupId.isNullOrBlank() || !isLoggedIn()) {
            callback(Result.success(emptyList()))
            return
        }
        V2TIMManager.getGroupManager().getGroupMemberList(
            groupId,
            V2TIMGroupMemberFullInfo.V2TIM_GROUP_MEMBER_FILTER_ALL,
            0,
            object : V2TIMValueCallback<com.tencent.imsdk.v2.V2TIMGroupMemberInfoResult> {
                override fun onSuccess(result: com.tencent.imsdk.v2.V2TIMGroupMemberInfoResult?) {
                    callback(Result.success(result?.memberInfoList.orEmpty().mapNotNull(::mapGroupMember)))
                }

                override fun onError(code: Int, desc: String?) {
                    callback(Result.failure(IllegalStateException("$code:${desc.orEmpty()}")))
                }
            },
        )
    }

    fun createGroup(memberIds: List<String>, groupName: String, callback: (Result<MessageConversation>) -> Unit) {
        if (!isLoggedIn()) {
            callback(Result.failure(IllegalStateException("IMSDK_NOT_LOGGED_IN")))
            return
        }
        val members = (memberIds + currentUserId).filter { it.isNotBlank() }.distinct()
        if (members.size < 2) {
            callback(Result.failure(IllegalArgumentException("IMSDK_GROUP_MEMBER_REQUIRED")))
            return
        }
        val groupInfo = V2TIMGroupInfo().apply {
            groupType = V2TIMManager.GROUP_TYPE_WORK
            this.groupName = groupName.trim().ifBlank { appContext?.getString(R.string.watch_chat_default_group_title).orEmpty() }
        }
        val memberList = members.filterNot { it == currentUserId }.map { userId ->
            V2TIMCreateGroupMemberInfo().apply { setUserID(userId) }
        }
        V2TIMManager.getGroupManager().createGroup(
            groupInfo,
            memberList,
            object : V2TIMValueCallback<String> {
                override fun onSuccess(groupId: String?) {
                    val id = groupId.orEmpty()
                    if (id.isBlank()) {
                        callback(Result.failure(IllegalStateException("IMSDK_GROUP_ID_EMPTY")))
                        return
                    }
                    refreshConversations()
                    callback(Result.success(MessageConversation(
                        key = "group_$id",
                        titleRes = R.string.watch_chat_default_group_title,
                        avatarRes = R.drawable.watch_avatar_family_design,
                        isGroup = true,
                        conversationId = "group_$id",
                        peerId = id,
                        groupId = id,
                        displayName = groupInfo.groupName,
                    )))
                }

                override fun onError(code: Int, desc: String?) {
                    callback(Result.failure(IllegalStateException("$code:${desc.orEmpty()}")))
                }
            },
        )
    }

    fun inviteToGroup(conversation: MessageConversation, memberIds: List<String>, callback: (Result<Unit>) -> Unit) {
        val groupId = conversation.groupId
        if (!conversation.isGroup || groupId.isNullOrBlank() || !isLoggedIn()) {
            callback(Result.failure(IllegalStateException("IMSDK_GROUP_NOT_READY")))
            return
        }
        val ids = memberIds.filter { it.isNotBlank() && it != currentUserId }.distinct()
        if (ids.isEmpty()) {
            callback(Result.failure(IllegalArgumentException("IMSDK_GROUP_MEMBER_REQUIRED")))
            return
        }
        V2TIMManager.getGroupManager().inviteUserToGroup(
            groupId,
            ids,
            object : V2TIMValueCallback<List<com.tencent.imsdk.v2.V2TIMGroupMemberOperationResult>> {
                override fun onSuccess(result: List<com.tencent.imsdk.v2.V2TIMGroupMemberOperationResult>?) {
                    val failed = result.orEmpty().filter { it.result != 0 }
                    if (failed.isEmpty()) callback(Result.success(Unit))
                    else callback(Result.failure(IllegalStateException("IMSDK_GROUP_INVITE_PARTIAL_FAILURE")))
                }

                override fun onError(code: Int, desc: String?) {
                    callback(Result.failure(IllegalStateException("$code:${desc.orEmpty()}")))
                }
            },
        )
    }

    fun sendText(conversation: MessageConversation, text: String, callback: (Result<WatchImMessage>) -> Unit) {
        val content = text.trim()
        if (content.isBlank() || !isLoggedIn()) {
            callback(Result.failure(IllegalArgumentException("IMSDK_MESSAGE_EMPTY_OR_NOT_LOGGED_IN")))
            return
        }
        val message = V2TIMManager.getMessageManager().createTextMessage(content)
        V2TIMManager.getMessageManager().sendMessage(
            message,
            if (conversation.isGroup) "" else conversation.peerId,
            if (conversation.isGroup) conversation.groupId ?: conversation.peerId else "",
            V2TIMMessage.V2TIM_PRIORITY_DEFAULT,
            false,
            null,
            object : V2TIMSendCallback<V2TIMMessage> {
                override fun onProgress(progress: Int) = Unit

                override fun onSuccess(sentMessage: V2TIMMessage?) {
                    val mapped = sentMessage?.let(::mapMessage)?.copy(conversationId = conversation.conversationId)
                    if (mapped == null) callback(Result.failure(IllegalStateException("IMSDK_MESSAGE_EMPTY_RESPONSE")))
                    else callback(Result.success(mapped))
                    refreshConversations()
                }

                override fun onError(code: Int, desc: String?) {
                    callback(Result.failure(IllegalStateException("$code:${desc.orEmpty()}")))
                }
            },
        )
    }

    fun sendCallSignal(to: String, signal: CallSignal, callback: (Result<Unit>) -> Unit) {
        if (to.isBlank() || !isLoggedIn()) {
            callback(Result.failure(IllegalStateException("IMSDK_NOT_READY")))
            return
        }
        val message = try {
            V2TIMManager.getMessageManager().createTextMessage(CallSignalCodec.encode(signal))
        } catch (error: Exception) {
            callback(Result.failure(error))
            return
        }
        V2TIMManager.getMessageManager().sendMessage(
            message,
            to,
            "",
            V2TIMMessage.V2TIM_PRIORITY_HIGH,
            true,
            null,
            object : V2TIMSendCallback<V2TIMMessage> {
                override fun onProgress(progress: Int) = Unit
                override fun onSuccess(sentMessage: V2TIMMessage?) { callback(Result.success(Unit)) }
                override fun onError(code: Int, desc: String?) {
                    callback(Result.failure(IllegalStateException("$code:${desc.orEmpty()}")))
                }
            },
        )
    }

    fun markAsRead(conversation: MessageConversation) {
        if (!isLoggedIn()) return
        val conversationManager = V2TIMManager.getConversationManager()
        conversationManager.cleanConversationUnreadMessageCount(
            conversation.conversationId,
            0,
            0,
            object : V2TIMCallback {
                override fun onSuccess() {
                    WatchLogger.i("IMSDK mark conversation read: clean unread success, id=${conversation.conversationId}")
                }

                override fun onError(code: Int, desc: String?) {
                    WatchLogger.w(
                        "IMSDK mark conversation read: clean unread failed, " +
                            "id=${conversation.conversationId}, code=$code, message=${desc.orEmpty()}",
                    )
                }
            },
        )
    }

    fun setPinned(conversation: MessageConversation, pinned: Boolean, callback: (Result<Unit>) -> Unit) {
        V2TIMManager.getConversationManager().pinConversation(conversation.conversationId, pinned, callbackAdapter(callback))
    }

    fun setMuted(conversation: MessageConversation, muted: Boolean, callback: (Result<Unit>) -> Unit) {
        val receiveOpt = if (muted) V2TIMMessage.V2TIM_NOT_RECEIVE_MESSAGE else V2TIMMessage.V2TIM_RECEIVE_MESSAGE
        val manager = V2TIMManager.getMessageManager()
        val sdkCallback = callbackAdapter(callback)
        if (conversation.isGroup) {
            manager.setGroupReceiveMessageOpt(conversation.groupId ?: conversation.peerId, receiveOpt, sdkCallback)
        } else {
            manager.setC2CReceiveMessageOpt(listOf(conversation.peerId), receiveOpt, sdkCallback)
        }
    }

    fun enableC2CReceiveMessage(peerId: String) {
        if (!isLoggedIn() || peerId.isBlank()) {
            WatchLogger.w("IMSDK C2C receive enable skipped: loggedIn=${isLoggedIn()}, peer=$peerId")
            return
        }
        V2TIMManager.getMessageManager().setC2CReceiveMessageOpt(
            listOf(peerId),
            V2TIMMessage.V2TIM_RECEIVE_MESSAGE,
            object : V2TIMCallback {
                override fun onSuccess() {
                    WatchLogger.i("IMSDK C2C receive enabled: peer=$peerId")
                    logC2CReceiveOption(peerId)
                }

                override fun onError(code: Int, desc: String?) {
                    WatchLogger.e(
                        "IMSDK C2C receive enable failed: peer=$peerId, code=$code, message=${desc.orEmpty()}",
                    )
                }
            },
        )
    }

    fun clearHistory(conversation: MessageConversation, callback: (Result<Unit>) -> Unit) {
        val manager = V2TIMManager.getMessageManager()
        val sdkCallback = callbackAdapter(callback)
        if (conversation.isGroup) {
            manager.clearGroupHistoryMessage(conversation.groupId ?: conversation.peerId, sdkCallback)
        } else {
            manager.clearC2CHistoryMessage(conversation.peerId, sdkCallback)
        }
    }

    fun setDraft(conversation: MessageConversation, draft: String) {
        if (isLoggedIn()) {
            V2TIMManager.getConversationManager().setConversationDraft(conversation.conversationId, draft, emptyCallback())
        }
    }

    fun logC2CReceiveOption(peerId: String) {
        if (!isLoggedIn() || peerId.isBlank()) return
        V2TIMManager.getMessageManager().getC2CReceiveMessageOpt(
            listOf(peerId),
            object : V2TIMValueCallback<List<V2TIMReceiveMessageOptInfo>> {
                override fun onSuccess(result: List<V2TIMReceiveMessageOptInfo>?) {
                    val item = result.orEmpty().firstOrNull { it.userID == peerId }
                    WatchLogger.i(
                        "IMSDK C2C receive option: peer=$peerId, " +
                            "opt=${item?.c2CReceiveMessageOpt}, " +
                            "receive=${V2TIMMessage.V2TIM_RECEIVE_MESSAGE}, " +
                            "notReceive=${V2TIMMessage.V2TIM_NOT_RECEIVE_MESSAGE}",
                    )
                }

                override fun onError(code: Int, desc: String?) {
                    WatchLogger.w("IMSDK C2C receive option failed: peer=$peerId, code=$code, message=${desc.orEmpty()}")
                }
            },
        )
    }

    private fun isLoggedIn(): Boolean = _loginState.value is ImLoginState.LoggedIn

    private fun clearSession() {
        currentUserId = ""
        _loginState.value = ImLoginState.LoggedOut
        _conversations.value = emptyList()
    }

    private fun emptyCallback() = object : V2TIMCallback {
        override fun onSuccess() = Unit
        override fun onError(code: Int, desc: String?) {
            WatchLogger.w("IMSDK operation failed, code=$code, message=${desc.orEmpty()}")
        }
    }

    private fun callbackAdapter(callback: (Result<Unit>) -> Unit) = object : V2TIMCallback {
        override fun onSuccess() = callback(Result.success(Unit))
        override fun onError(code: Int, desc: String?) = callback(Result.failure(IllegalStateException("$code:${desc.orEmpty()}")))
    }

    private fun handleIncomingText(
        messageId: String,
        senderId: String,
        senderName: String,
        groupId: String,
        isSelf: Boolean,
        text: String,
        timestamp: Long,
        status: Int,
        source: String,
        refresh: Boolean = true,
    ) {
        if (senderId.isBlank() && groupId.isBlank()) {
            WatchLogger.w("IMSDK $source recv message ignored: missing sender and group ID")
            return
        }
        if (!isSelf && messageId.isNotBlank() && !handledIncomingMessageIds.add(messageId)) {
            WatchLogger.i("IMSDK $source recv message ignored: duplicate msgId=$messageId")
            return
        }
        if (!isSelf && groupId.isBlank()) {
            val signal = CallSignalCodec.decode(text)
            if (signal != null) {
                val emitted = _callSignalEvents.tryEmit(IncomingCallSignal(senderId, signal))
                WatchLogger.i(
                    "IMSDK recv call signal: type=${signal.type.wireValue}, sid=${signal.sessionId}, " +
                        "from=$senderId, source=$source, emitted=$emitted",
                )
                return
            }
        }
        val conversationId = if (groupId.isNotBlank()) "group_$groupId" else "c2c_$senderId"
        val mapped = WatchImMessage(
            messageId = messageId.ifBlank { "${timestamp}-${senderId.hashCode()}" },
            conversationId = conversationId,
            senderId = senderId,
            senderName = senderName,
            isSelf = isSelf,
            text = text,
            timestamp = timestamp,
            status = status,
        )
        val emitted = _messageEvents.tryEmit(mapped)
        WatchLogger.i(
            "IMSDK recv message mapped: conversation=${mapped.conversationId}, " +
                "sender=${mapped.senderId}, isSelf=${mapped.isSelf}, source=$source, " +
                "subscribers=${_messageEvents.subscriptionCount.value}, emitted=$emitted",
        )
        if (refresh) refreshConversations()
    }

    private fun logConversationChanges(source: String, conversations: List<V2TIMConversation>?) {
        conversations.orEmpty().forEach { conversation ->
            val lastMessage = conversation.lastMessage ?: return@forEach
            WatchLogger.i(
                "IMSDK conversation $source: id=${conversation.conversationID.orEmpty()}, " +
                    "peer=${conversation.userID.orEmpty()}, group=${conversation.groupID.orEmpty()}, " +
                    "lastMsgId=${lastMessage.msgID.orEmpty()}, isSelf=${lastMessage.isSelf}, " +
                    "elemType=${lastMessage.elemType}, text=${lastMessage.textElem?.text.orEmpty().replace(Regex("\\s+"), " ").take(120)}",
            )
            if (!lastMessage.isSelf && lastMessage.groupID.isNullOrBlank() &&
                lastMessage.elemType == V2TIMMessage.V2TIM_ELEM_TYPE_TEXT
            ) {
                handleIncomingText(
                    messageId = lastMessage.msgID.orEmpty(),
                    senderId = lastMessage.sender.orEmpty(),
                    senderName = lastMessage.nickName.orEmpty().ifBlank { lastMessage.sender.orEmpty() },
                    groupId = "",
                    isSelf = false,
                    text = lastMessage.textElem?.text.orEmpty(),
                    timestamp = lastMessage.timestamp,
                    status = lastMessage.status,
                    source = "conversation",
                    refresh = false,
                )
            }
        }
    }

    private fun mapConversation(conversation: V2TIMConversation): WatchImConversation? {
        val isGroup = conversation.type == V2TIMConversation.V2TIM_GROUP
        val peerId = if (isGroup) conversation.groupID.orEmpty() else conversation.userID.orEmpty()
        if (peerId.isBlank()) return null
        val lastMessage = conversation.lastMessage
        val preview = if (lastMessage?.elemType == V2TIMMessage.V2TIM_ELEM_TYPE_TEXT) {
            lastMessage.textElem?.text.orEmpty()
        } else {
            ""
        }
        val conversationId = conversation.conversationID.orEmpty()
        val boundDeviceNames = appContext
            ?.let { context -> WatchBindingStore.all(context, currentUserId).map { it.deviceName }.toSet() }
            .orEmpty()
        val title = if (!isGroup && peerId in boundDeviceNames) {
            peerId
        } else {
            conversation.showName?.takeIf { it.isNotBlank() } ?: peerId
        }
        return WatchImConversation(
            conversationId = conversationId,
            peerId = peerId,
            groupId = if (isGroup) peerId else null,
            isGroup = isGroup,
            title = title,
            avatarRes = if (isGroup) R.drawable.watch_avatar_family_design else WatchAvatarResolver.resourceFor(peerId),
            preview = preview,
            timestamp = lastMessage?.timestamp ?: conversation.orderKey,
            unreadCount = conversation.unreadCount,
            isPinned = conversation.isPinned,
            isMuted = conversation.recvOpt != V2TIMMessage.V2TIM_RECEIVE_MESSAGE,
            isLocalBinding = !isGroup && peerId in boundDeviceNames,
        )
    }

    private fun mergeGroupCandidates(contacts: List<WatchImGroupCandidate>): List<WatchImGroupCandidate> {
        val currentUser = WatchImGroupCandidate(
            userId = currentUserId,
            displayName = currentUserId,
            avatarRes = WatchAvatarResolver.resourceFor(currentUserId),
            isWatch = false,
            isCurrentUser = true,
        )
        val watches = appContext?.let { context ->
            WatchBindingStore.all(context, currentUserId).map { binding ->
                WatchImGroupCandidate(
                    userId = binding.deviceName,
                    displayName = binding.deviceName,
                    avatarRes = WatchAvatarResolver.resourceFor(binding.deviceName),
                    isWatch = true,
                )
            }
        }.orEmpty()
        return (listOf(currentUser) + contacts + watches)
            .filter { it.userId.isNotBlank() }
            .distinctBy { it.userId }
            .sortedWith(
                compareBy<WatchImGroupCandidate> { !it.isCurrentUser }
                    .thenBy { !it.isWatch }
                    .thenBy { it.displayName },
            )
    }

    private fun mapGroupMember(member: V2TIMGroupMemberFullInfo): WatchImGroupMember? {
        val userId = member.userID.orEmpty()
        if (userId.isBlank()) return null
        return WatchImGroupMember(
            userId = userId,
            displayName = member.nameCard.orEmpty().ifBlank {
                member.nickName.orEmpty().ifBlank { userId }
            },
            avatarRes = WatchAvatarResolver.resourceFor(userId),
        )
    }

    private fun mergeBoundWatchConversation(conversations: List<WatchImConversation>): List<WatchImConversation> {
        val bindings = appContext?.let { context -> WatchBindingStore.all(context, currentUserId) }.orEmpty()
        if (bindings.isEmpty()) return conversations
        val existing = conversations.asSequence().filterNot { it.isGroup }.map { it.peerId }.toSet()
        return conversations + bindings.filterNot { it.deviceName in existing }.map { binding ->
            WatchImConversation(
                conversationId = "c2c_${binding.deviceName}",
                peerId = binding.deviceName,
                groupId = null,
                isGroup = false,
                title = binding.deviceName,
                avatarRes = WatchAvatarResolver.resourceFor(binding.deviceName),
                preview = "",
                timestamp = 0L,
                unreadCount = 0,
                isPinned = false,
                isMuted = false,
                isLocalBinding = true,
            )
        }
    }

    private fun mapMessage(message: V2TIMMessage): WatchImMessage? {
        if (message.elemType != V2TIMMessage.V2TIM_ELEM_TYPE_TEXT) return null
        val groupId = message.groupID.orEmpty()
        val peerId = if (groupId.isNotBlank()) groupId else message.userID.orEmpty().ifBlank { message.sender.orEmpty() }
        if (peerId.isBlank()) return null
        return WatchImMessage(
            messageId = message.msgID.orEmpty().ifBlank { "${message.timestamp}-${message.sender}" },
            conversationId = if (groupId.isNotBlank()) "group_$groupId" else "c2c_$peerId",
            senderId = message.sender.orEmpty(),
            senderName = message.nickName.orEmpty().ifBlank { message.sender.orEmpty() },
            isSelf = message.isSelf,
            text = message.textElem?.text.orEmpty(),
            timestamp = message.timestamp,
            status = message.status,
        )
    }
}
