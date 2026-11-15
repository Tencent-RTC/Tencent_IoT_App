import Foundation

#if canImport(ImSDK_Plus)
import ImSDK_Plus
#endif

struct WatchImMessage {
    let id: String
    let text: String
    let senderID: String
    let isOutgoing: Bool
    let timestamp: Date
}

struct WatchImGroupCandidate {
    let userID: String
    let displayName: String
    let avatarKey: String
    let isWatch: Bool
    let isCurrentUser: Bool

    init(userID: String, displayName: String, avatarKey: String, isWatch: Bool, isCurrentUser: Bool = false) {
        self.userID = userID
        self.displayName = displayName
        self.avatarKey = avatarKey
        self.isWatch = isWatch
        self.isCurrentUser = isCurrentUser
    }
}

struct WatchImGroupMember {
    let userID: String
    let displayName: String
    let avatarKey: String
}

enum WatchImLoginState: Equatable {
    case loggedOut
    case loggingIn
    case loggedIn(userID: String)
    case failed(code: Int, message: String)
}

/// iOS 端 IMSDK 的最小消息能力层。页面只依赖本文件的模型和操作，不直接调用 V2TIM API。
@MainActor
final class ImService {
    private(set) var loginState: WatchImLoginState = .loggedOut {
        didSet { onLoginStateChange?(loginState) }
    }
    private(set) var conversations: [MessageConversation] = [] {
        didSet { onConversationsChange?(conversations) }
    }

    var onLoginStateChange: ((WatchImLoginState) -> Void)?
    var onConversationsChange: (([MessageConversation]) -> Void)?
    var onMessagesChange: (([WatchImMessage]) -> Void)?
    var onMessageReceived: ((MessageConversation, WatchImMessage) -> Void)?
    var onCallSignalReceived: ((IncomingCallSignal) -> Void)?

    var loggedInUserID: String? {
        if case .loggedIn(let userID) = loginState { return userID }
        return nil
    }

    func directConversation(peerID: String, displayName: String? = nil) -> MessageConversation {
        ConversationMapper.direct(
            peerID: peerID,
            displayName: displayName,
            isLocalBinding: WatchBindingStore.all(userID: loggedInUserID).contains { $0.deviceName == peerID }
        )
    }

    private var activeChannel = ""
    private var activeConversation: MessageConversation?
    private var conversationRefreshGeneration = 0
    private var sdkInitialized = false
    private var isLoggingOut = false
    private var logoutCompletion: (() -> Void)?

#if canImport(ImSDK_Plus)
    private let manager = V2TIMManager.sharedInstance()!
    private lazy var listener: Listener = {
        let listener = Listener()
        listener.onConversationChange = { [weak self] in
            Task { @MainActor in self?.refreshConversations() }
        }
        listener.onMessage = { [weak self] message in
            Task { @MainActor in self?.handleIncoming(message) }
        }
        return listener
    }()
#endif

    func login(channel: String) {
        activeChannel = channel
        loginState = .loggingIn

#if canImport(ImSDK_Plus) && !targetEnvironment(simulator)
        do {
            let credentials = try ImSdkAuth.forChannel(channel)
            let config = V2TIMSDKConfig()
            guard manager.initSDK(Int32(credentials.sdkAppID), config: config) else {
                loginState = .failed(code: -1, message: "IMSDK_INIT_FAILED")
                return
            }
            sdkInitialized = true
            manager.addConversationListener(listener: listener)
            manager.addAdvancedMsgListener(listener: listener)
            manager.login(credentials.userID, userSig: credentials.userSig, succ: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.loginState = .loggedIn(userID: credentials.userID)
                    WatchBindingStore.all(userID: credentials.userID).forEach {
                        self.enableC2CReceiveMessage(for: $0.deviceName)
                    }
                    self.refreshConversations()
                }
            }, fail: { [weak self] code, desc in
                Task { @MainActor in self?.loginState = .failed(code: Int(code), message: desc ?? "") }
            })
        } catch {
            loginState = .failed(code: -2, message: error.localizedDescription)
        }
#else
        // 参考工程提供的旧版 Framework 仅包含 iPhoneOS slice，模拟器只验证页面和流程。
        let userID = WatchIdentity.userID(for: channel)
        loginState = .loggedIn(userID: userID)
        WatchBindingStore.all(userID: userID).forEach {
            enableC2CReceiveMessage(for: $0.deviceName)
        }
        refreshConversations()
