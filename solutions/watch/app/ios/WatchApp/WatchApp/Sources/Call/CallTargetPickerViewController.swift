import UIKit

final class CallTargetPickerViewController: UIViewController {
    private let store: AppStateStore
    fileprivate enum Target: Hashable {
        case bound(String)
    }

    private var selectedTarget: Target?
    private var targetViews: [Target: CallTargetItemView] = [:]
    private weak var dimView: UIControl?
    private weak var sheetView: UIView?
    private var didAnimateIn = false
    private var isDismissing = false

    init(store: AppStateStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        buildView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        view.layoutIfNeeded()
        guard !didAnimateIn, let sheetView else { return }
        sheetView.transform = CGAffineTransform(translationX: 0, y: sheetView.bounds.height)
        dimView?.alpha = 0
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didAnimateIn, let sheetView else { return }
        didAnimateIn = true
        UIView.animate(withDuration: 0.32, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            sheetView.transform = .identity
            self.dimView?.alpha = 1
        }
    }

    private func buildView() {
        let dim = UIControl()
        dim.translatesAutoresizingMaskIntoConstraints = false
        dim.backgroundColor = UIColor(red: 0.059, green: 0.09, blue: 0.188, alpha: 0.42)
        dim.addAction(UIAction { [weak self] _ in self?.dismissPicker() }, for: .touchUpInside)
        view.addSubview(dim)
        dimView = dim
        NSLayoutConstraint.activate([
            dim.leadingAnchor.constraint(equalTo: view.leadingAnchor), dim.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dim.topAnchor.constraint(equalTo: view.topAnchor), dim.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let sheet = UIView()
        sheet.translatesAutoresizingMaskIntoConstraints = false
        sheet.backgroundColor = WatchTheme.surface
        sheet.layer.cornerRadius = 24
        sheet.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        sheet.clipsToBounds = true
        view.addSubview(sheet)
        sheetView = sheet
        NSLayoutConstraint.activate([
            sheet.leadingAnchor.constraint(equalTo: view.leadingAnchor), sheet.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sheet.bottomAnchor.constraint(equalTo: view.bottomAnchor), sheet.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 170)
        ])

        let content = UIStackView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .vertical
        content.spacing = 4
        sheet.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: sheet.leadingAnchor, constant: 20), content.trailingAnchor.constraint(equalTo: sheet.trailingAnchor, constant: -20),
            content.topAnchor.constraint(equalTo: sheet.topAnchor, constant: 16), content.bottomAnchor.constraint(equalTo: sheet.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])

        let header = UIStackView()
        header.axis = .horizontal
        header.alignment = .center
        let title = WatchTheme.label("watch_call_choose_target", size: 13, color: WatchTheme.secondaryText)
        let cancel = UIButton(type: .system)
        cancel.translatesAutoresizingMaskIntoConstraints = false
        cancel.accessibilityIdentifier = "call.cancel"
        cancel.setTitle(NSLocalizedString("watch_cancel", comment: ""), for: .normal)
        cancel.setTitleColor(WatchTheme.secondaryText, for: .normal)
        cancel.titleLabel?.font = .systemFont(ofSize: 14)
        cancel.addAction(UIAction { [weak self] _ in self?.dismissPicker() }, for: .touchUpInside)
        header.addArrangedSubview(title); header.addArrangedSubview(UIView()); header.addArrangedSubview(cancel)
        cancel.widthAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        cancel.heightAnchor.constraint(equalToConstant: 44).isActive = true
        content.addArrangedSubview(header)

