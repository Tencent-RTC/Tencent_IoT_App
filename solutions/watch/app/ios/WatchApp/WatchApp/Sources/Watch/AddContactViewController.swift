import UIKit

final class AddContactViewController: UIViewController {
    var onBack: (() -> Void)?
    var onAddWatch: (() -> Void)?
    var onCreateGroup: (() -> Void)?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = WatchTheme.background
        buildView()
    }

    private func buildView() {
        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.backgroundColor = WatchTheme.surface
        view.addSubview(header)

        let back = WatchTheme.backButton(
            identifier: "add.back",
            label: NSLocalizedString("watch_add_back", comment: "")
        ) { [weak self] in
            self?.onBack?()
        }
        let title = WatchTheme.label("watch_add_page_title", size: 20, weight: .bold)
        title.textAlignment = .center
        header.addSubview(back)
        header.addSubview(title)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor), header.trailingAnchor.constraint(equalTo: view.trailingAnchor), header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8), header.heightAnchor.constraint(equalToConstant: 52),
            back.leadingAnchor.constraint(equalTo: header.leadingAnchor), back.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            title.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 48), title.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -48), title.centerYAnchor.constraint(equalTo: header.centerYAnchor)
        ])

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor), scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor), scrollView.topAnchor.constraint(equalTo: header.bottomAnchor), scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 0
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16), contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16), contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 18), contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -38), contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32)
        ])

        contentStack.addArrangedSubview(makeSection(titleKey: "watch_add_contact_section", rows: [
            makeRow(titleKey: "watch_add_member", descriptionKey: "watch_add_member_desc", icon: .link, iconColor: UIColor(red: 0.949, green: 0.459, blue: 0.122, alpha: 1), backgroundColor: UIColor(red: 1, green: 0.941, blue: 0.89, alpha: 1)),
            makeRow(titleKey: "watch_add_watch_friend", descriptionKey: "watch_add_watch_friend_desc", icon: .watch, iconColor: UIColor(red: 0.122, green: 0.549, blue: 0.941, alpha: 1), backgroundColor: UIColor(red: 0.89, green: 0.949, blue: 1, alpha: 1))
        ], divided: true))
        contentStack.setCustomSpacing(22, after: contentStack.arrangedSubviews.last!)
        contentStack.addArrangedSubview(makeSection(titleKey: "watch_add_group_section", rows: [
            makeRow(titleKey: "watch_add_group", descriptionKey: "watch_add_group_desc", icon: .users, iconColor: UIColor(red: 0.055, green: 0.604, blue: 0.439, alpha: 1), backgroundColor: UIColor(red: 0.882, green: 0.973, blue: 0.941, alpha: 1), action: { [weak self] in self?.onCreateGroup?() })
        ], divided: false))
        contentStack.setCustomSpacing(22, after: contentStack.arrangedSubviews.last!)
        contentStack.addArrangedSubview(makeSection(titleKey: "watch_add_watch_section", rows: [
            makeRow(titleKey: "watch_add_watch", descriptionKey: "watch_add_watch_desc", icon: .plus, iconColor: UIColor(red: 0.592, green: 0.663, blue: 0.761, alpha: 1), backgroundColor: .clear, dashed: true, action: { [weak self] in
                self?.onAddWatch?()
            })
        ], divided: false))
    }

    private func makeSection(titleKey: String, rows: [UIView], divided: Bool) -> UIView {
        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        let title = WatchTheme.label(titleKey, size: 14, weight: .semibold, color: WatchTheme.addSectionText)
        title.translatesAutoresizingMaskIntoConstraints = false
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = WatchTheme.surface
        card.layer.cornerRadius = 20
        card.clipsToBounds = true
        wrapper.addSubview(title); wrapper.addSubview(card)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 6), title.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor), title.topAnchor.constraint(equalTo: wrapper.topAnchor), title.heightAnchor.constraint(equalToConstant: 20),
            card.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor), card.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor), card.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10), card.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor)
        ])
        let stack = UIStackView(arrangedSubviews: rows)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 0
        card.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: card.leadingAnchor), stack.trailingAnchor.constraint(equalTo: card.trailingAnchor), stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 4), stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -4)])
        if divided, rows.count > 1 {
            let divider = UIView(); divider.translatesAutoresizingMaskIntoConstraints = false; divider.backgroundColor = WatchTheme.addDivider
            card.addSubview(divider)
            NSLayoutConstraint.activate([divider.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 67), divider.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14), divider.centerYAnchor.constraint(equalTo: card.centerYAnchor), divider.heightAnchor.constraint(equalToConstant: 1)])
        }
        return wrapper
    }

    private func makeRow(titleKey: String, descriptionKey: String, icon: WatchIconKind, iconColor: UIColor, backgroundColor: UIColor, dashed: Bool = false, action: (() -> Void)? = nil) -> UIView {
        let row = WatchActionControl()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 64).isActive = true
        let rowIdentifier = "add.\(titleKey.replacingOccurrences(of: "watch_add_", with: ""))"
        row.isAccessibilityElement = action == nil
        row.accessibilityIdentifier = action == nil ? rowIdentifier : nil
        row.accessibilityLabel = NSLocalizedString(titleKey, comment: "")
        row.activationHandler = action
        if action != nil {
            row.accessibilityTraits = .button
        }
        let iconBackground: UIView = dashed ? DashedIconBackground() : UIView(); iconBackground.translatesAutoresizingMaskIntoConstraints = false; iconBackground.backgroundColor = backgroundColor; iconBackground.layer.cornerRadius = 12
        let iconView = WatchTheme.icon(icon, tint: iconColor, size: 22); iconBackground.addSubview(iconView)
        let copy = UIStackView(arrangedSubviews: [WatchTheme.label(titleKey, size: 16, weight: .regular), WatchTheme.label(descriptionKey, size: 13, color: WatchTheme.secondaryText)]); copy.translatesAutoresizingMaskIntoConstraints = false; copy.axis = .vertical; copy.spacing = 3
        let chevronSlot = WatchTheme.trailingChevronSlot(); row.addSubview(iconBackground); row.addSubview(copy); row.addSubview(chevronSlot)
        iconBackground.isUserInteractionEnabled = false
        copy.isUserInteractionEnabled = false
        chevronSlot.isUserInteractionEnabled = false
        NSLayoutConstraint.activate([
            iconBackground.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14), iconBackground.centerYAnchor.constraint(equalTo: row.centerYAnchor), iconBackground.widthAnchor.constraint(equalToConstant: 40), iconBackground.heightAnchor.constraint(equalToConstant: 40), iconView.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor), iconView.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor),
            copy.leadingAnchor.constraint(equalTo: iconBackground.trailingAnchor, constant: 13), copy.centerYAnchor.constraint(equalTo: row.centerYAnchor), copy.trailingAnchor.constraint(equalTo: chevronSlot.leadingAnchor, constant: -8), chevronSlot.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14), chevronSlot.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        if let action {
            let hitButton = AddContactRowButton(action: action)
            hitButton.translatesAutoresizingMaskIntoConstraints = false
            hitButton.backgroundColor = .clear
            hitButton.accessibilityIdentifier = rowIdentifier
            hitButton.accessibilityLabel = row.accessibilityLabel
            hitButton.accessibilityTraits = .button
            row.addSubview(hitButton)
            NSLayoutConstraint.activate([
                hitButton.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                hitButton.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                hitButton.topAnchor.constraint(equalTo: row.topAnchor),
                hitButton.bottomAnchor.constraint(equalTo: row.bottomAnchor)
            ])
        }
        return row
    }
}

private final class AddContactRowButton: UIButton {
    private let handler: () -> Void

    init(action: @escaping () -> Void) {
        handler = action
        super.init(frame: .zero)
        addTarget(self, action: #selector(activate), for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func activate() {
        handler()
    }
}

private final class DashedIconBackground: UIView {
    private let border = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        border.strokeColor = UIColor(red: 0.812, green: 0.847, blue: 0.902, alpha: 1).cgColor
        border.fillColor = UIColor.clear.cgColor
        border.lineDashPattern = [3, 2]
        border.lineWidth = 1
        layer.addSublayer(border)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() { super.layoutSubviews(); border.frame = bounds; border.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 12).cgPath }
}