#endif
    }

    func logout(completion: (() -> Void)? = nil) {
#if canImport(ImSDK_Plus) && !targetEnvironment(simulator)
        if isLoggingOut {
            logoutCompletion = completion
            return
        }
        isLoggingOut = true
        logoutCompletion = completion
        manager.removeConversationListener(listener: listener)
        manager.removeAdvancedMsgListener(listener: listener)
        if sdkInitialized {
            manager.logout({ [weak self] in
                Task { @MainActor in self?.finishSDKLogout() }
            }, fail: { [weak self] _, _ in
                Task { @MainActor in self?.finishSDKLogout() }
            })
        } else {
            finishSDKLogout()
        }
#else
        completion?()
#endif
        activeConversation = nil
        conversations = []
        loginState = .loggedOut
    }

    private func finishSDKLogout() {
#if canImport(ImSDK_Plus) && !targetEnvironment(simulator)
        if sdkInitialized {
            manager.unInitSDK()
            sdkInitialized = false
        }
#endif
        isLoggingOut = false
        let completion = logoutCompletion
        logoutCompletion = nil
        completion?()
    }

    func refreshConversations() {
        conversationRefreshGeneration += 1
        let refreshGeneration = conversationRefreshGeneration
#if canImport(ImSDK_Plus) && !targetEnvironment(simulator)
        manager.getConversationList(0, count: 100, succ: { [weak self] list, _, _ in
            Task { @MainActor in
                guard let self else { return }
                let merged = self.mergeBoundWatchConversation((list ?? []).map { self.makeConversation($0) })
                guard refreshGeneration == self.conversationRefreshGeneration else { return }
                self.conversations = merged
                self.enrichGroupAvatars(merged, refreshGeneration: refreshGeneration)
            }
        }, fail: { [weak self] code, desc in
            WatchLogger.im.error("IM conversation load failed: \(code, privacy: .public) \(desc ?? "", privacy: .public)")
            Task { @MainActor in self?.conversations = [] }
        })
#else
        conversations = mergeBoundWatchConversation([])
#endif
    }

    private func enrichGroupAvatars(_ base: [MessageConversation], refreshGeneration: Int) {
        let groups = base.filter { $0.isGroup && $0.groupID?.isEmpty == false }
        guard !groups.isEmpty else { return }
        var enriched = base
        var remaining = groups.count
        for group in groups {
            loadGroupMembers(for: group) { [weak self] result in
                Task { @MainActor in
                    guard let self, refreshGeneration == self.conversationRefreshGeneration else { return }
                    let avatarKeys: [String]
                    switch result {
                    case .success(let members):
                        avatarKeys = Array(members.map(\.avatarKey).prefix(4))
                    case .failure:
                        avatarKeys = []
                    }
                    if let index = enriched.firstIndex(where: { $0.key == group.key }), !avatarKeys.isEmpty {
                        enriched[index].groupAvatarKeys = avatarKeys
                    }
                    remaining -= 1
                    if remaining == 0 {
                        self.conversations = enriched
                    }
                }
            }
        }
    }

    func loadMessages(for conversation: MessageConversation) {
        activeConversation = conversation
#if canImport(ImSDK_Plus) && !targetEnvironment(simulator)
        let success: ([V2TIMMessage]?) -> Void = { [weak self] list in
            Task { @MainActor in
                let messages = (list ?? []).compactMap { self?.makeMessage($0) }
                self?.onMessagesChange?(messages.sorted { $0.timestamp < $1.timestamp })
            }
        }
        if conversation.isGroup, let groupID = conversation.groupID {
            manager.getGroupHistoryMessageList(groupID, count: 50, lastMsg: nil, succ: success, fail: nil)
        } else if let userID = conversation.userID {
            manager.getC2CHistoryMessageList(userID, count: 50, lastMsg: nil, succ: success, fail: nil)
        } else {
            onMessagesChange?([])
        }
        markAsRead(conversation)
#else
        onMessagesChange?([])
#endif
    }

    func loadGroupCandidates(completion: @escaping (Result<[WatchImGroupCandidate], Error>) -> Void) {
#if canImport(ImSDK_Plus) && !targetEnvironment(simulator)
        manager.getFriendList({ [weak self] friends in
            guard let self else { return }
            let currentUser = self.loggedInUserID.map {
                WatchImGroupCandidate(userID: $0, displayName: $0, avatarKey: WatchAvatarResolver.key(for: $0), isWatch: false, isCurrentUser: true)
            }
            let contacts = (friends ?? []).compactMap { friend -> WatchImGroupCandidate? in
                let userID = friend.userID ?? ""
                guard !userID.isEmpty, userID != self.loggedInUserID else { return nil }
                let name = (friend.friendRemark?.isEmpty == false ? friend.friendRemark : nil)
                    ?? (friend.userFullInfo?.nickName.isEmpty == false ? friend.userFullInfo?.nickName : nil)
                    ?? userID
                return WatchImGroupCandidate(userID: userID, displayName: name, avatarKey: WatchAvatarResolver.key(for: userID), isWatch: false)
            }
            completion(.success(self.mergeGroupCandidates((currentUser.map { [$0] } ?? []) + contacts)))
        }, fail: { [weak self] code, desc in
            guard let self else { return }
            WatchLogger.im.error("IM friend list load failed: \(code, privacy: .public) \(desc ?? "", privacy: .public)")
            let currentUser = self.loggedInUserID.map {
                WatchImGroupCandidate(userID: $0, displayName: $0, avatarKey: WatchAvatarResolver.key(for: $0), isWatch: false, isCurrentUser: true)
            }
            completion(.success(self.mergeGroupCandidates(currentUser.map { [$0] } ?? [])))
        })
#else
        completion(.success(mergeGroupCandidates([])))
#endif
    }

    func loadGroupMembers(for conversation: MessageConversation, completion: @escaping (Result<[WatchImGroupMember], Error>) -> Void) {
#if canImport(ImSDK_Plus) && !targetEnvironment(simulator)
        guard conversation.isGroup, let groupID = conversation.groupID else {
            completion(.success([]))
            return
        }
        manager.getGroupMemberList(groupID, filter: 0, nextSeq: 0, succ: { _, members in
            let values = (members ?? []).map { member in
                WatchImGroupMember(userID: member.userID ?? "", displayName: (member.nameCard?.isEmpty == false ? member.nameCard : nil) ?? (member.nickName?.isEmpty == false ? member.nickName : nil) ?? member.userID ?? "", avatarKey: WatchAvatarResolver.key(for: member.userID ?? ""))
            }
            completion(.success(values.filter { !$0.userID.isEmpty }))
        }, fail: { code, desc in
            completion(.failure(NSError(domain: "ImSDK", code: Int(code), userInfo: [NSLocalizedDescriptionKey: desc ?? ""])))
        })
#else
        completion(.success([]))
#endif
    }

    func createGroup(memberIDs: [String], groupName: String, completion: @escaping (Result<MessageConversation, Error>) -> Void) {
#if canImport(ImSDK_Plus) && !targetEnvironment(simulator)
        guard let currentUserID = loggedInUserID else {
            completion(.failure(NSError(domain: "ImSDK", code: -1, userInfo: [NSLocalizedDescriptionKey: "IMSDK_NOT_LOGGED_IN"])))
            return
        }
        let ids = Array(Set((memberIDs + [currentUserID]).filter { !$0.isEmpty }))
        guard ids.count >= 2 else {
            completion(.failure(NSError(domain: "ImSDK", code: -2, userInfo: [NSLocalizedDescriptionKey: "IMSDK_GROUP_MEMBER_REQUIRED"])))
            return
        }
        let info = V2TIMGroupInfo()
        info.groupType = GroupType_Work
        info.groupName = groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? NSLocalizedString("watch_chat_default_group_title", comment: "") : groupName
        let members = ids.filter { $0 != currentUserID }.map { userID in
            let member = V2TIMCreateGroupMemberInfo()
            member.userID = userID
            return member
        }
        manager.createGroup(info, memberList: members, succ: { [weak self] groupID in
            guard let self else { return }
            self.refreshConversations()
            completion(.success(MessageConversation(key: "group_\(groupID ?? "")", titleKey: "watch_chat_default_group_title", avatarKey: "watch_avatar_family", isGroup: true, displayTitle: info.groupName, groupID: groupID)))
        }, fail: { code, desc in
            completion(.failure(NSError(domain: "ImSDK", code: Int(code), userInfo: [NSLocalizedDescriptionKey: desc ?? ""])))
        })
#else
        completion(.failure(NSError(domain: "ImSDK", code: -1000, userInfo: [NSLocalizedDescriptionKey: "SIMULATOR_SDK_UNAVAILABLE"])))
#endif
    }

    func inviteToGroup(_ conversation: MessageConversation, memberIDs: [String], completion: @escaping (Result<Void, Error>) -> Void) {
#if canImport(ImSDK_Plus) && !targetEnvironment(simulator)
        guard let groupID = conversation.groupID, !memberIDs.isEmpty else {
            completion(.failure(NSError(domain: "ImSDK", code: -1, userInfo: [NSLocalizedDescriptionKey: "IMSDK_GROUP_MEMBER_REQUIRED"])))
            return
        }
        let currentUserID = loggedInUserID ?? ""
        let userIDs = Array(Set(memberIDs.filter { !$0.isEmpty && $0 != currentUserID }))
        guard !userIDs.isEmpty else {
            completion(.failure(NSError(domain: "ImSDK", code: -1, userInfo: [NSLocalizedDescriptionKey: "IMSDK_GROUP_MEMBER_REQUIRED"])))
            return
        }
        manager.inviteUser(toGroup: groupID, userList: userIDs, succ: { results in
            let failed = (results ?? []).contains { $0.result.rawValue != 1 }
            if failed { completion(.failure(NSError(domain: "ImSDK", code: -2, userInfo: [NSLocalizedDescriptionKey: "IMSDK_GROUP_INVITE_PARTIAL_FAILURE"]))) }
            else { completion(.success(())) }
        }, fail: { code, desc in
            completion(.failure(NSError(domain: "ImSDK", code: Int(code), userInfo: [NSLocalizedDescriptionKey: desc ?? ""])))
        })
#else
        completion(.failure(NSError(domain: "ImSDK", code: -1000, userInfo: [NSLocalizedDescriptionKey: "SIMULATOR_SDK_UNAVAILABLE"])))
#endif
    }

    func sendText(_ text: String, to conversation: MessageConversation, completion: @escaping (Result<Void, Error>) -> Void) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