        let targetScroll = UIScrollView()
        targetScroll.translatesAutoresizingMaskIntoConstraints = false
        targetScroll.showsHorizontalScrollIndicator = false
        targetScroll.alwaysBounceHorizontal = false
        let targets = UIStackView()
        targets.translatesAutoresizingMaskIntoConstraints = false
        targets.axis = .horizontal
        targets.alignment = .top
        targets.spacing = 12
        targetScroll.addSubview(targets)
        NSLayoutConstraint.activate([
            targets.leadingAnchor.constraint(equalTo: targetScroll.contentLayoutGuide.leadingAnchor),
            targets.trailingAnchor.constraint(equalTo: targetScroll.contentLayoutGuide.trailingAnchor),
            targets.topAnchor.constraint(equalTo: targetScroll.contentLayoutGuide.topAnchor),
            targets.bottomAnchor.constraint(equalTo: targetScroll.contentLayoutGuide.bottomAnchor),
            targets.heightAnchor.constraint(equalTo: targetScroll.frameLayoutGuide.heightAnchor)
        ])
        targetScroll.heightAnchor.constraint(equalToConstant: 92).isActive = true
        let boundWatches = WatchBindingStore.all(userID: store.imManager.loggedInUserID)
        if !boundWatches.isEmpty {
            for boundWatch in boundWatches {
                let target = Target.bound(boundWatch.deviceName)
                let item = CallTargetItemView(target: target, title: boundWatch.deviceName, color: WatchTheme.surfaceStrong, iconKind: .device, enabled: true)
                item.widthAnchor.constraint(equalToConstant: 72).isActive = true
                item.accessibilityIdentifier = "call.target.\(boundWatch.deviceName)"
                item.onSelect = { [weak self] in self?.select(target) }
                targetViews[target] = item
                targets.addArrangedSubview(item)
            }
        } else {
            let empty = WatchTheme.label("watch_call_no_bound_watch", size: 13, color: WatchTheme.secondaryText)
            empty.textAlignment = .center
            targets.addArrangedSubview(empty)
        }
        content.addArrangedSubview(targetScroll)

        let actions = UIStackView()
        actions.axis = .horizontal; actions.alignment = .top; actions.distribution = .fillEqually; actions.spacing = 12
        actions.addArrangedSubview(actionItem(key: "watch_call_video", icon: .video, color: WatchTheme.blue, voiceMode: false, enabled: !boundWatches.isEmpty))
        actions.addArrangedSubview(actionItem(key: "watch_call_voice", icon: .phone, color: WatchTheme.mint, voiceMode: true, enabled: !boundWatches.isEmpty))
        content.addArrangedSubview(actions)
        if let first = boundWatches.first { select(.bound(first.deviceName)) }
    }

    private func select(_ target: Target) {
        selectedTarget = target
        targetViews.forEach { $0.value.setSelected($0.key == target) }
    }

    private func actionItem(key: String, icon: WatchIconKind, color: UIColor, voiceMode: Bool, enabled: Bool) -> UIView {
        let stack = UIStackView(); stack.axis = .vertical; stack.alignment = .center; stack.spacing = 4
        let button = UIControl(); button.translatesAutoresizingMaskIntoConstraints = false; button.accessibilityIdentifier = voiceMode ? "call.voice" : "call.video"; button.backgroundColor = color; button.layer.cornerRadius = 18
        button.isEnabled = enabled
        button.alpha = enabled ? 1 : 0.42
        let iconView = WatchTheme.icon(icon, tint: WatchTheme.surface, size: 24); button.addSubview(iconView)
        NSLayoutConstraint.activate([button.widthAnchor.constraint(equalToConstant: 60), button.heightAnchor.constraint(equalToConstant: 44), iconView.centerXAnchor.constraint(equalTo: button.centerXAnchor), iconView.centerYAnchor.constraint(equalTo: button.centerYAnchor)])
        button.addAction(UIAction { [weak self] _ in self?.startCall(voiceMode: voiceMode) }, for: .touchUpInside)
        stack.addArrangedSubview(button); stack.addArrangedSubview(WatchTheme.label(key, size: 11, color: WatchTheme.primaryText))
        return stack
    }

    private func startCall(voiceMode: Bool) {
        guard case let .bound(deviceName)? = selectedTarget,
              let bound = WatchBindingStore.all(userID: store.imManager.loggedInUserID).first(where: { $0.deviceName == deviceName }) else { return }
        let displayName = bound.deviceName
        let avatarKey = WatchAvatarResolver.key(for: bound.deviceName)
        let avatarColor = WatchTheme.surfaceStrong
        let target = CallTarget(productId: bound.productId, deviceName: bound.deviceName, displayName: displayName, avatarID: bound.deviceName)
        guard store.startCall(target: target, mediaType: voiceMode ? .audio : .video) else { return }
        let presenter = presentingViewController
        let call = OutgoingCallViewController(store: store, displayName: displayName, avatarKey: avatarKey, avatarColor: avatarColor, voiceMode: voiceMode)
        call.modalPresentationStyle = .fullScreen
        dismiss(animated: true) {
            presenter?.present(call, animated: true)
        }
    }

    private func dismissPicker() {
        guard !isDismissing else { return }
        isDismissing = true
        guard let sheetView else {
            dismiss(animated: true)
            return
        }
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]) {
            sheetView.transform = CGAffineTransform(translationX: 0, y: sheetView.bounds.height)
            self.dimView?.alpha = 0
        } completion: { [weak self] _ in
            self?.dismiss(animated: false)
        }
    }
}

