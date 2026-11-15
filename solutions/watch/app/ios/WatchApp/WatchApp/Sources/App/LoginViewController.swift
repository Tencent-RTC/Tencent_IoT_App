import UIKit

final class LoginViewController: UIViewController {
    var onLogin: ((String, String, String) -> Void)?
    private let scrollView = UIScrollView(); private let contentStack = UIStackView(); private let roomField = UITextField(); private let appIDField = UITextField(); private let secretField = UITextField(); private let loginButton = WatchTheme.button("watch_login", filled: true); private let statusLabel = UILabel()

    override func viewDidLoad() { super.viewDidLoad(); view.backgroundColor = WatchTheme.background; buildView(); NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged), name: UIResponder.keyboardWillChangeFrameNotification, object: nil) }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func buildView() {
        roomField.accessibilityIdentifier = "login.room"
        appIDField.accessibilityIdentifier = "login.appID"
        secretField.accessibilityIdentifier = "login.secret"
        loginButton.accessibilityIdentifier = "login.submit"
        scrollView.translatesAutoresizingMaskIntoConstraints = false; scrollView.alwaysBounceVertical = true; scrollView.keyboardDismissMode = .interactive; view.addSubview(scrollView); NSLayoutConstraint.activate([scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor), scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor), scrollView.topAnchor.constraint(equalTo: view.topAnchor), scrollView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)])
        contentStack.translatesAutoresizingMaskIntoConstraints = false; contentStack.axis = .vertical; contentStack.spacing = 0; scrollView.addSubview(contentStack); NSLayoutConstraint.activate([contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 24), contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -24), contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20), contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24), contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -48)])

        let brand = UIStackView(); brand.axis = .horizontal; brand.alignment = .center; brand.spacing = 10; let logo = WatchTheme.gradientCard(); logo.layer.cornerRadius = 14; logo.addSubview(WatchTheme.icon(.video, tint: WatchTheme.surface, size: 22)); NSLayoutConstraint.activate([logo.widthAnchor.constraint(equalToConstant: 40), logo.heightAnchor.constraint(equalToConstant: 40), logo.subviews[0].centerXAnchor.constraint(equalTo: logo.centerXAnchor), logo.subviews[0].centerYAnchor.constraint(equalTo: logo.centerYAnchor)]); brand.addArrangedSubview(logo); brand.addArrangedSubview(WatchTheme.label("watch_brand", size: 17, weight: .bold)); contentStack.addArrangedSubview(brand)
        let title = WatchTheme.label("watch_tagline", size: 26, weight: .bold); contentStack.setCustomSpacing(24, after: brand); contentStack.addArrangedSubview(title); contentStack.setCustomSpacing(6, after: title); contentStack.addArrangedSubview(WatchTheme.label("watch_login_subtitle", size: 13, color: WatchTheme.secondaryText))

        let form = WatchTheme.card(); let formStack = UIStackView(); formStack.translatesAutoresizingMaskIntoConstraints = false; formStack.axis = .vertical; formStack.spacing = 8; form.addSubview(formStack); NSLayoutConstraint.activate([formStack.leadingAnchor.constraint(equalTo: form.leadingAnchor, constant: 16), formStack.trailingAnchor.constraint(equalTo: form.trailingAnchor, constant: -16), formStack.topAnchor.constraint(equalTo: form.topAnchor, constant: 16), formStack.bottomAnchor.constraint(equalTo: form.bottomAnchor, constant: -16)]); contentStack.setCustomSpacing(24, after: contentStack.arrangedSubviews.last!); contentStack.addArrangedSubview(form)
        addField(label: "watch_room_label", placeholder: "watch_room_hint", field: roomField, keyboard: .numberPad, icon: .home, target: formStack); roomField.text = WatchSdkConfig.TRTC_ROOM_ID
        addField(label: "watch_sdk_app_id_label", placeholder: "watch_sdk_app_id_hint", field: appIDField, keyboard: .numberPad, icon: .grid, target: formStack); appIDField.text = String(WatchSdkConfig.TRTC_SDK_APP_ID)
        addField(label: "watch_sdk_secret_label", placeholder: "watch_sdk_secret_hint", field: secretField, keyboard: .default, icon: .lock, target: formStack); secretField.isSecureTextEntry = true; secretField.text = WatchSdkConfig.TRTC_SECRET_KEY

        loginButton.addTarget(self, action: #selector(submitButtonTapped), for: .touchUpInside); loginButton.heightAnchor.constraint(equalToConstant: 48).isActive = true; contentStack.setCustomSpacing(14, after: form); contentStack.addArrangedSubview(loginButton)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false; statusLabel.font = .systemFont(ofSize: 12); statusLabel.textAlignment = .center; statusLabel.numberOfLines = 0; statusLabel.textColor = WatchTheme.red; statusLabel.isHidden = true; contentStack.setCustomSpacing(8, after: loginButton); contentStack.addArrangedSubview(statusLabel)
        let other = WatchTheme.label("watch_other_login", size: 12, color: WatchTheme.tertiaryText); other.textAlignment = .center; contentStack.setCustomSpacing(24, after: statusLabel); contentStack.addArrangedSubview(other)
        let options = UIStackView(); options.axis = .horizontal; options.alignment = .top; options.distribution = .fillEqually; options.spacing = 16; let wechat = imageOption(assetName: "WatchWeChat", title: "watch_wechat_login"); let phone = option(kind: .device, title: "watch_phone_login"); options.addArrangedSubview(wechat); options.addArrangedSubview(phone); contentStack.setCustomSpacing(10, after: other); contentStack.addArrangedSubview(options)
    }

    private func addField(label: String, placeholder: String, field: UITextField, keyboard: UIKeyboardType, icon: WatchIconKind, target: UIStackView) {
        let title = WatchTheme.label(label, size: 12, weight: .semibold); target.addArrangedSubview(title); field.translatesAutoresizingMaskIntoConstraints = false; field.placeholder = NSLocalizedString(placeholder, comment: ""); field.font = .systemFont(ofSize: 14); field.textColor = WatchTheme.primaryText; field.tintColor = WatchTheme.blue; field.backgroundColor = WatchTheme.surfaceStrong; field.layer.cornerRadius = 12; field.layer.borderWidth = 1; field.layer.borderColor = WatchTheme.line.cgColor; field.leftView = WatchTheme.icon(icon, tint: WatchTheme.secondaryText, size: 20); field.leftViewMode = .always; field.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1)); field.rightViewMode = .always; field.keyboardType = keyboard; field.heightAnchor.constraint(equalToConstant: 44).isActive = true; target.addArrangedSubview(field)
    }

    private func option(kind: WatchIconKind, title: String) -> UIView { let button = UIButton(type: .system); button.translatesAutoresizingMaskIntoConstraints = false; button.backgroundColor = .clear; button.addSubview(WatchTheme.icon(kind, tint: kind == .group ? WatchTheme.mint : WatchTheme.blue, size: 24)); button.addSubview(WatchTheme.label(title, size: 11, color: WatchTheme.secondaryText)); let icon = button.subviews[0]; let label = button.subviews[1]; NSLayoutConstraint.activate([button.heightAnchor.constraint(equalToConstant: 52), icon.centerXAnchor.constraint(equalTo: button.centerXAnchor), icon.topAnchor.constraint(equalTo: button.topAnchor), label.centerXAnchor.constraint(equalTo: button.centerXAnchor), label.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 4)]); return button }

    private func imageOption(assetName: String, title: String) -> UIView { let button = UIButton(type: .system); button.translatesAutoresizingMaskIntoConstraints = false; button.backgroundColor = .clear; let icon = UIImageView(image: UIImage(named: assetName)); icon.translatesAutoresizingMaskIntoConstraints = false; icon.contentMode = .scaleAspectFit; button.addSubview(icon); let label = WatchTheme.label(title, size: 11, color: WatchTheme.secondaryText); button.addSubview(label); NSLayoutConstraint.activate([button.heightAnchor.constraint(equalToConstant: 52), icon.centerXAnchor.constraint(equalTo: button.centerXAnchor), icon.topAnchor.constraint(equalTo: button.topAnchor), icon.widthAnchor.constraint(equalToConstant: 26), icon.heightAnchor.constraint(equalToConstant: 24), label.centerXAnchor.constraint(equalTo: button.centerXAnchor), label.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 4)]); return button }

    @objc private func keyboardChanged() { DispatchQueue.main.async { [weak self] in guard let self, self.view.window != nil else { return }; self.view.layoutIfNeeded(); let rect = self.loginButton.convert(self.loginButton.bounds.insetBy(dx: 0, dy: -12), to: self.scrollView); self.scrollView.scrollRectToVisible(rect, animated: true) } }

    @objc private func submitButtonTapped() { submit() }

    private func submit() {
        guard !(roomField.text ?? "").isEmpty, !(appIDField.text ?? "").isEmpty else { roomField.layer.borderColor = WatchTheme.red.cgColor; statusLabel.text = NSLocalizedString("watch_login_required", comment: ""); statusLabel.isHidden = false; return }
        view.endEditing(true)
        loginButton.isEnabled = false
        loginButton.setTitle(NSLocalizedString("watch_login_loading", comment: ""), for: .normal)
        statusLabel.isHidden = true
        onLogin?(roomField.text ?? "", appIDField.text ?? "", (secretField.text ?? "").ifEmpty("watch_local_secret"))
    }

    func renderLoginState(_ state: IoTLoginState) {
        switch state {
        case .loggingIn:
            loginButton.isEnabled = false
            loginButton.setTitle(NSLocalizedString("watch_login_loading", comment: ""), for: .normal)
            statusLabel.isHidden = true
        case .failed:
            loginButton.isEnabled = true
            loginButton.setTitle(NSLocalizedString("watch_login", comment: ""), for: .normal)
            statusLabel.text = NSLocalizedString("watch_login_failed", comment: "")
            statusLabel.isHidden = false
        default:
            loginButton.isEnabled = true
            loginButton.setTitle(NSLocalizedString("watch_login", comment: ""), for: .normal)
            statusLabel.isHidden = true
        }
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
