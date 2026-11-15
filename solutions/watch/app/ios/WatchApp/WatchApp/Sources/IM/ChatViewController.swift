import UIKit

final class ChatViewController: UIViewController {
    private let manager: ImService
    private let conversation: MessageConversation
    private var draft: String
    private let draftTextView = UITextView()
    private let inputModeButton = UIButton(type: .system)
    private let sendButton = UIButton(type: .system)
    private let historyScroll = UIScrollView()
    private let history = UIStackView()
    private var textMode = true

    var onBack: ((String) -> Void)?
    var onInfo: ((MessageConversation, String) -> Void)?

    init(manager: ImService, conversation: MessageConversation, draft: String = "") {
        self.manager = manager
        self.conversation = conversation
        self.draft = draft
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = WatchTheme.background
        buildView()
        manager.onMessagesChange = { [weak self] messages in self?.render(messages) }
        manager.loadMessages(for: conversation)
    }

    private func buildView() {
        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)

        let back = WatchTheme.backButton(
            identifier: "chat.back",
            label: NSLocalizedString("watch_chat_back", comment: "")
        ) { [weak self] in
            self?.leave()
        }
        header.addSubview(back)

        let title = WatchTheme.label(conversation.displayTitle ?? conversation.titleKey, size: 19, weight: .bold)
        if conversation.displayTitle == nil { title.text = NSLocalizedString(conversation.titleKey, comment: "") }
        title.textAlignment = .center
        header.addSubview(title)

