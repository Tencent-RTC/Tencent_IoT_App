import UIKit

final class MainTabViewController: UIViewController {
    private let store: AppStateStore
    private let contentView = UIView()
    private let pageMarker = UIView()
    private let tabBar = UIStackView()
    private var tabItems: [AppStateStore.Tab: WatchTabItemView] = [:]
    private var rootControllers: [AppStateStore.Tab: UIViewController] = [:]
    private weak var currentChild: UIViewController?
    private var currentTab: AppStateStore.Tab?
    private var callObserverID: UUID?
    private var contentBottomConstraint: NSLayoutConstraint!
    private var messageDrafts: [String: String] = [:]
    var onLogout: (() -> Void)?

    init(store: AppStateStore) { self.store = store; super.init(nibName: nil, bundle: nil) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        if let callObserverID {
            let store = store
            Task { @MainActor in
                store.removeCallStateObserver(callObserverID)
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = WatchTheme.background
        buildView()
        callObserverID = store.addCallStateObserver { [weak self] state in self?.handleCallState(state) }
        show(store.selectedTab)
    }

    private func buildView() {
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentView)
        contentBottomConstraint = contentView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -94)
        NSLayoutConstraint.activate([contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor), contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor), contentView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), contentBottomConstraint])
        pageMarker.translatesAutoresizingMaskIntoConstraints = false
        pageMarker.isAccessibilityElement = true
        pageMarker.isUserInteractionEnabled = false
        contentView.addSubview(pageMarker)
        NSLayoutConstraint.activate([
            pageMarker.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            pageMarker.topAnchor.constraint(equalTo: contentView.topAnchor),
            pageMarker.widthAnchor.constraint(equalToConstant: 1),
            pageMarker.heightAnchor.constraint(equalToConstant: 1)
        ])

        tabBar.translatesAutoresizingMaskIntoConstraints = false
        tabBar.axis = .horizontal; tabBar.alignment = .center; tabBar.distribution = .fillEqually; tabBar.spacing = 2
        tabBar.backgroundColor = WatchTheme.surface; tabBar.layer.cornerRadius = 36; tabBar.layer.shadowColor = UIColor.black.withAlphaComponent(0.12).cgColor; tabBar.layer.shadowOpacity = 1; tabBar.layer.shadowRadius = 12; tabBar.layer.shadowOffset = CGSize(width: 0, height: 5)
        view.addSubview(tabBar)
        NSLayoutConstraint.activate([tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24), tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24), tabBar.topAnchor.constraint(equalTo: contentView.bottomAnchor, constant: 8), tabBar.heightAnchor.constraint(equalToConstant: 72), tabBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -14)])

        addTab("watch_messages", .messages, .message)
        addTab("watch_location", .location, .pin)
        let call = UIButton(type: .system); call.translatesAutoresizingMaskIntoConstraints = false; call.accessibilityIdentifier = "tab.call"; call.accessibilityLabel = NSLocalizedString("watch_call", comment: ""); call.accessibilityTraits = .button; call.backgroundColor = .clear; call.layer.cornerRadius = 29; call.layer.borderWidth = 4; call.layer.borderColor = WatchTheme.background.cgColor; call.clipsToBounds = true
        let callGradient = WatchGradientView(); callGradient.isUserInteractionEnabled = false; call.insertSubview(callGradient, at: 0); NSLayoutConstraint.activate([callGradient.leadingAnchor.constraint(equalTo: call.leadingAnchor), callGradient.trailingAnchor.constraint(equalTo: call.trailingAnchor), callGradient.topAnchor.constraint(equalTo: call.topAnchor), callGradient.bottomAnchor.constraint(equalTo: call.bottomAnchor)])
        let callIcon = WatchTheme.icon(.phone, tint: WatchTheme.surface, size: 26); call.addSubview(callIcon); NSLayoutConstraint.activate([callIcon.centerXAnchor.constraint(equalTo: call.centerXAnchor), callIcon.centerYAnchor.constraint(equalTo: call.centerYAnchor)]); call.addAction(UIAction { [weak self] _ in WatchLogger.ui.info("Bottom tab activated: call"); self?.presentCallTargetPicker() }, for: .touchUpInside); call.transform = CGAffineTransform(translationX: 0, y: -8)
        let callContainer = UIView(); callContainer.translatesAutoresizingMaskIntoConstraints = false; callContainer.addSubview(call)
        NSLayoutConstraint.activate([callContainer.heightAnchor.constraint(equalToConstant: 72), call.centerXAnchor.constraint(equalTo: callContainer.centerXAnchor), call.centerYAnchor.constraint(equalTo: callContainer.centerYAnchor), call.widthAnchor.constraint(equalToConstant: 58), call.heightAnchor.constraint(equalToConstant: 58)])
        tabBar.addArrangedSubview(callContainer)
        addTab("watch_devices", .devices, .device)
        addTab("watch_profile", .profile, .profile)
        tabBar.isAccessibilityElement = false
        tabBar.accessibilityElements = [tabItems[.messages], tabItems[.location], call, tabItems[.devices], tabItems[.profile]].compactMap { $0 }
    }

    private func presentCallTargetPicker() {
        guard presentedViewController == nil else { return }
        let picker = CallTargetPickerViewController(store: store)
        picker.modalPresentationStyle = .overFullScreen
        picker.modalTransitionStyle = .crossDissolve
        present(picker, animated: true)
    }

    private func addTab(_ key: String, _ tab: AppStateStore.Tab, _ icon: WatchIconKind) {
        let item = WatchTabItemView(title: key, iconKind: icon)
        item.accessibilityIdentifier = "tab.\(tabIdentifier(tab))"
        item.heightAnchor.constraint(equalToConstant: 72).isActive = true
        item.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            WatchLogger.ui.info("Bottom tab activated: \(self.tabIdentifier(tab), privacy: .public)")
            self.store.select(tab)
            self.show(tab)
        }, for: .touchUpInside)
        tabItems[tab] = item; tabBar.addArrangedSubview(item)
    }

    private func tabIdentifier(_ tab: AppStateStore.Tab) -> String {
        switch tab {
        case .messages: return "messages"
        case .location: return "location"
        case .devices: return "devices"
        case .profile: return "profile"
        }
    }

    private func show(_ tab: AppStateStore.Tab) {
        WatchLogger.ui.info("Show tab requested: \(self.tabIdentifier(tab), privacy: .public), authenticated=\(self.store.isAuthenticated, privacy: .public)")
        pageMarker.accessibilityIdentifier = "page.\(tabIdentifier(tab))"
        tabBar.isHidden = false
        contentBottomConstraint.constant = -94
        tabItems.forEach { $0.value.isSelected = $0.key == tab }
        // 绑定关系按登录账号实时读取；设备和定位页不能复用绑定前创建的空态控制器。
        if tab == .devices || tab == .location {
            rootControllers[tab] = nil
        }
        let controller = rootController(for: tab)
        if currentTab == tab, currentChild === controller {
            WatchLogger.ui.info("Show tab skipped: already visible \(self.tabIdentifier(tab), privacy: .public)")
            return
        }
        currentTab = tab
        showChild(controller)
        WatchLogger.ui.info("Show tab completed: \(self.tabIdentifier(tab), privacy: .public)")
    }

    private func rootController(for tab: AppStateStore.Tab) -> UIViewController {
        if let controller = rootControllers[tab] { return controller }
        let controller: UIViewController
        switch tab {
        case .messages:
            let messages = MessagesViewController(manager: store.imManager)
            messages.onOpenConversation = { [weak self] conversation in self?.showChat(conversation) }
            messages.onAddContact = { [weak self] in self?.showAddContact() }
            controller = messages
        case .location:
            controller = LocationViewController(store: store)
        case .devices:
            let devices = DevicesViewController(store: store)
            devices.onAddWatch = { [weak self] in self?.showWatchScanner(returnToDevices: true) }
            controller = devices
        case .profile:
            let profile = ProfileViewController(userID: store.imManager.loggedInUserID ?? "account")
            profile.onLogout = { [weak self] in
                guard let self else { return }
                store.logout()
                onLogout?()
            }
            controller = profile
        }
        rootControllers[tab] = controller
        return controller
    }

    private func showChat(_ conversation: MessageConversation, draft: String? = nil) {
        let currentDraft = draft ?? messageDrafts[conversation.key] ?? ""
        tabBar.isHidden = true
        contentBottomConstraint.constant = 0
        let controller = ChatViewController(manager: store.imManager, conversation: conversation, draft: currentDraft)
        controller.onBack = { [weak self] draft in
            self?.messageDrafts[conversation.key] = draft
            self?.show(.messages)
        }
        controller.onInfo = { [weak self] conversation, draft in
            self?.messageDrafts[conversation.key] = draft
            self?.showChatInfo(conversation, draft: draft)
        }
        showChild(controller)
    }

    private func showChatInfo(_ conversation: MessageConversation, draft: String) {
        tabBar.isHidden = true
        contentBottomConstraint.constant = 0
        let controller = ChatInfoViewController(manager: store.imManager, conversation: conversation)
        controller.onBack = { [weak self] in self?.showChat(conversation, draft: draft) }
        controller.onInvite = { [weak self] conversation in self?.showGroupMemberPicker(for: conversation) }
        showChild(controller)
    }

    private func showGroupMemberPicker(for conversation: MessageConversation? = nil) {
        tabBar.isHidden = true
        contentBottomConstraint.constant = 0
        let picker = GroupMemberPickerViewController(manager: store.imManager)
        if conversation == nil || conversation?.isGroup == false {
            picker.setDefaultSelectedUserIDs(Set([store.imManager.loggedInUserID, conversation?.userID].compactMap { $0 }))
        }
        picker.onBack = { [weak self] in
            guard let self else { return }
            if let conversation {
                self.showChatInfo(conversation, draft: self.messageDrafts[conversation.key] ?? "")
            } else {
                self.showAddContact()
            }
        }
        picker.onDone = { [weak self, weak picker] selected in
            guard let self else { return }
            let selectedIDs = selected.map(\.userID)
            if let conversation, conversation.isGroup {
                self.store.imManager.inviteToGroup(conversation, memberIDs: selectedIDs) { result in
                    DispatchQueue.main.async {
                        if case .success = result {
                            let alert = UIAlertController(title: nil, message: NSLocalizedString("watch_group_invite_done", comment: ""), preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: NSLocalizedString("watch_common_ok", comment: ""), style: .default) { _ in self.showChatInfo(conversation, draft: self.messageDrafts[conversation.key] ?? "") })
                            self.present(alert, animated: true)
                        } else {
                            let message = result.failureMessage
                            let alert = UIAlertController(title: nil, message: String(format: NSLocalizedString("watch_group_invite_failed", comment: ""), message), preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: NSLocalizedString("watch_common_ok", comment: ""), style: .default))
                            self.present(alert, animated: true)
                        }
                    }
                }
            } else {
                let names = ([conversation?.displayTitle] + selected.filter { !$0.isCurrentUser }.map(\.displayName)).compactMap { $0 }.filter { !$0.isEmpty }.prefix(3)
                self.store.imManager.createGroup(memberIDs: ([conversation?.userID] + selectedIDs).compactMap { $0 }, groupName: names.joined(separator: NSLocalizedString("watch_group_name_separator", comment: "")) + NSLocalizedString("watch_chat_default_group_title", comment: "")) { result in
                    DispatchQueue.main.async {
                        if case .success(let group) = result { self.showChat(group) }
                        else {
                            let message = result.failureMessage
                            let alert = UIAlertController(title: nil, message: String(format: NSLocalizedString("watch_group_create_failed", comment: ""), message), preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: NSLocalizedString("watch_common_ok", comment: ""), style: .default))
                            self.present(alert, animated: true)
                        }
                    }
                }
            }
            _ = picker
        }
        showChild(picker)
    }

    private func showAddContact() {
        tabBar.isHidden = true
        contentBottomConstraint.constant = 0
        let controller = AddContactViewController()
        controller.onBack = { [weak self] in self?.show(.messages) }
        controller.onAddWatch = { [weak self] in self?.showBindWatchPage() }
        controller.onCreateGroup = { [weak self] in self?.showGroupMemberPicker() }
        showChild(controller)
    }

    private func showBindWatchPage(returnToDevices: Bool = false) {
        tabBar.isHidden = true
        contentBottomConstraint.constant = 0
        let controller = BindWatchViewController()
        controller.onBack = { [weak self] in
            if returnToDevices { self?.show(.devices) } else { self?.showAddContact() }
        }
        controller.onBind = { [weak self, weak controller] deviceName in
            guard let self,
                  let bound = WatchBindingStore.bind(deviceName: deviceName, userID: self.store.imManager.loggedInUserID ?? "") else {
                controller?.showError(NSLocalizedString("watch_bind_watch_device_required", comment: ""))
                return
            }
            self.store.imManager.enableC2CReceiveMessage(for: bound.deviceName)
            self.store.imManager.refreshConversations()
            self.showChat(self.store.imManager.directConversation(peerID: bound.deviceName, displayName: bound.deviceName))
        }
        showChild(controller)
    }

    private func showWatchScanner(returnToDevices: Bool = false) {
        tabBar.isHidden = true
        contentBottomConstraint.constant = 0
        let controller = WatchQrScannerViewController()
        controller.onBack = { [weak self] in
            if returnToDevices { self?.show(.devices) } else { self?.showAddContact() }
        }
        controller.onScan = { [weak self] value in
            guard let self else { return }
            if returnToDevices { self.show(.devices) } else { self.showAddContact() }
            let alert = UIAlertController(title: NSLocalizedString("watch_scan_result_title", comment: ""), message: value, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("watch_common_ok", comment: ""), style: .default))
            self.present(alert, animated: true)
        }
        showChild(controller)
    }

    private func showChild(_ controller: UIViewController) {
        if currentChild === controller { return }
        children.forEach { child in child.willMove(toParent: nil); child.view.removeFromSuperview(); child.removeFromParent() }
        controller.view.alpha = 0
        attachChild(controller, to: contentView)
        currentChild = controller
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut, .beginFromCurrentState, .allowAnimatedContent]) {
            controller.view.alpha = 1
        }
    }

    private func handleCallState(_ state: CallUIState) {
        guard isViewLoaded, view.window != nil else { return }
        switch state.phase {
        case .incoming:
            guard presentedViewController == nil else { return }
            let incoming = IncomingCallViewController(store: store, state: state)
            incoming.modalPresentationStyle = .fullScreen
            present(incoming, animated: true)
        case .active:
            if presentedViewController is IncomingCallViewController {
                presentedViewController?.dismiss(animated: true) { [weak self] in self?.presentActiveCall(state) }
            } else if presentedViewController == nil {
                presentActiveCall(state)
            }
        case .idle:
            if presentedViewController is OutgoingCallViewController { presentedViewController?.dismiss(animated: true) }
        case .outgoing:
            break
        }
    }

    private func presentActiveCall(_ state: CallUIState) {
        guard let target = state.target, presentedViewController == nil else { return }
        let avatarKey = WatchAvatarResolver.key(for: target.avatarID)
        let avatarColor = WatchTheme.mint.withAlphaComponent(0.22)
        let call = OutgoingCallViewController(store: store, displayName: target.displayName, avatarKey: avatarKey, avatarColor: avatarColor, voiceMode: state.mediaType == .audio)
        call.modalPresentationStyle = .fullScreen
        present(call, animated: true)
    }
}

private extension Result where Failure: Error {
    var failureMessage: String {
        if case .failure(let error) = self { return error.localizedDescription }
        return ""
    }
}
