import UIKit

final class IncomingCallViewController: UIViewController {
    private weak var store: AppStateStore?
    private let state: CallUIState

    init(store: AppStateStore, state: CallUIState) {
        self.store = store
        self.state = state
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.078, green: 0.141, blue: 0.243, alpha: 1)
        buildView()
        installWatchSystemBottomBar()
    }

    private func buildView() {
        let background = WatchCallIncomingBackgroundView()
        background.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(background)
        NSLayoutConstraint.activate([background.leadingAnchor.constraint(equalTo: view.leadingAnchor), background.trailingAnchor.constraint(equalTo: view.trailingAnchor), background.topAnchor.constraint(equalTo: view.topAnchor), background.bottomAnchor.constraint(equalTo: view.bottomAnchor)])

        let targetName = state.target?.displayName ?? NSLocalizedString("watch_watch_xiaoya", comment: "")
        let targetID = state.target?.avatarID ?? targetName
        let targetKey = WatchAvatarResolver.key(for: targetID)
        let targetColor = WatchTheme.mint.withAlphaComponent(0.22)
        let backgroundImage = UIImageView(image: UIImage(named: targetKey.contains("boy") || targetKey.contains("lele") ? "WatchBoyAvatar" : "WatchGirlAvatar"))
        backgroundImage.translatesAutoresizingMaskIntoConstraints = false
        backgroundImage.contentMode = .scaleAspectFill
        backgroundImage.alpha = 0.48
        view.insertSubview(backgroundImage, aboveSubview: background)
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.alpha = 0.82
        view.insertSubview(blur, aboveSubview: backgroundImage)
        NSLayoutConstraint.activate([
            backgroundImage.leadingAnchor.constraint(equalTo: view.leadingAnchor), backgroundImage.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundImage.topAnchor.constraint(equalTo: view.topAnchor), backgroundImage.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            blur.leadingAnchor.constraint(equalTo: view.leadingAnchor), blur.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            blur.topAnchor.constraint(equalTo: view.topAnchor), blur.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        let navTitle = WatchTheme.label(targetName, size: 17, weight: .semibold, color: WatchTheme.surface)
        let navSubtitle = WatchTheme.label(state.mediaType == .audio ? "watch_call_voice_incoming" : "watch_call_video_incoming", size: 12, color: WatchTheme.callSecondaryText)
        let nav = UIStackView(arrangedSubviews: [navTitle, navSubtitle]); nav.translatesAutoresizingMaskIntoConstraints = false; nav.axis = .vertical; nav.alignment = .center; nav.spacing = 2; view.addSubview(nav)
        NSLayoutConstraint.activate([nav.centerXAnchor.constraint(equalTo: view.centerXAnchor), nav.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4)])

        let avatar = WatchTheme.avatar(textKey: targetKey, color: targetColor, size: 120)
        let message = WatchTheme.label(state.mediaType == .audio ? "watch_call_voice_incoming" : "watch_call_incoming", size: 15, color: WatchTheme.surface)
        message.textAlignment = .center
        let center = UIStackView(arrangedSubviews: [avatar, message]); center.translatesAutoresizingMaskIntoConstraints = false; center.axis = .vertical; center.alignment = .center; center.spacing = 16; view.addSubview(center)
        NSLayoutConstraint.activate([center.centerXAnchor.constraint(equalTo: view.centerXAnchor), center.topAnchor.constraint(equalTo: view.topAnchor, constant: 272)])

        let dock = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark)); dock.translatesAutoresizingMaskIntoConstraints = false; dock.layer.cornerRadius = 32; dock.clipsToBounds = true; dock.backgroundColor = UIColor(red: 0.078, green: 0.141, blue: 0.243, alpha: 0.60); view.addSubview(dock)
        NSLayoutConstraint.activate([dock.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12), dock.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12), dock.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)])
        let actions = UIStackView(); actions.translatesAutoresizingMaskIntoConstraints = false; actions.axis = .horizontal; actions.spacing = 12; actions.distribution = .fillEqually; dock.contentView.addSubview(actions)
        NSLayoutConstraint.activate([actions.leadingAnchor.constraint(equalTo: dock.contentView.leadingAnchor, constant: 16), actions.trailingAnchor.constraint(equalTo: dock.contentView.trailingAnchor, constant: -16), actions.topAnchor.constraint(equalTo: dock.contentView.topAnchor, constant: 16), actions.bottomAnchor.constraint(equalTo: dock.contentView.bottomAnchor, constant: -16), actions.heightAnchor.constraint(equalToConstant: 52)])
        let reject = actionButton(title: "watch_reject", color: WatchTheme.red, identifier: "call.reject") { [weak self] in _ = self?.store?.rejectIncoming(); self?.dismiss(animated: true) }
        let accept = actionButton(title: "watch_answer", color: WatchTheme.mint, identifier: "call.accept") { [weak self] in _ = self?.store?.acceptIncoming() }
        actions.addArrangedSubview(reject); actions.addArrangedSubview(accept)
    }

    private func actionButton(title: String, color: UIColor, identifier: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system); button.translatesAutoresizingMaskIntoConstraints = false; button.setTitle(NSLocalizedString(title, comment: ""), for: .normal); button.setTitleColor(WatchTheme.surface, for: .normal); button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold); button.backgroundColor = color; button.layer.cornerRadius = 26; button.accessibilityIdentifier = identifier; button.addAction(UIAction { _ in action() }, for: .touchUpInside); return button
    }
}

private final class WatchCallIncomingBackgroundView: UIView {
    private let gradient = CAGradientLayer()
    override init(frame: CGRect) { super.init(frame: frame); gradient.colors = [UIColor(red: 0.18, green: 0.31, blue: 0.50, alpha: 1).cgColor, UIColor(red: 0.08, green: 0.14, blue: 0.24, alpha: 1).cgColor]; gradient.startPoint = CGPoint(x: 0.5, y: 0); gradient.endPoint = CGPoint(x: 0.5, y: 1); layer.addSublayer(gradient) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() { super.layoutSubviews(); gradient.frame = bounds }
}
