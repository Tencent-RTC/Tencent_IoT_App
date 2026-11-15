import UIKit

final class MessagesViewController: UIViewController {
    private let manager: ImService
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let listStack = UIStackView()
    private var allConversations: [MessageConversation] = []
    private var conversationByRowID: [ObjectIdentifier: MessageConversation] = [:]
    private var lastConversationRefreshAt: Date?
    var onOpenConversation: ((MessageConversation) -> Void)?
    var onAddContact: (() -> Void)?

    init(manager: ImService) {
        self.manager = manager
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = WatchTheme.background
        buildView()
        manager.onConversationsChange = { [weak self] conversations in
            self?.allConversations = conversations
            self?.render(conversations)
        }
        refreshConversationsIfNeeded(force: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshConversationsIfNeeded()
    }

    private func refreshConversationsIfNeeded(force: Bool = false) {
        if !force, let lastConversationRefreshAt, Date().timeIntervalSince(lastConversationRefreshAt) < 1.0 {
            return
        }
        lastConversationRefreshAt = Date()
        manager.refreshConversations()
    }

    private func buildView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 0
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40)
        ])

        let heading = UIStackView()
        heading.axis = .horizontal
        heading.alignment = .center
        heading.addArrangedSubview(WatchTheme.label("watch_messages", size: 24, weight: .bold))
        heading.addArrangedSubview(UIView())
        heading.addArrangedSubview(iconButton(.plus, label: "watch_message_add") { [weak self] in self?.onAddContact?() })
        stack.addArrangedSubview(heading)

        let search = UITextField()
        search.translatesAutoresizingMaskIntoConstraints = false
        search.placeholder = NSLocalizedString("watch_search_hint", comment: "")
        search.font = .systemFont(ofSize: 13)
        search.textColor = WatchTheme.primaryText
        search.backgroundColor = WatchTheme.surface
        search.layer.cornerRadius = 12
        search.layer.borderColor = WatchTheme.line.cgColor
        search.layer.borderWidth = 1
        search.leftView = WatchTheme.icon(.search, tint: WatchTheme.tertiaryText, size: 18)
        search.leftViewMode = .always
        search.addTarget(self, action: #selector(searchChanged(_:)), for: .editingChanged)
        search.heightAnchor.constraint(equalToConstant: 44).isActive = true
        stack.setCustomSpacing(8, after: heading)
        stack.addArrangedSubview(search)

        let list = WatchTheme.card()
        listStack.translatesAutoresizingMaskIntoConstraints = false
        listStack.axis = .vertical
        listStack.spacing = 0
        list.addSubview(listStack)
        NSLayoutConstraint.activate([
            listStack.leadingAnchor.constraint(equalTo: list.leadingAnchor),
            listStack.trailingAnchor.constraint(equalTo: list.trailingAnchor),
            listStack.topAnchor.constraint(equalTo: list.topAnchor, constant: 4),
            listStack.bottomAnchor.constraint(equalTo: list.bottomAnchor, constant: -4)
        ])
        stack.setCustomSpacing(14, after: search)
        stack.addArrangedSubview(list)
    }

    private func iconButton(_ kind: WatchIconKind, label: String, action: (() -> Void)? = nil) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        if label == "watch_message_add" { button.accessibilityIdentifier = "message.add" }
        button.accessibilityLabel = NSLocalizedString(label, comment: "")
        let icon = WatchTheme.icon(kind, tint: WatchTheme.primaryText, size: 20)
        button.addSubview(icon)
        button.backgroundColor = WatchTheme.surface
        button.layer.cornerRadius = 14
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 40), button.heightAnchor.constraint(equalToConstant: 40),
            icon.centerXAnchor.constraint(equalTo: button.centerXAnchor), icon.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])
        if let action {
            button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        }
        return button
    }

    private func render(_ conversations: [MessageConversation]) {
        listStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        conversationByRowID.removeAll()
        if conversations.isEmpty {
            let empty = WatchTheme.label("watch_im_empty", size: 14, color: WatchTheme.secondaryText)
            empty.textAlignment = .center
            empty.numberOfLines = 0
            empty.heightAnchor.constraint(equalToConstant: 92).isActive = true
            listStack.addArrangedSubview(empty)
            return
        }
        conversations.forEach { listStack.addArrangedSubview(messageRow($0)) }
    }

    private func messageRow(_ conversation: MessageConversation) -> UIView {
        let row = UIButton(type: .custom)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.backgroundColor = .clear
        let tap = UITapGestureRecognizer(target: self, action: #selector(conversationRowGestureTapped(_:)))
        tap.cancelsTouchesInView = true
        row.addGestureRecognizer(tap)
        conversationByRowID[ObjectIdentifier(row)] = conversation
        row.accessibilityIdentifier = "message.conversation.\(conversation.userID ?? conversation.key)"
        row.accessibilityLabel = conversation.displayTitle ?? NSLocalizedString(conversation.titleKey, comment: "")
        let avatar = conversation.groupAvatarKeys.count > 1
            ? GroupAvatarComposer.make(textKeys: conversation.groupAvatarKeys, backgroundColor: WatchTheme.blue.withAlphaComponent(0.22), size: 44)
            : WatchTheme.avatar(textKey: conversation.avatarKey, color: WatchTheme.blue.withAlphaComponent(0.22), size: 44)
        let avatarContainer = UIView()
        avatarContainer.translatesAutoresizingMaskIntoConstraints = false
        avatarContainer.clipsToBounds = false
        avatarContainer.addSubview(avatar)
        let title = WatchTheme.label(conversation.titleKey, size: 15, weight: .semibold)
        title.text = conversation.displayTitle ?? title.text
        let preview = WatchTheme.label(conversation.preview == nil ? "watch_im_no_message" : "", size: 13, color: WatchTheme.secondaryText)
        preview.text = conversation.preview ?? preview.text
        preview.numberOfLines = 1
        let texts = UIStackView(arrangedSubviews: [title, preview])
        texts.axis = .vertical; texts.spacing = 4; texts.translatesAutoresizingMaskIntoConstraints = false
        let metadata = UIView()
        metadata.translatesAutoresizingMaskIntoConstraints = false
        let time = WatchTheme.label(formatConversationTime(conversation.timestamp), size: 11, color: WatchTheme.tertiaryText)
        let unread = UILabel()
        unread.text = conversation.unreadCount > 99 ? "99+" : "\(conversation.unreadCount)"
        unread.textColor = WatchTheme.surface
        unread.font = .systemFont(ofSize: 10, weight: .bold)
        unread.textAlignment = .center
        unread.backgroundColor = WatchTheme.red
        unread.layer.borderColor = WatchTheme.surface.cgColor
        unread.layer.borderWidth = 2
        unread.layer.cornerRadius = 9
        unread.layer.masksToBounds = true
        unread.isHidden = conversation.unreadCount <= 0
        unread.setContentHuggingPriority(.required, for: .horizontal)
        unread.setContentCompressionResistancePriority(.required, for: .horizontal)
        metadata.addSubview(time)
        avatarContainer.addSubview(unread)
        row.addSubview(avatarContainer); row.addSubview(texts); row.addSubview(metadata)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 72), avatarContainer.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14), avatarContainer.centerYAnchor.constraint(equalTo: row.centerYAnchor), avatarContainer.widthAnchor.constraint(equalToConstant: 44), avatarContainer.heightAnchor.constraint(equalToConstant: 44),
            avatar.centerXAnchor.constraint(equalTo: avatarContainer.centerXAnchor), avatar.centerYAnchor.constraint(equalTo: avatarContainer.centerYAnchor),
            unread.topAnchor.constraint(equalTo: avatarContainer.topAnchor, constant: -4), unread.trailingAnchor.constraint(equalTo: avatarContainer.trailingAnchor, constant: 7), unread.heightAnchor.constraint(equalToConstant: 18), unread.widthAnchor.constraint(greaterThanOrEqualToConstant: 18),
            texts.leadingAnchor.constraint(equalTo: avatarContainer.trailingAnchor, constant: 12), texts.centerYAnchor.constraint(equalTo: row.centerYAnchor), texts.trailingAnchor.constraint(lessThanOrEqualTo: metadata.leadingAnchor, constant: -8),
            metadata.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14), metadata.topAnchor.constraint(equalTo: row.topAnchor, constant: 12), metadata.heightAnchor.constraint(equalToConstant: 18), metadata.widthAnchor.constraint(equalToConstant: 56),
            time.topAnchor.constraint(equalTo: metadata.topAnchor), time.trailingAnchor.constraint(equalTo: metadata.trailingAnchor)
        ])
        return row
    }

    @objc private func conversationRowGestureTapped(_ gesture: UITapGestureRecognizer) {
        guard let row = gesture.view as? UIButton,
              let conversation = conversationByRowID[ObjectIdentifier(row)] else { return }
        WatchLogger.ui.info("Message conversation activated: \(conversation.key, privacy: .public)")
        onOpenConversation?(conversation)
    }

    private func formatConversationTime(_ date: Date?) -> String {
        guard let date else { return "" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return conversationDateFormatter("HH:mm").string(from: date)
        }
        if calendar.isDateInYesterday(date) {
            return NSLocalizedString("watch_time_yesterday", comment: "")
        }
        if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) {
            return conversationDateFormatter("MM/dd").string(from: date)
        }
        return conversationDateFormatter("yyyy/MM/dd").string(from: date)
    }

    private func conversationDateFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = format
        return formatter
    }

    @objc private func searchChanged(_ textField: UITextField) {
        let query = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard !query.isEmpty else { render(allConversations); return }
        render(allConversations.filter { ($0.displayTitle ?? NSLocalizedString($0.titleKey, comment: "")).lowercased().contains(query) || ($0.preview ?? "").lowercased().contains(query) })
    }
}