private final class CallTargetItemView: UIButton {
    private let target: CallTargetPickerViewController.Target
    private let avatarContainer = UIView()
    private let check = WatchIconView(.check, tint: WatchTheme.surface)
    private let title: UILabel
    private let iconKind: WatchIconKind
    private let color: UIColor
    var onSelect: (() -> Void)?

    fileprivate init(target: CallTargetPickerViewController.Target, title: String, color: UIColor, iconKind: WatchIconKind, enabled: Bool) {
        self.target = target; self.title = WatchTheme.label(title, size: 11); self.iconKind = iconKind; self.color = color
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        alpha = enabled ? 1 : 0.48
        isUserInteractionEnabled = enabled
        isExclusiveTouch = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(didTap))
        addGestureRecognizer(tap)
        buildView()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildView() {
        let stack = UIStackView(); stack.translatesAutoresizingMaskIntoConstraints = false; stack.axis = .vertical; stack.alignment = .center; stack.spacing = 4
        addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor), stack.topAnchor.constraint(equalTo: topAnchor, constant: 2), stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)])
        avatarContainer.translatesAutoresizingMaskIntoConstraints = false; avatarContainer.layer.cornerRadius = 28; avatarContainer.backgroundColor = color
        check.backgroundColor = WatchTheme.blue; check.layer.cornerRadius = 9
        stack.addArrangedSubview(avatarContainer); avatarContainer.widthAnchor.constraint(equalToConstant: 56).isActive = true; avatarContainer.heightAnchor.constraint(equalToConstant: 56).isActive = true

        let deviceName: String = {
            if case let .bound(name) = target { return name }
            return title.text ?? "watch"
        }()
        let device = WatchTheme.avatar(textKey: WatchAvatarResolver.key(for: deviceName), color: WatchTheme.mint.withAlphaComponent(0.22), size: 48); avatarContainer.addSubview(device); NSLayoutConstraint.activate([device.centerXAnchor.constraint(equalTo: avatarContainer.centerXAnchor), device.centerYAnchor.constraint(equalTo: avatarContainer.centerYAnchor)])
        avatarContainer.addSubview(check); NSLayoutConstraint.activate([check.widthAnchor.constraint(equalToConstant: 18), check.heightAnchor.constraint(equalToConstant: 18), check.trailingAnchor.constraint(equalTo: avatarContainer.trailingAnchor), check.bottomAnchor.constraint(equalTo: avatarContainer.bottomAnchor)])
        stack.addArrangedSubview(title)
    }

    func setSelected(_ selected: Bool) {
        avatarContainer.layer.borderWidth = selected ? 2 : 0
        avatarContainer.layer.borderColor = WatchTheme.blue.cgColor
        title.textColor = selected ? WatchTheme.blue : WatchTheme.primaryText
        check.isHidden = !selected
        accessibilityValue = selected ? NSLocalizedString("watch_selected", comment: "") : nil
        accessibilityTraits = selected ? [.button, .selected] : [.button]
    }

    @objc private func didTap() {
        onSelect?()
    }

    override func accessibilityActivate() -> Bool {
        sendActions(for: .touchUpInside)
        return true
    }
}
