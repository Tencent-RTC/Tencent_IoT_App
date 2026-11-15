import UIKit

final class BindWatchViewController: UIViewController {
    var onBack: (() -> Void)?
    var onBind: ((String) -> Void)?

    private let input = UITextField()
    private let errorLabel = UILabel()
    private let submitButton = UIButton(type: .system)
    private let submitBackground = CAGradientLayer()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = WatchTheme.surface
        buildView()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.input.text.isNilOrEmpty else { return }
            self.input.becomeFirstResponder()
        }
    }

    private func buildView() {
        input.accessibilityIdentifier = "watch.deviceName"
        submitButton.accessibilityIdentifier = "watch.bind"
        let toolbar = UIView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.backgroundColor = WatchTheme.surface
        view.addSubview(toolbar)

        let back = WatchTheme.backButton(
            identifier: "watch.bind.back",
            label: NSLocalizedString("watch_bind_watch_back", comment: "")
        ) { [weak self] in
            self?.view.endEditing(true)
            self?.onBack?()
        }
        toolbar.addSubview(back)

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.isAccessibilityElement = false
        scrollView.shouldGroupAccessibilityChildren = false
        view.addSubview(scrollView)

        let content = UIView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.isAccessibilityElement = false
        scrollView.addSubview(content)

        let title = WatchTheme.label("watch_bind_watch_page_title", size: 27, weight: .bold)
        title.textAlignment = .center
        content.addSubview(title)

        let form = UIView()
        form.translatesAutoresizingMaskIntoConstraints = false
        form.isAccessibilityElement = false
        content.addSubview(form)

        let fieldLabel = WatchTheme.label("watch_bind_watch_device_label", size: 16, weight: .medium)
        form.addSubview(fieldLabel)

        input.translatesAutoresizingMaskIntoConstraints = false
        input.isAccessibilityElement = true
        input.accessibilityLabel = NSLocalizedString("watch_bind_watch_device_label", comment: "")
        input.placeholder = NSLocalizedString("watch_bind_watch_device_hint", comment: "")
        input.font = .systemFont(ofSize: 16)
        input.textColor = WatchTheme.primaryText
        input.tintColor = WatchTheme.blue
        input.backgroundColor = WatchTheme.surfaceStrong
        input.layer.cornerRadius = 10
        input.isUserInteractionEnabled = true
        input.keyboardType = .asciiCapable
        input.textContentType = .username
        input.enablesReturnKeyAutomatically = false
        input.autocapitalizationType = .none
        input.autocorrectionType = .no
        input.spellCheckingType = .no
        input.returnKeyType = .done
        input.clearButtonMode = .whileEditing
        input.addTarget(self, action: #selector(inputChanged), for: .editingChanged)
        input.delegate = self
        view.addSubview(input)
        input.accessibilityIdentifier = "watch.deviceName"
        input.isAccessibilityElement = true
        input.accessibilityElementsHidden = false

        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = WatchTheme.addDivider
        form.addSubview(divider)

        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.textColor = UIColor(red: 0.843, green: 0.184, blue: 0.263, alpha: 1)
        errorLabel.font = .systemFont(ofSize: 13)
        errorLabel.numberOfLines = 1
        errorLabel.isHidden = true
        content.addSubview(errorLabel)

        let buttonContainer = UIView()
        buttonContainer.translatesAutoresizingMaskIntoConstraints = false
        buttonContainer.layer.cornerRadius = 16
        buttonContainer.clipsToBounds = true
        submitBackground.startPoint = CGPoint(x: 0, y: 0.5)
        submitBackground.endPoint = CGPoint(x: 1, y: 0.5)
        buttonContainer.layer.insertSublayer(submitBackground, at: 0)
        content.addSubview(buttonContainer)

        submitButton.translatesAutoresizingMaskIntoConstraints = false
        submitButton.isAccessibilityElement = true
        submitButton.accessibilityLabel = NSLocalizedString("watch_bind_watch_submit", comment: "")
        submitButton.setTitle(NSLocalizedString("watch_bind_watch_submit", comment: ""), for: .normal)
        submitButton.setTitleColor(WatchTheme.surface, for: .normal)
        submitButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        submitButton.addAction(UIAction { [weak self] _ in self?.submit() }, for: .touchUpInside)
        buttonContainer.addSubview(submitButton)

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor), toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor), toolbar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8), toolbar.heightAnchor.constraint(equalToConstant: 52),
            back.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor), back.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor), scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor), scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor), scrollView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16), content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16), content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 62), content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -32), content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor), title.trailingAnchor.constraint(equalTo: content.trailingAnchor), title.topAnchor.constraint(equalTo: content.topAnchor), title.heightAnchor.constraint(equalToConstant: 38),
            form.leadingAnchor.constraint(equalTo: content.leadingAnchor), form.trailingAnchor.constraint(equalTo: content.trailingAnchor), form.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 32), form.heightAnchor.constraint(equalToConstant: 64),
            fieldLabel.leadingAnchor.constraint(equalTo: form.leadingAnchor, constant: 4), fieldLabel.centerYAnchor.constraint(equalTo: form.centerYAnchor), fieldLabel.widthAnchor.constraint(equalToConstant: 72),
            input.leadingAnchor.constraint(equalTo: fieldLabel.trailingAnchor, constant: 18), input.trailingAnchor.constraint(equalTo: form.trailingAnchor, constant: -4), input.centerYAnchor.constraint(equalTo: form.centerYAnchor), input.heightAnchor.constraint(equalToConstant: 44),
            divider.leadingAnchor.constraint(equalTo: form.leadingAnchor), divider.trailingAnchor.constraint(equalTo: form.trailingAnchor), divider.bottomAnchor.constraint(equalTo: form.bottomAnchor), divider.heightAnchor.constraint(equalToConstant: 1),
            errorLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor), errorLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor), errorLabel.topAnchor.constraint(equalTo: form.bottomAnchor, constant: 8), errorLabel.heightAnchor.constraint(equalToConstant: 24),
            buttonContainer.leadingAnchor.constraint(equalTo: content.leadingAnchor), buttonContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor), buttonContainer.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 10), buttonContainer.heightAnchor.constraint(equalToConstant: 54),
            submitButton.leadingAnchor.constraint(equalTo: buttonContainer.leadingAnchor), submitButton.trailingAnchor.constraint(equalTo: buttonContainer.trailingAnchor), submitButton.topAnchor.constraint(equalTo: buttonContainer.topAnchor), submitButton.bottomAnchor.constraint(equalTo: buttonContainer.bottomAnchor)
        ])

        updateSubmitState()
    }

    @objc private func inputChanged() {
        errorLabel.isHidden = !input.text.isNilOrEmpty
        updateSubmitState()
    }

    func showError(_ message: String) {
        errorLabel.text = message
        errorLabel.isHidden = false
        input.becomeFirstResponder()
    }

    private func submit() {
        let value = input.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty else {
            showError(NSLocalizedString("watch_bind_watch_device_required", comment: ""))
            return
        }
        view.endEditing(true)
        onBind?(value)
    }

    private func updateSubmitState() {
        let enabled = !(input.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        submitButton.isEnabled = enabled
        submitButton.alpha = enabled ? 1 : 0.72
        submitBackground.colors = enabled
            ? [WatchTheme.blue.cgColor, WatchTheme.purple.cgColor]
            : [UIColor(red: 0.882, green: 0.902, blue: 1, alpha: 1).cgColor, UIColor(red: 0.882, green: 0.902, blue: 1, alpha: 1).cgColor]
    }
}

extension BindWatchViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        submit()
        return true
    }
}

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool { self?.isEmpty ?? true }
}
