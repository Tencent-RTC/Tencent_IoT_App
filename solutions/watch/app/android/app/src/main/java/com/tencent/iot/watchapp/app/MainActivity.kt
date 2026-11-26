package com.tencent.iot.watchapp.app
import com.tencent.iot.watchapp.R
import com.tencent.iot.watchapp.call.*
import com.tencent.iot.watchapp.config.*
import com.tencent.iot.watchapp.im.*
import com.tencent.iot.watchapp.ui.*
import com.tencent.iot.watchapp.watch.*

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.Toast
import androidx.activity.viewModels
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.WindowCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

class MainActivity : AppCompatActivity() {
    private val sessionViewModel: AppSessionViewModel by viewModels()
    internal lateinit var callCoordinator: CallCoordinator
    private lateinit var pageContainer: FrameLayout
    private lateinit var loginView: LoginView
    private lateinit var mainTabView: MainTabView
    private var pendingCall: PendingCallRequest? = null
    private val messageDrafts = mutableMapOf<String, String>()
    private var iotReady = false
    private var imReady = false
    private var messageListJob: Job? = null
    private var chatMessageJob: Job? = null
    private var chatHistorySyncJob: Job? = null
    private var activeChatView: ChatView? = null
    private var qrScannerView: WatchQrScannerView? = null
    private var groupMemberPicker: GroupMemberPickerView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, true)
        window.statusBarColor = getColor(R.color.watch_background)
        window.navigationBarColor = getColor(R.color.watch_surface)
        window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
        setContentView(R.layout.watch_activity_main)
        callCoordinator = CallCoordinator(this, this, ImCallSignalTransport())
        IoTSignatureProviders.install(TrtcSignatureProvider)

        pageContainer = findViewById(R.id.watch_page_container)
        loginView = findViewById(R.id.watch_login_view)
        mainTabView = findViewById(R.id.watch_main_tab_view)
        ImService.initialize(this)

        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                launch { sessionViewModel.screen.collect(::render) }
                launch {
                    callCoordinator.loginState.collect { state ->
                        loginView.renderLoginState(state)
                        iotReady = state is IoTLoginState.LoggedIn || (state is IoTLoginState.Failed && state.code == "SDK_UNAVAILABLE")
                        tryEnterMain()
                    }
                }
                launch {
                    ImService.loginState.collect { state ->
                        when (state) {
                            ImLoginState.LoggedOut -> imReady = false
                            ImLoginState.LoggingIn -> {
                                imReady = false
                                loginView.renderLoginState(IoTLoginState.LoggingIn)
                            }
                            is ImLoginState.LoggedIn -> {
                                imReady = true
                                tryEnterMain()
                            }
                            is ImLoginState.Failed -> {
                                imReady = false
                                loginView.renderLoginState(IoTLoginState.Failed("IMSDK_${state.code}", state.message))
                            }
                        }
                    }
                }
                launch { callCoordinator.callState.collect(::renderCallState) }
            }
        }
    }

    fun onLoginSubmitted(channel: String, appId: String, appSecret: String) {
        WatchLogger.i("Login submitted, channel=$channel, appId=$appId, secretPresent=${appSecret.isNotBlank()}")
        iotReady = false
        imReady = false
        ImService.login(this, channel)
        callCoordinator.login(channel, appId, appSecret)
    }

    fun onLogoutRequested() {
        imReady = false
        iotReady = false
        ImService.logout()
        callCoordinator.logout()
        sessionViewModel.onLogout()
    }

    fun onTabSelected(screen: AppScreen) {
        sessionViewModel.select(screen)
    }

    fun showChat(conversation: MessageConversation, draft: String = messageDrafts[conversation.key].orEmpty()) {
        chatMessageJob?.cancel()
        chatHistorySyncJob?.cancel()
        messageDrafts[conversation.key] = draft
        mainTabView.visibility = View.GONE
        val chat = ChatView(this)
        activeChatView = chat
        chat.configure(conversation, draft)
        chatMessageJob = lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                ImService.messageEvents.collect { message ->
                    val matched = message.conversationId == conversation.conversationId
                    WatchLogger.i(
                        "Chat message event: actual=${message.conversationId}, " +
                            "expected=${conversation.conversationId}, matched=$matched, " +
                            "sender=${message.senderId}, isSelf=${message.isSelf}, " +
                            "text=${message.text.replace(Regex("\\s+"), " ").take(120)}",
                    )
                    if (matched) chat.appendMessage(message)
                }
            }
        }
        ImService.loadMessages(conversation) { result ->
            runOnUiThread {
                result.onSuccess(chat::renderMessages).onFailure {
                    Toast.makeText(this, R.string.watch_chat_load_failed, Toast.LENGTH_SHORT).show()
                    chat.renderMessages(emptyList())
                }
            }
        }
        chatHistorySyncJob = lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                while (isActive) {
                    delay(1500)
                    ImService.loadMessages(conversation) { result ->
                        result.onSuccess { messages ->
                            val before = messages.size
                            runOnUiThread {
                                chat.mergeMessages(messages)
                                val after = chat.messageCount()
                                if (after > before) {
                                    WatchLogger.i(
                                        "Chat history sync: conversation=${conversation.conversationId}, " +
                                            "historyCount=$before, mergedCount=$after",
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        ImService.markAsRead(conversation)
        chat.findViewById<ImageButton>(R.id.watch_chat_back).setOnClickListener {
            val updatedDraft = chat.currentDraft()
            messageDrafts[conversation.key] = updatedDraft
            ImService.setDraft(conversation, updatedDraft)
            chatMessageJob?.cancel()
            chatHistorySyncJob?.cancel()
            activeChatView = null
            showMessages()
        }
        chat.findViewById<ImageButton>(R.id.watch_chat_info).setOnClickListener {
            val selectedConversation = chat.currentConversation() ?: return@setOnClickListener
            val updatedDraft = chat.currentDraft()
            messageDrafts[selectedConversation.key] = updatedDraft
            ImService.setDraft(selectedConversation, updatedDraft)
            chatMessageJob?.cancel()
            chatHistorySyncJob?.cancel()
            activeChatView = null
            showChatInfo(selectedConversation, updatedDraft)
        }
        pageContainer.removeAllViews()
        pageContainer.addView(chat)
    }

    fun showAddContact() {
        restoreNormalSystemBars()
        mainTabView.visibility = View.GONE
        val addContact = AddContactView(this)
        addContact.setOnBack { showMessages() }
        addContact.setOnAddWatch { showBindWatchPage() }
        addContact.setOnCreateGroup { showGroupMemberPicker() }
        pageContainer.removeAllViews()
        pageContainer.addView(addContact)
    }

    fun showBindWatchPage(returnToDevices: Boolean = false) {
        restoreNormalSystemBars()
        mainTabView.visibility = View.GONE
        val bindWatch = BindWatchPage(this)
        bindWatch.setOnBack { if (returnToDevices) onTabSelected(AppScreen.DEVICES) else showAddContact() }
        bindWatch.setOnBind { deviceName ->
            val bound = WatchBindingStore.bind(this, ImService.loggedInUserId, deviceName)
            if (bound == null) {
                bindWatch.showError(getString(R.string.watch_bind_watch_device_required))
                return@setOnBind
            }
            ImService.enableC2CReceiveMessage(bound.deviceName)
            ImService.refreshConversations()
            showChat(bound.toMessageConversation())
        }
        pageContainer.removeAllViews()
        pageContainer.addView(bindWatch)
    }

    fun showWatchScanner(returnToDevices: Boolean = false) {
        mainTabView.visibility = View.GONE
        window.statusBarColor = getColor(android.R.color.black)
        window.navigationBarColor = getColor(R.color.watch_surface)
        window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
        val scanner = WatchQrScannerView(this)
        qrScannerView = scanner
        scanner.findViewById<ImageButton>(R.id.watch_scan_back).setOnClickListener {
            scanner.stop()
            qrScannerView = null
            if (returnToDevices) render(AppScreen.DEVICES) else showAddContact()
        }
        scanner.setOnResult { value ->
            scanner.stop()
            qrScannerView = null
            if (returnToDevices) render(AppScreen.DEVICES) else showAddContact()
            Toast.makeText(this, getString(R.string.watch_scan_found, value), Toast.LENGTH_LONG).show()
        }
        pageContainer.removeAllViews()
        pageContainer.addView(scanner)
        if (checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            scanner.start(this)
        } else {
            requestPermissions(arrayOf(Manifest.permission.CAMERA), CAMERA_PERMISSION_REQUEST)
        }
    }

    private fun restoreNormalSystemBars() {
        window.statusBarColor = getColor(R.color.watch_background)
        window.navigationBarColor = getColor(R.color.watch_surface)
        window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
    }

    private fun showChatInfo(conversation: MessageConversation, draft: String) {
        mainTabView.visibility = View.GONE
        val info = ChatInfoView(this)
        info.configure(conversation)
        info.setInviteAction { showGroupMemberPicker(it) }
        info.findViewById<ImageButton>(R.id.watch_chat_info_back).setOnClickListener { showChat(conversation, draft) }
        pageContainer.removeAllViews()
        pageContainer.addView(info)
    }

    private fun showGroupMemberPicker(conversation: MessageConversation? = null) {
        val picker = GroupMemberPickerView(this)
        groupMemberPicker = picker
        if (conversation == null || !conversation.isGroup) {
            picker.setDefaultSelectedUserIds(
                buildSet {
                    add(ImService.loggedInUserId)
                    conversation?.peerId?.takeIf { it.isNotBlank() }?.let(::add)
                },
            )
        }
        picker.setCallbacks(
            onBack = {
                groupMemberPicker = null
                if (conversation == null) {
                    showAddContact()
                } else {
                    showChatInfo(conversation, messageDrafts[conversation.key].orEmpty())
                }
            },
            onDone = { selected ->
                picker.isEnabled = false
                val selectedIds = selected.map { it.userId }
                if (conversation?.isGroup == true) {
                    ImService.inviteToGroup(conversation, selectedIds) { result ->
                        runOnUiThread {
                            groupMemberPicker = null
                            if (result.isSuccess) {
                                Toast.makeText(this, R.string.watch_group_invite_done, Toast.LENGTH_SHORT).show()
                                showChatInfo(conversation, messageDrafts[conversation.key].orEmpty())
                            } else {
                                picker.isEnabled = true
                                Toast.makeText(this, getString(R.string.watch_group_invite_failed, result.exceptionOrNull()?.message.orEmpty()), Toast.LENGTH_LONG).show()
                            }
                        }
                    }
                } else {
                    val memberIds = listOfNotNull(conversation?.peerId) + selectedIds
                    val groupName = (listOfNotNull(conversation?.displayName) + selected.filterNot { it.isCurrentUser }.map { it.displayName })
                        .distinct()
                        .take(3)
                        .joinToString(getString(R.string.watch_group_name_separator))
                        .plus(getString(R.string.watch_chat_default_group_title))
                    ImService.createGroup(memberIds, groupName) { result ->
                        runOnUiThread {
                            groupMemberPicker = null
                            result.onSuccess { created -> showChat(created) }.onFailure { error ->
                                picker.isEnabled = true
                                Toast.makeText(this, getString(R.string.watch_group_create_failed, error.message.orEmpty()), Toast.LENGTH_LONG).show()
                            }
                        }
                    }
                }
            },
        )
        picker.showLoading()
        pageContainer.removeAllViews()
        pageContainer.addView(picker)
        ImService.loadGroupCandidates { result ->
            runOnUiThread { result.onSuccess(picker::render).onFailure { picker.render(emptyList()) } }
        }
    }

    fun onChatSendRequested(conversation: MessageConversation?, text: String) {
        val activeChat = activeChatView ?: return
        val selectedConversation = conversation ?: return
        activeChat.setSending(true)
        ImService.sendText(selectedConversation, text) { result ->
            runOnUiThread {
                activeChat.setSending(false)
                result.onSuccess {
                    activeChat.renderMessagesWithDraftCleared(it)
                    messageDrafts[selectedConversation.key] = ""
                }.onFailure {
                    activeChat.showSendFailed()
                }
            }
        }
    }

    fun onChatMuteChanged(conversation: MessageConversation, muted: Boolean) {
        ImService.setMuted(conversation, muted) { result ->
            if (result.isFailure) runOnUiThread { Toast.makeText(this, result.exceptionOrNull()?.message.orEmpty(), Toast.LENGTH_SHORT).show() }
        }
    }

    fun onChatPinChanged(conversation: MessageConversation, pinned: Boolean) {
        ImService.setPinned(conversation, pinned) { result ->
            if (result.isFailure) runOnUiThread { Toast.makeText(this, result.exceptionOrNull()?.message.orEmpty(), Toast.LENGTH_SHORT).show() }
        }
    }

    fun onChatClearRequested(conversation: MessageConversation) {
        AlertDialog.Builder(this)
            .setMessage(R.string.watch_chat_clear_confirm)
            .setNegativeButton(android.R.string.cancel, null)
            .setPositiveButton(android.R.string.ok) { _, _ ->
                ImService.clearHistory(conversation) { result ->
                    runOnUiThread {
                        if (result.isSuccess) Toast.makeText(this, R.string.watch_chat_clear_done, Toast.LENGTH_SHORT).show()
                        else Toast.makeText(this, result.exceptionOrNull()?.message.orEmpty(), Toast.LENGTH_SHORT).show()
                    }
                }
            }
            .show()
    }

    private fun showMessages() {
        restoreNormalSystemBars()
        mainTabView.visibility = View.VISIBLE
        render(AppScreen.MESSAGES)
    }

    fun showCallTargetPicker() {
        if (findViewById<CallTargetPickerView>(R.id.watch_call_picker_root) != null) return
        val picker = CallTargetPickerView(this)
        findViewById<FrameLayout>(android.R.id.content).addView(
            picker,
            FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT),
        )
    }

    fun showOutgoingCall(voiceMode: Boolean, targetName: String, avatarId: String) {
        val content = findViewById<FrameLayout>(android.R.id.content)
        findViewById<CallTargetPickerView>(R.id.watch_call_picker_root)?.let(content::removeView)
        if (findViewById<OutgoingCallView>(R.id.watch_outgoing_call_root) != null) return
        window.statusBarColor = getColor(R.color.watch_call_dark)
        window.navigationBarColor = getColor(R.color.watch_surface)
        window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
        val call = OutgoingCallView(this)
        call.configure(voiceMode, targetName, WatchAvatarResolver.resourceFor(avatarId))
        content.addView(call, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        if (!voiceMode) call.startLocalPreview(callCoordinator)
    }

    fun startCall(target: CallTarget, voiceMode: Boolean, targetName: String, avatarId: String) {
        val permissions = if (voiceMode) arrayOf(Manifest.permission.RECORD_AUDIO) else arrayOf(Manifest.permission.RECORD_AUDIO, Manifest.permission.CAMERA)
        if (permissions.any { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }) {
            pendingCall = PendingCallRequest(target, voiceMode, targetName, avatarId)
            requestPermissions(permissions, CALL_PERMISSION_REQUEST)
            return
        }
        startCallAfterPermission(target, voiceMode, targetName, avatarId)
    }

    private fun startCallAfterPermission(target: CallTarget, voiceMode: Boolean, targetName: String, avatarId: String) {
        if (callCoordinator.startCall(target, targetName, avatarId, if (voiceMode) CallMediaType.AUDIO else CallMediaType.VIDEO)) {
            showOutgoingCall(voiceMode, targetName, avatarId)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CAMERA_PERMISSION_REQUEST) {
            val scanner = qrScannerView ?: return
            if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) scanner.start(this) else scanner.showPermissionDenied()
            return
        }
        if (requestCode != CALL_PERMISSION_REQUEST) return
        val request = pendingCall ?: return
        pendingCall = null
        if (grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }) {
            startCallAfterPermission(request.target, request.voiceMode, request.targetName, request.avatarId)
        }
    }

    fun dismissOutgoingCall() {
        callCoordinator.hangup()
        findViewById<OutgoingCallView>(R.id.watch_outgoing_call_root)?.let { view -> (view.parent as? FrameLayout)?.removeView(view) }
        window.statusBarColor = getColor(R.color.watch_background)
        window.navigationBarColor = getColor(R.color.watch_surface)
        window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
    }

    private fun renderCallState(state: CallUiState) {
        when (state.phase) {
            CallPhase.INCOMING -> showIncomingCall(state)
            CallPhase.ACTIVE -> {
                removeIncomingCall()
                findViewById<OutgoingCallView>(R.id.watch_outgoing_call_root)?.setActive(
                    callCoordinator,
                    callCoordinator.callState.value.mediaType == CallMediaType.VIDEO,
                )
            }
            CallPhase.IDLE -> removeIncomingCall()
            CallPhase.OUTGOING -> Unit
        }
    }

    private fun showIncomingCall(state: CallUiState) {
        if (findViewById<IncomingCallView>(R.id.watch_incoming_call_root) != null) return
        val incoming = IncomingCallView(this)
        incoming.configure(state.targetName, WatchAvatarResolver.resourceFor(state.avatarId), state.mediaType == CallMediaType.AUDIO)
        findViewById<FrameLayout>(android.R.id.content).addView(incoming, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
    }

    private fun removeIncomingCall() {
        findViewById<IncomingCallView>(R.id.watch_incoming_call_root)?.let { view -> (view.parent as? FrameLayout)?.removeView(view) }
    }

    fun acceptIncomingCall() {
        val incoming = callCoordinator.callState.value
        if (!callCoordinator.acceptIncoming()) return
        removeIncomingCall()
        showOutgoingCall(
            voiceMode = incoming.mediaType == CallMediaType.AUDIO,
            targetName = incoming.targetName,
            avatarId = incoming.avatarId,
        )
        renderCallState(callCoordinator.callState.value)
    }

    fun rejectIncomingCall() {
        callCoordinator.rejectIncoming()
        removeIncomingCall()
    }

    override fun onDestroy() {
        messageListJob?.cancel()
        chatMessageJob?.cancel()
        chatHistorySyncJob?.cancel()
        ImService.release()
        callCoordinator.release()
        super.onDestroy()
    }

    private fun render(screen: AppScreen) {
        messageListJob?.cancel()
        if (screen == AppScreen.LOGIN) {
            loginView.visibility = View.VISIBLE
            mainTabView.visibility = View.GONE
            return
        }

        loginView.visibility = View.GONE
        mainTabView.visibility = View.VISIBLE
        mainTabView.select(screen)
        val page = when (screen) {
            AppScreen.MESSAGES -> MessagesView(this).also { messagesView ->
                messagesView.renderConversations(ImService.conversations.value)
                messageListJob = lifecycleScope.launch {
                    repeatOnLifecycle(Lifecycle.State.STARTED) {
                        ImService.conversations.collect(messagesView::renderConversations)
                    }
                }
                ImService.refreshConversations()
            }
            AppScreen.LOCATION -> LocationView(this)
            AppScreen.DEVICES -> DevicesView(this)
            AppScreen.PROFILE -> ProfileView(this)
            AppScreen.LOGIN -> return
        }
        pageContainer.removeAllViews()
        page.alpha = 0f
        pageContainer.addView(page)
        page.animate().alpha(1f).setDuration(180L).start()
    }

    private fun tryEnterMain() {
        if (imReady && iotReady) sessionViewModel.onLoginSucceeded()
    }

    private data class PendingCallRequest(
        val target: CallTarget,
        val voiceMode: Boolean,
        val targetName: String,
        val avatarId: String,
    )

    private companion object {
        const val CALL_PERMISSION_REQUEST = 2301
        const val CAMERA_PERMISSION_REQUEST = 4101
    }
}