#if canImport(ImSDK_Plus) && !targetEnvironment(simulator)
        let message = manager.createTextMessage(trimmed)
        let receiver = conversation.isGroup ? nil : conversation.userID
        let groupID = conversation.isGroup ? conversation.groupID : nil
        manager.send(message, receiver: receiver, groupID: groupID, priority: V2TIMMessagePriority(rawValue: 0)!, onlineUserOnly: false, offlinePushInfo: nil, progress: nil, succ: {
            Task { @MainActor in completion(.success(())) }
        }, fail: { code, desc in
            Task { @MainActor in completion(.failure(NSError(domain: "ImSDK", code: Int(code), userInfo: [NSLocalizedDescriptionKey: desc ?? ""]))) }
        })
#else
        completion(.failure(NSError(domain: "ImSDK", code: -1000, userInfo: [NSLocalizedDescriptionKey: "SIMULATOR_SDK_UNAVAILABLE"])))
#endif
    }

    func sendCallSignal(_ signal: CallSignal, to userID: String, completion: @escaping (Result<Void, Error>) -> Void) {
#if canImport(ImSDK_Plus) && !targetEnvironment(simulator)
        do {
            let text = try CallSignalCodec.encode(signal)
            let message = manager.createTextMessage(text)
            manager.send(message, receiver: userID, groupID: nil, priority: V2TIMMessagePriority(rawValue: 2)!, onlineUserOnly: true, offlinePushInfo: nil, progress: nil, succ: {
                Task { @MainActor in completion(.success(())) }
            }, fail: { code, desc in
                Task { @MainActor in completion(.failure(NSError(domain: "ImSDK", code: Int(code), userInfo: [NSLocalizedDescriptionKey: desc ?? ""]))) }
            })
        } catch {
            completion(.failure(error))
        }
#else
        completion(.failure(NSError(domain: "ImSDK", code: -1000, userInfo: [NSLocalizedDescriptionKey: "SIMULATOR_SDK_UNAVAILABLE"])))
#endif
    }

    func setDraft(_ draft: String, for conversation: MessageConversation) {
#if canImport(ImSDK_Plus) && !targetEnvironment(simulator)
        manager.setConversationDraft(conversation.key, draftText: draft, succ: nil, fail: nil)
#endif
    }

    func markAsRead(_ conversation: MessageConversation) {
#if canImport(ImSDK_Plus) && !targetEnvironment(simulator)
        if conversation.isGroup, let groupID = conversation.groupID {
            manager.markGroupMessage(asRead: groupID, succ: nil, fail: nil)
        } else if let userID = conversation.userID {
            manager.markC2CMessage(asRead: userID, succ: nil, fail: nil)
        }
#endif
    }

    func setMuted(_ muted: Bool, for conversation: MessageConversation, completion: @escaping (Result<Void, Error>) -> Void) {
#if canImport(ImSDK_Plus) && !targetEnvironment(simulator)
        let opt: V2TIMReceiveMessageOpt = V2TIMReceiveMessageOpt(rawValue: muted ? 2 : 0)!
        let success: () -> Void = { [weak self] in Task { @MainActor in completion(.success(())); self?.refreshConversations() }; }
        let failure: (Int32, String?) -> Void = { code, desc in
            Task { @MainActor in completion(.failure(NSError(domain: "ImSDK", code: Int(code), userInfo: [NSLocalizedDescriptionKey: desc ?? ""]))) }
        }
        if conversation.isGroup, let groupID = conversation.groupID {
            manager.setGroupReceiveMessageOpt(groupID, opt: opt, succ: success, fail: failure)
        } else if let userID = conversation.userID {
            manager.setC2CReceiveMessageOpt([userID], opt: opt, succ: success, fail: failure)
        }
#else
        completion(.failure(NSError(domain: "ImSDK", code: -1000, userInfo: [NSLocalizedDescriptionKey: "SIMULATOR_SDK_UNAVAILABLE"])))
#endif
    }

    func enableC2CReceiveMessage(for userID: String) {
#if canImport(ImSDK_Plus) && !targetEnvironment(simulator)
        guard !userID.isEmpty, loggedInUserID != nil else {
            WatchLogger.im.warning("IMSDK C2C receive enable skipped: peer=\(userID, privacy: .public)")
            return
        }
        let opt = V2TIMReceiveMessageOpt(rawValue: 0)!
        manager.setC2CReceiveMessageOpt([userID], opt: opt, succ: {
            WatchLogger.im.info("IMSDK C2C receive enabled: peer=\(userID, privacy: .public)")
        }, fail: { code, desc in
            WatchLogger.im.error(
                "IMSDK C2C receive enable failed: peer=\(userID, privacy: .public), code=\(code), message=\(desc ?? "", privacy: .public)"
            )
        })
#else
        _ = userID
#endif
    }

    func setPinned(_ pinned: Bool, for conversation: MessageConversation, completion: @escaping (Result<Void, Error>) -> Void) {
#if canImport(ImSDK_Plus) && !targetEnvironment(simulator)
        manager.pinConversation(conversation.key, isPinned: pinned, succ: {
            Task { @MainActor in completion(.success(())); self.refreshConversations() }
        }, fail: { code, desc in
            Task { @MainActor in completion(.failure(NSError(domain: "ImSDK", code: Int(code), userInfo: [NSLocalizedDescriptionKey: desc ?? ""]))) }
        })
#else
        completion(.failure(NSError(domain: "ImSDK", code: -1000, userInfo: [NSLocalizedDescriptionKey: "SIMULATOR_SDK_UNAVAILABLE"])))
#endif
    }

    func clearHistory(for conversation: MessageConversation, completion: @escaping (Result<Void, Error>) -> Void) {
#if canImport(ImSDK_Plus) && !targetEnvironment(simulator)
        let success: () -> Void = { [weak self] in Task { @MainActor in completion(.success(())); self?.loadMessages(for: conversation) }; }
        let failure: (Int32, String?) -> Void = { code, desc in
            Task { @MainActor in completion(.failure(NSError(domain: "ImSDK", code: Int(code), userInfo: [NSLocalizedDescriptionKey: desc ?? ""]))) }
        }
        if conversation.isGroup, let groupID = conversation.groupID {
            manager.clearGroupHistoryMessage(groupID, succ: success, fail: failure)
        } else if let userID = conversation.userID {
            manager.clearC2CHistoryMessage(userID, succ: success, fail: failure)
        }
#else
        completion(.failure(NSError(domain: "ImSDK", code: -1000, userInfo: [NSLocalizedDescriptionKey: "SIMULATOR_SDK_UNAVAILABLE"])))
#endif
    }