        let info = UIButton(type: .system)
        info.translatesAutoresizingMaskIntoConstraints = false
        info.accessibilityIdentifier = "chat.info"
        info.accessibilityLabel = NSLocalizedString(conversation.isGroup ? "watch_group_info" : "watch_chat_members", comment: "")
        let infoIcon = WatchTheme.icon(.more, tint: WatchTheme.secondaryText, size: 20)
        info.addSubview(infoIcon)
        info.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.onInfo?(self.conversation, self.draftTextView.text)
        }, for: .touchUpInside)
        header.addSubview(info)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12), header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12), header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8), header.heightAnchor.constraint(equalToConstant: 52),
            back.leadingAnchor.constraint(equalTo: header.leadingAnchor), back.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            title.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 48), title.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -48), title.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            info.trailingAnchor.constraint(equalTo: header.trailingAnchor), info.centerYAnchor.constraint(equalTo: header.centerYAnchor), info.widthAnchor.constraint(equalToConstant: 40), info.heightAnchor.constraint(equalToConstant: 40),
            infoIcon.centerXAnchor.constraint(equalTo: info.centerXAnchor), infoIcon.centerYAnchor.constraint(equalTo: info.centerYAnchor)
        ])

        historyScroll.translatesAutoresizingMaskIntoConstraints = false
        historyScroll.alwaysBounceVertical = true
        historyScroll.keyboardDismissMode = .interactive
        view.addSubview(historyScroll)
        history.translatesAutoresizingMaskIntoConstraints = false
        history.axis = .vertical; history.spacing = 7
        historyScroll.addSubview(history)
        NSLayoutConstraint.activate([
            historyScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), historyScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor), historyScroll.topAnchor.constraint(equalTo: header.bottomAnchor), historyScroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -62),
            history.leadingAnchor.constraint(equalTo: historyScroll.contentLayoutGuide.leadingAnchor, constant: 20), history.trailingAnchor.constraint(equalTo: historyScroll.contentLayoutGuide.trailingAnchor, constant: -20), history.topAnchor.constraint(equalTo: historyScroll.contentLayoutGuide.topAnchor, constant: 12), history.bottomAnchor.constraint(equalTo: historyScroll.contentLayoutGuide.bottomAnchor, constant: -16), history.widthAnchor.constraint(equalTo: historyScroll.frameLayoutGuide.widthAnchor, constant: -40)
        ])

        let inputBar = UIView()
        inputBar.translatesAutoresizingMaskIntoConstraints = false
        inputBar.backgroundColor = WatchTheme.surface
        inputBar.layer.shadowColor = UIColor.black.withAlphaComponent(0.08).cgColor; inputBar.layer.shadowOpacity = 1; inputBar.layer.shadowRadius = 8; inputBar.layer.shadowOffset = CGSize(width: 0, height: -2)
        view.addSubview(inputBar)
        NSLayoutConstraint.activate([
            inputBar.leadingAnchor.constraint(equalTo: view.leadingAnchor), inputBar.trailingAnchor.constraint(equalTo: view.trailingAnchor), inputBar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor), inputBar.heightAnchor.constraint(equalToConstant: 62)
        ])

        inputModeButton.translatesAutoresizingMaskIntoConstraints = false
        inputModeButton.accessibilityIdentifier = "chat.voiceToggle"
        inputModeButton.accessibilityLabel = NSLocalizedString("watch_chat_switch_voice_input", comment: "")
        inputModeButton.addAction(UIAction { [weak self] _ in self?.toggleInputMode() }, for: .touchUpInside)
        inputBar.addSubview(inputModeButton)

        draftTextView.translatesAutoresizingMaskIntoConstraints = false
        draftTextView.text = draft
        draftTextView.textColor = WatchTheme.primaryText; draftTextView.font = .systemFont(ofSize: 13); draftTextView.backgroundColor = WatchTheme.surfaceStrong; draftTextView.layer.cornerRadius = 12; draftTextView.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 8, right: 10)
        draftTextView.isEditable = true
        inputBar.addSubview(draftTextView)

        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.accessibilityIdentifier = "chat.send"
        sendButton.setTitle(NSLocalizedString("watch_chat_send", comment: ""), for: .normal)
        draftTextView.accessibilityIdentifier = "chat.input"
        sendButton.setTitleColor(WatchTheme.primaryText, for: .normal); sendButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold); sendButton.backgroundColor = WatchTheme.surfaceStrong; sendButton.layer.cornerRadius = 12
        sendButton.addAction(UIAction { [weak self] _ in self?.send() }, for: .touchUpInside)
        inputBar.addSubview(sendButton)

        let emoji = toolButton(.emoji, key: "watch_chat_emoji")
        let more = toolButton(.plus, key: "watch_chat_more")
        more.layer.borderWidth = 1.5; more.layer.borderColor = WatchTheme.blue.cgColor; more.layer.cornerRadius = 14
        inputBar.addSubview(emoji); inputBar.addSubview(more)
        NSLayoutConstraint.activate([
            inputModeButton.leadingAnchor.constraint(equalTo: inputBar.leadingAnchor, constant: 12), inputModeButton.centerYAnchor.constraint(equalTo: inputBar.centerYAnchor), inputModeButton.widthAnchor.constraint(equalToConstant: 36), inputModeButton.heightAnchor.constraint(equalToConstant: 36),
            draftTextView.leadingAnchor.constraint(equalTo: inputModeButton.trailingAnchor, constant: 8), draftTextView.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -4), draftTextView.centerYAnchor.constraint(equalTo: inputBar.centerYAnchor), draftTextView.heightAnchor.constraint(equalToConstant: 40),
            sendButton.trailingAnchor.constraint(equalTo: emoji.leadingAnchor, constant: -4), sendButton.centerYAnchor.constraint(equalTo: inputBar.centerYAnchor), sendButton.widthAnchor.constraint(equalToConstant: 48), sendButton.heightAnchor.constraint(equalToConstant: 40),
            emoji.centerYAnchor.constraint(equalTo: inputBar.centerYAnchor), emoji.widthAnchor.constraint(equalToConstant: 34), emoji.heightAnchor.constraint(equalToConstant: 36),
            more.leadingAnchor.constraint(equalTo: emoji.trailingAnchor, constant: 2), more.trailingAnchor.constraint(equalTo: inputBar.trailingAnchor, constant: -8), more.centerYAnchor.constraint(equalTo: inputBar.centerYAnchor), more.widthAnchor.constraint(equalToConstant: 34), more.heightAnchor.constraint(equalToConstant: 36)
        ])
        updateInputMode()
    }

    private func toolButton(_ kind: WatchIconKind, key: String) -> UIButton {
        let button = UIButton(type: .system); button.translatesAutoresizingMaskIntoConstraints = false; button.accessibilityLabel = NSLocalizedString(key, comment: "")
        let icon = WatchTheme.icon(kind, tint: WatchTheme.secondaryText, size: 19); button.addSubview(icon); NSLayoutConstraint.activate([icon.centerXAnchor.constraint(equalTo: button.centerXAnchor), icon.centerYAnchor.constraint(equalTo: button.centerYAnchor)]); return button
    }

    private func toggleInputMode() {
        textMode.toggle()
        updateInputMode()
    }

    private func updateInputMode() {
        inputModeButton.subviews.forEach { $0.removeFromSuperview() }
        let icon = WatchTheme.icon(textMode ? .voice : .keyboard, tint: textMode ? WatchTheme.blue : WatchTheme.secondaryText, size: 20)
        inputModeButton.addSubview(icon); NSLayoutConstraint.activate([icon.centerXAnchor.constraint(equalTo: inputModeButton.centerXAnchor), icon.centerYAnchor.constraint(equalTo: inputModeButton.centerYAnchor)])
        draftTextView.isHidden = !textMode; sendButton.isHidden = !textMode
        inputModeButton.accessibilityLabel = NSLocalizedString(textMode ? "watch_chat_switch_voice_input" : "watch_chat_switch_text", comment: "")
    }

    private func render(_ messages: [WatchImMessage]) {
        history.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard !messages.isEmpty else {
            let empty = WatchTheme.label("watch_im_chat_empty", size: 14, color: WatchTheme.secondaryText)
            empty.textAlignment = .center; empty.numberOfLines = 0; history.addArrangedSubview(empty)
            scrollHistoryToBottom()
            return
        }
        messages.forEach { message in
            let avatarKey = message.isOutgoing
                ? WatchAvatarResolver.key(for: manager.loggedInUserID ?? "account")
                : WatchAvatarResolver.key(for: message.senderID.isEmpty ? (conversation.userID ?? conversation.key) : message.senderID)
            history.addArrangedSubview(messageRow(message.text, avatarKey: avatarKey, outgoing: message.isOutgoing))
        }
        scrollHistoryToBottom()
    }

    private func scrollHistoryToBottom() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.view.layoutIfNeeded()
            let bottom = max(-self.historyScroll.adjustedContentInset.top,
                             self.historyScroll.contentSize.height - self.historyScroll.bounds.height + self.historyScroll.adjustedContentInset.bottom)
            self.historyScroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
        }
    }

    private func messageRow(_ text: String, avatarKey: String, outgoing: Bool) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        let bubble = ChatBubbleLabel()
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.text = text
        bubble.backgroundColor = outgoing ? WatchTheme.lavender : WatchTheme.surface
        bubble.layer.cornerRadius = 16
        bubble.layer.borderWidth = outgoing ? 0 : 1
        bubble.layer.borderColor = WatchTheme.line.cgColor
        bubble.clipsToBounds = true
        let avatar = WatchTheme.avatar(textKey: avatarKey, color: outgoing ? WatchTheme.blue.withAlphaComponent(0.2) : WatchTheme.mint.withAlphaComponent(0.2), size: 32)
        row.addSubview(bubble)
        if outgoing {
            NSLayoutConstraint.activate([
                bubble.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                bubble.leadingAnchor.constraint(greaterThanOrEqualTo: row.leadingAnchor, constant: 72)
            ])
        } else {
            row.addSubview(avatar)
            NSLayoutConstraint.activate([
                avatar.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                avatar.topAnchor.constraint(equalTo: bubble.topAnchor),
                avatar.widthAnchor.constraint(equalToConstant: 32),
                avatar.heightAnchor.constraint(equalToConstant: 32),
                bubble.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 8),
                bubble.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor)
            ])
        }
        // The row is not attached to historyScroll yet when this method runs.
        // Constraining to the scroll view's frameLayoutGuide at this point raises
        // an exception on a real device when the conversation has history.
        let maxBubbleWidth = bubble.widthAnchor.constraint(lessThanOrEqualTo: row.widthAnchor, multiplier: 0.72)
        maxBubbleWidth.priority = .required
        maxBubbleWidth.isActive = true
        bubble.topAnchor.constraint(equalTo: row.topAnchor).isActive = true
        bubble.bottomAnchor.constraint(equalTo: row.bottomAnchor).isActive = true
        bubble.setContentHuggingPriority(.required, for: .vertical)
        bubble.setContentCompressionResistancePriority(.required, for: .vertical)
        return row
    }

    private func send() {
        guard textMode else { return }
        let text = draftTextView.text ?? ""
        manager.sendText(text, to: conversation) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.draftTextView.text = ""; self.manager.loadMessages(for: self.conversation)
            case .failure(let error):
                WatchLogger.im.error("IM send failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func leave() {
        draft = draftTextView.text ?? ""
        manager.setDraft(draft, for: conversation)
        onBack?(draft)
    }
}

private final class ChatBubbleLabel: UILabel {
    private let insets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)

    override init(frame: CGRect) {
        super.init(frame: frame)
        font = .systemFont(ofSize: 15)
        textColor = WatchTheme.primaryText
        numberOfLines = 0
        lineBreakMode = .byCharWrapping
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override func textRect(forBounds bounds: CGRect, limitedToNumberOfLines numberOfLines: Int) -> CGRect {
        let textRect = super.textRect(forBounds: bounds.inset(by: insets), limitedToNumberOfLines: numberOfLines)
        return textRect.insetBy(dx: -insets.left, dy: -insets.top)
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
}
