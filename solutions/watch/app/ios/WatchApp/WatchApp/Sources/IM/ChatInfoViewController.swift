import UIKit

final class ChatInfoViewController: UIViewController {
    private let manager: ImService
    private let conversation: MessageConversation
    var onBack: (() -> Void)?
    var onInvite: ((MessageConversation) -> Void)?

    init(manager: ImService, conversation: MessageConversation) {
        self.manager = manager
        self.conversation = conversation
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = WatchTheme.background
        buildView()
    }

    private func buildView() {
        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)

        let back = WatchTheme.backButton(
            identifier: "chat.info.back",
            label: NSLocalizedString("watch_chat_back", comment: "")
        ) { [weak self] in
            self?.onBack?()
        }
        header.addSubview(back)

        let title = WatchTheme.label(conversation.isGroup ? "watch_group_info_title" : "watch_chat_info_title", size: 20, weight: .bold)
        title.textAlignment = .center
        header.addSubview(title)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            header.heightAnchor.constraint(equalToConstant: 52),
            back.leadingAnchor.constraint(equalTo: header.leadingAnchor), back.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            title.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 48), title.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -48), title.centerYAnchor.constraint(equalTo: header.centerYAnchor)
        ])

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        view.addSubview(scroll)
        let content = UIStackView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .vertical
        content.spacing = 0
        scroll.addSubview(content)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor), scroll.topAnchor.constraint(equalTo: header.bottomAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20), content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20), content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 8), content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24), content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40)
        ])
        if conversation.isGroup { addGroupInfo(to: content) } else { addPersonalInfo(to: content) }
    }

    private func addPersonalInfo(to stack: UIStackView) {
        let name = conversation.displayTitle ?? conversation.userID ?? NSLocalizedString("watch_chat_default_title", comment: "")
        stack.addArrangedSubview(memberStrip([(name, conversation.avatarKey)], inviteAction: { [weak self] in
            guard let self else { return }
            self.onInvite?(self.conversation)
        }))
        stack.addArrangedSubview(settingsBlock())
    }

    private func addGroupInfo(to stack: UIStackView) {
        let memberCard = memberStrip([], inviteAction: { [weak self] in
            guard let self else { return }
            self.onInvite?(self.conversation)
        })
        stack.addArrangedSubview(memberCard)
        manager.loadGroupMembers(for: conversation) { [weak memberCard] result in
            let members = (try? result.get()) ?? []
            DispatchQueue.main.async {
                guard let memberCard else { return }
                self.replaceMembers(in: memberCard, members: members.map { ($0.displayName, $0.avatarKey) }, inviteAction: { [weak self] in
                    guard let self else { return }
                    self.onInvite?(self.conversation)
                })
            }
        }
        let profile = UIStackView()
        profile.translatesAutoresizingMaskIntoConstraints = false
        profile.axis = .vertical
        profile.spacing = 0
        profile.backgroundColor = WatchTheme.surface
        profile.layer.cornerRadius = 18
        profile.clipsToBounds = true
        profile.addArrangedSubview(detailRow("watch_chat_group_name", valueKey: conversation.displayTitle ?? NSLocalizedString("watch_chat_default_group_title", comment: "")))
        profile.addArrangedSubview(detailRow("watch_chat_group_notice", valueKey: "watch_chat_not_set"))
        profile.addArrangedSubview(detailRow("watch_chat_my_nickname", valueKey: "watch_account_name"))
        profile.layoutMargins = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        profile.isLayoutMarginsRelativeArrangement = true
        stack.addArrangedSubview(profile)
        stack.setCustomSpacing(14, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(settingsBlock())
    }

    private func memberStrip(_ members: [(String, String)], inviteAction: @escaping () -> Void) -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = WatchTheme.surface
        card.layer.cornerRadius = 18
        card.heightAnchor.constraint(equalToConstant: 118).isActive = true
        let row = UIStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 2
        card.addSubview(row)
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14), row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14), row.centerYAnchor.constraint(equalTo: card.centerYAnchor)])
        members.forEach { row.addArrangedSubview(memberItem(titleKey: $0.0, avatarKey: $0.1)) }
        row.addArrangedSubview(memberAddButton(inviteAction: inviteAction))
        row.addArrangedSubview(UIView())
        return card
    }

    private func memberItem(titleKey: String, avatarKey: String) -> UIView {
        let item = UIStackView(arrangedSubviews: [WatchTheme.avatar(textKey: avatarKey, color: WatchTheme.lavender, size: 48), WatchTheme.label(titleKey, size: 11, color: WatchTheme.secondaryText)])
        item.axis = .vertical
        item.alignment = .center
        item.spacing = 5
        item.widthAnchor.constraint(equalToConstant: 56).isActive = true
        return item
    }

    private func replaceMembers(in card: UIView, members: [(String, String)], inviteAction: @escaping () -> Void) {
        card.subviews.forEach { $0.removeFromSuperview() }
        let row = UIStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 2
        card.addSubview(row)
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14), row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14), row.centerYAnchor.constraint(equalTo: card.centerYAnchor)])
        members.forEach { row.addArrangedSubview(memberItem(titleKey: $0.0, avatarKey: $0.1)) }
        row.addArrangedSubview(memberAddButton(inviteAction: inviteAction))
        row.addArrangedSubview(UIView())
    }

    private func memberAddButton(inviteAction: @escaping () -> Void) -> UIView {
        let slot = UIView()
        slot.translatesAutoresizingMaskIntoConstraints = false
        slot.setContentHuggingPriority(.required, for: .horizontal)
        slot.setContentCompressionResistancePriority(.required, for: .horizontal)
        slot.widthAnchor.constraint(equalToConstant: 56).isActive = true
        slot.heightAnchor.constraint(equalToConstant: 56).isActive = true

        let add = WatchDashedBorderButton()
        add.translatesAutoresizingMaskIntoConstraints = false
        add.accessibilityIdentifier = "chat.member.add"
        add.accessibilityLabel = NSLocalizedString("watch_chat_invite_member", comment: "")
        let icon = WatchTheme.icon(.plus, tint: WatchTheme.secondaryText, size: 18)
        add.addSubview(icon)
        slot.addSubview(add)
        NSLayoutConstraint.activate([
            add.leadingAnchor.constraint(equalTo: slot.leadingAnchor),
            add.trailingAnchor.constraint(equalTo: slot.trailingAnchor),
            add.topAnchor.constraint(equalTo: slot.topAnchor),
            add.bottomAnchor.constraint(equalTo: slot.bottomAnchor),
            icon.centerXAnchor.constraint(equalTo: add.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: add.centerYAnchor)
        ])
        add.addAction(UIAction { _ in inviteAction() }, for: .touchUpInside)
        return slot
    }

    private func settingsBlock() -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 0
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addArrangedSubview(settingCard())
        container.addArrangedSubview(actionRow("watch_chat_background", color: WatchTheme.primaryText, showsChevron: true))
        container.setCustomSpacing(14, after: container.arrangedSubviews[0])
        container.addArrangedSubview(actionRow("watch_chat_clear", color: WatchTheme.red, showsChevron: false))
        container.setCustomSpacing(14, after: container.arrangedSubviews[1])
        return container
    }

    private func settingCard() -> UIView {
        let currentConversation = conversation
        let card = UIStackView()
        card.axis = .vertical
        card.spacing = 0
        card.backgroundColor = WatchTheme.surface
        card.layer.cornerRadius = 18
        card.clipsToBounds = true
        card.layoutMargins = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        card.isLayoutMarginsRelativeArrangement = true
        card.addArrangedSubview(settingRow("watch_chat_do_not_disturb", initialValue: conversation.isMuted) { [weak self] value, toggle in
            self?.manager.setMuted(value, for: self?.conversation ?? currentConversation) { [weak self] result in
                if case .failure = result { toggle.setOn(!value, animated: true); self?.showSdkUnavailable() }
            }
        })
        let line = UIView(); line.backgroundColor = WatchTheme.line; line.heightAnchor.constraint(equalToConstant: 1).isActive = true; card.addArrangedSubview(line)
        card.addArrangedSubview(settingRow("watch_chat_pin", initialValue: conversation.isPinned) { [weak self] value, toggle in
            self?.manager.setPinned(value, for: self?.conversation ?? currentConversation) { [weak self] result in
                if case .failure = result { toggle.setOn(!value, animated: true); self?.showSdkUnavailable() }
            }
        })
        return card
    }

    private func settingRow(_ key: String, initialValue: Bool, changed: @escaping (Bool, UISwitch) -> Void) -> UIView {
        let row = UIView(); row.translatesAutoresizingMaskIntoConstraints = false; row.heightAnchor.constraint(equalToConstant: 58).isActive = true
        let label = WatchTheme.label(key, size: 14)
        let toggle = UISwitch(); toggle.translatesAutoresizingMaskIntoConstraints = false; toggle.onTintColor = WatchTheme.blue; toggle.isOn = initialValue; toggle.accessibilityLabel = NSLocalizedString(key, comment: "")
        toggle.addAction(UIAction { action in
            guard let sender = action.sender as? UISwitch else { return }
            changed(sender.isOn, sender)
        }, for: .valueChanged)
        row.addSubview(label); row.addSubview(toggle)
        NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16), label.centerYAnchor.constraint(equalTo: row.centerYAnchor), toggle.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -12), toggle.centerYAnchor.constraint(equalTo: row.centerYAnchor)])
        return row
    }

    private func detailRow(_ titleKey: String, valueKey: String) -> UIView {
        let row = UIView(); row.translatesAutoresizingMaskIntoConstraints = false; row.heightAnchor.constraint(equalToConstant: 52).isActive = true
        let title = WatchTheme.label(titleKey, size: 14)
        let value = WatchTheme.label(valueKey, size: 14, color: WatchTheme.secondaryText)
        let chevronSlot = WatchTheme.trailingChevronSlot()
        row.addSubview(title); row.addSubview(value); row.addSubview(chevronSlot)
        NSLayoutConstraint.activate([title.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16), title.centerYAnchor.constraint(equalTo: row.centerYAnchor), value.trailingAnchor.constraint(equalTo: chevronSlot.leadingAnchor, constant: -8), value.centerYAnchor.constraint(equalTo: row.centerYAnchor), chevronSlot.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14), chevronSlot.centerYAnchor.constraint(equalTo: row.centerYAnchor)])
        return row
    }

    private func actionRow(_ key: String, color: UIColor, showsChevron: Bool) -> UIView {
        let currentConversation = conversation
        let row = UIButton(type: .system); row.translatesAutoresizingMaskIntoConstraints = false; row.heightAnchor.constraint(equalToConstant: 48).isActive = true; row.backgroundColor = WatchTheme.surface; row.layer.cornerRadius = 16
        row.accessibilityLabel = NSLocalizedString(key, comment: "")
        let label = WatchTheme.label(key, size: 14, color: color)
        row.addSubview(label)
        if showsChevron {
            let chevronSlot = WatchTheme.trailingChevronSlot(); row.addSubview(chevronSlot)
            NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16), label.centerYAnchor.constraint(equalTo: row.centerYAnchor), chevronSlot.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14), chevronSlot.centerYAnchor.constraint(equalTo: row.centerYAnchor)])
        } else {
            label.textAlignment = .center
            NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16), label.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16), label.centerYAnchor.constraint(equalTo: row.centerYAnchor)])
            row.addAction(UIAction { [weak self] _ in
                self?.manager.clearHistory(for: self?.conversation ?? currentConversation) { [weak self] result in
                    if case .failure = result { self?.showSdkUnavailable() }
                }
            }, for: .touchUpInside)
        }
        return row
    }

    private func showSdkUnavailable() {
        let alert = UIAlertController(title: NSLocalizedString("watch_im_settings_failed_title", comment: ""), message: NSLocalizedString("watch_im_simulator_message", comment: ""), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("watch_common_ok", comment: ""), style: .default))
        present(alert, animated: true)
    }
}