#if canImport(ImSDK_Plus)
    private func makeConversation(_ conversation: V2TIMConversation) -> MessageConversation {
        let isGroup = conversation.type.rawValue == 2
        let conversationID = conversation.conversationID ?? ""
        let boundDeviceNames = Set(WatchBindingStore.all(userID: loggedInUserID).map(\.deviceName))
        let title = conversation.userID.map { boundDeviceNames.contains($0) } == true
            ? conversation.userID
            : ((conversation.showName?.isEmpty == false ? conversation.showName : nil) ?? conversation.userID ?? conversation.groupID ?? conversation.conversationID)
        return MessageConversation(
            key: conversationID,
            titleKey: isGroup ? "watch_message_family" : "watch_chat_default_title",
            avatarKey: isGroup ? "watch_avatar_family" : WatchAvatarResolver.key(for: conversation.userID ?? conversationID),
            isGroup: isGroup,
            displayTitle: title,
            preview: conversation.lastMessage?.textElem?.text ?? conversation.draftText,
            timestamp: conversation.lastMessage?.timestamp,
            unreadCount: Int(conversation.unreadCount),
            isPinned: conversation.isPinned,
            isMuted: conversation.recvOpt.rawValue != 0,
            userID: conversation.userID,
            groupID: conversation.groupID,
            isLocalBinding: conversation.userID.map { boundDeviceNames.contains($0) } == true
        )
    }

    private func makeMessage(_ message: V2TIMMessage) -> WatchImMessage? {
        guard message.elemType.rawValue == 1, let text = message.textElem?.text else { return nil }
        return WatchImMessage(id: message.msgID ?? UUID().uuidString, text: text, senderID: message.sender ?? "", isOutgoing: message.isSelf, timestamp: message.timestamp ?? Date())
    }

    private func handleIncoming(_ message: V2TIMMessage) {
        // IMSDK returns nil for groupID on C2C messages. Treat nil as the C2C discriminator
        // instead of dereferencing groupID as a non-empty String.
        if !message.isSelf, message.groupID == nil, let text = message.textElem?.text, let signal = CallSignalCodec.decode(text) {
            onCallSignalReceived?(IncomingCallSignal(senderID: message.sender ?? "", signal: signal))
            return
        }
        guard let current = activeConversation, let mapped = makeMessage(message) else {
            refreshConversations()
            return
        }
        let matches = current.isGroup ? message.groupID == current.groupID : message.userID == current.userID
        if matches {
            onMessageReceived?(current, mapped)
            loadMessages(for: current)
        }
        refreshConversations()
    }
#endif

    private func mergeBoundWatchConversation(_ conversations: [MessageConversation]) -> [MessageConversation] {
        let bindings = WatchBindingStore.all(userID: loggedInUserID)
        if bindings.isEmpty { return conversations }
        let existing = Set(conversations.compactMap { !$0.isGroup ? $0.userID : nil })
        let missing = bindings.filter { !existing.contains($0.deviceName) }.map { bound in
            MessageConversation(
                key: "c2c_\(bound.deviceName)",
                titleKey: "watch_chat_default_title",
                avatarKey: WatchAvatarResolver.key(for: bound.deviceName),
                isGroup: false,
                displayTitle: bound.deviceName,
                userID: bound.deviceName,
                isLocalBinding: true
            )
        }
        return conversations + missing
    }

    private func mergeGroupCandidates(_ contacts: [WatchImGroupCandidate]) -> [WatchImGroupCandidate] {
        let currentUser = loggedInUserID.map {
            WatchImGroupCandidate(userID: $0, displayName: $0, avatarKey: WatchAvatarResolver.key(for: $0), isWatch: false, isCurrentUser: true)
        }
        let watches = WatchBindingStore.all(userID: loggedInUserID).map { bound in
            WatchImGroupCandidate(userID: bound.deviceName, displayName: bound.deviceName, avatarKey: WatchAvatarResolver.key(for: bound.deviceName), isWatch: true)
        }
        return ((currentUser.map { [$0] } ?? []) + contacts + watches)
            .filter { !$0.userID.isEmpty }
            .reduce(into: [String: WatchImGroupCandidate]()) { $0[$1.userID] = $0[$1.userID] ?? $1 }
            .values
            .sorted { lhs, rhs in
                if lhs.isCurrentUser != rhs.isCurrentUser { return lhs.isCurrentUser }
                if lhs.isWatch != rhs.isWatch { return lhs.isWatch }
                return lhs.displayName < rhs.displayName
            }
    }

}


#if canImport(ImSDK_Plus)
private final class Listener: NSObject, V2TIMConversationListener, V2TIMAdvancedMsgListener {
    var onConversationChange: (() -> Void)?
    var onMessage: ((V2TIMMessage) -> Void)?

    func onNewConversation(conversationList: [V2TIMConversation]) { onConversationChange?() }
    func onConversationChanged(conversationList: [V2TIMConversation]) { onConversationChange?() }
    func onRecvNewMessage(msg: V2TIMMessage) { onMessage?(msg) }
}
#endif
