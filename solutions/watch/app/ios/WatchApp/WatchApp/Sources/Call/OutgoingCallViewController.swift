import UIKit
import AVFoundation

final class OutgoingCallViewController: UIViewController {
    private weak var store: AppStateStore?
    private let displayName: String
    private let avatarKey: String
    private let avatarColor: UIColor
    private let voiceMode: Bool
    private var localView: UIView?
    private weak var stageView: UIView?
    private var localPip: UIView?
    private var remoteView: UIView?
    private var statusLabel: UILabel?
    private var navSubtitle: UILabel?
    private var waitView: UIView?
    private var voiceContent: UIView?
    private var voiceWave: UIView?
    private var dock: UIVisualEffectView?
    private var toolRow: UIStackView?
    private var active = false
    private var microphoneEnabled = true
    private var speakerEnabled = true
    private var cameraEnabled = true
    private var activeStartedAt = Date()
    private var timer: Timer?
    private var controls: [String: CallControlView] = [:]

    init(store: AppStateStore? = nil, displayName: String, avatarKey: String, avatarColor: UIColor, voiceMode: Bool) {
        self.store = store
        self.displayName = displayName
        self.avatarKey = avatarKey
        self.avatarColor = avatarColor
        self.voiceMode = voiceMode
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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startLocalPreviewIfNeeded()
        store?.addCallStateObserver { [weak self] state in
            guard state.phase == .active else { return }
            self?.showActiveMedia()
        }
        if store?.callState().phase == .active { showActiveMedia() }
    }

    deinit { timer?.invalidate() }

    private func buildView() {
        if voiceMode {
            let background = WatchCallBackgroundView()
            addFullScreen(background)
        } else {
            let stage = UIImageView(image: UIImage(named: "CallLocalMom"))
            stage.translatesAutoresizingMaskIntoConstraints = false
            stage.contentMode = .scaleAspectFill
            stage.backgroundColor = .black
            view.addSubview(stage)
            stageView = stage
            NSLayoutConstraint.activate([
                stage.leadingAnchor.constraint(equalTo: view.leadingAnchor), stage.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                stage.topAnchor.constraint(equalTo: view.topAnchor), stage.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            addOverlay(colors: [UIColor(red: 0.063, green: 0.125, blue: 0.231, alpha: 0.62), .clear], locations: [0, 1], height: 250, top: true)
            addOverlay(colors: [.clear, UIColor(red: 0.063, green: 0.125, blue: 0.231, alpha: 0.84)], locations: [0, 1], height: 280, top: false)
        }

        buildNavigation()
        if voiceMode { buildVoiceContent() } else { buildVideoWaitingContent() }
        buildDock()
    }

    private func buildNavigation() {
        let nav = UIView()
        nav.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(nav)
        let back = WatchTheme.backButton(identifier: "call.back", label: NSLocalizedString("watch_back", comment: ""), tint: WatchTheme.surface) { [weak self] in
            self?.finishCall()
        }
        nav.addSubview(back)
        NSLayoutConstraint.activate([back.leadingAnchor.constraint(equalTo: nav.leadingAnchor), back.centerYAnchor.constraint(equalTo: nav.centerYAnchor)])
        let title = WatchTheme.label(voiceMode ? "watch_call_voice" : displayName, size: 17, weight: .semibold, color: WatchTheme.surface)
        let subtitle = WatchTheme.label(voiceMode ? "watch_call_voice_calling" : "watch_call_video_calling", size: 12, color: WatchTheme.callSecondaryText)
        subtitle.textAlignment = .center
        let titleStack = UIStackView(arrangedSubviews: [title, subtitle])
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        titleStack.axis = .vertical; titleStack.alignment = .center; titleStack.spacing = 2
        nav.addSubview(titleStack)
        NSLayoutConstraint.activate([titleStack.centerXAnchor.constraint(equalTo: nav.centerXAnchor), titleStack.centerYAnchor.constraint(equalTo: nav.centerYAnchor)])
        navSubtitle = subtitle
        NSLayoutConstraint.activate([
            nav.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20), nav.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            nav.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4), nav.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func buildVideoWaitingContent() {
        let avatar = WatchTheme.avatar(textKey: avatarKey, color: avatarColor, size: 120)
        let status = WatchTheme.label("watch_call_waiting", size: 15, color: WatchTheme.surface)
        status.accessibilityIdentifier = "call.status"
        statusLabel = status
        let content = UIStackView(arrangedSubviews: [avatar, status])
        content.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .vertical; content.alignment = .center; content.spacing = 16
        view.addSubview(content)
        NSLayoutConstraint.activate([content.centerXAnchor.constraint(equalTo: view.centerXAnchor), content.topAnchor.constraint(equalTo: view.topAnchor, constant: 272)])
        waitView = content
    }

    private func buildVoiceContent() {
        let avatar = WatchTheme.avatar(textKey: avatarKey, color: avatarColor, size: 128)
        let ring = UIView(); ring.translatesAutoresizingMaskIntoConstraints = false; ring.backgroundColor = UIColor.white.withAlphaComponent(0.16); ring.layer.cornerRadius = 72; ring.layer.borderWidth = 1; ring.layer.borderColor = UIColor.white.withAlphaComponent(0.42).cgColor
        ring.addSubview(avatar)
        NSLayoutConstraint.activate([avatar.centerXAnchor.constraint(equalTo: ring.centerXAnchor), avatar.centerYAnchor.constraint(equalTo: ring.centerYAnchor)])
        let name = WatchTheme.label(displayName, size: 28, weight: .bold, color: WatchTheme.surface)
        let status = WatchTheme.label("watch_call_waiting", size: 13, color: WatchTheme.callSecondaryText)
        status.backgroundColor = UIColor.white.withAlphaComponent(0.15); status.layer.cornerRadius = 16; status.clipsToBounds = true; status.textAlignment = .center
        status.layoutMargins = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        statusLabel = status
        let wave = WatchCallWaveView(); wave.translatesAutoresizingMaskIntoConstraints = false; wave.isHidden = true
        let content = UIStackView(arrangedSubviews: [ring, name, status, wave])
        content.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .vertical; content.alignment = .center; content.spacing = 14
        view.addSubview(content)
        NSLayoutConstraint.activate([ring.widthAnchor.constraint(equalToConstant: 144), ring.heightAnchor.constraint(equalToConstant: 144), wave.widthAnchor.constraint(equalToConstant: 150), wave.heightAnchor.constraint(equalToConstant: 40), content.centerXAnchor.constraint(equalTo: view.centerXAnchor), content.topAnchor.constraint(equalTo: view.topAnchor, constant: 175)])
        voiceContent = content; voiceWave = wave
    }

    private func buildDock() {
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.layer.cornerRadius = 32; blur.clipsToBounds = true; blur.backgroundColor = UIColor(red: 0.078, green: 0.141, blue: 0.243, alpha: 0.60)
        view.addSubview(blur)
        NSLayoutConstraint.activate([blur.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12), blur.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12), blur.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)])
        dock = blur
        let row = UIStackView(); row.translatesAutoresizingMaskIntoConstraints = false; row.axis = .horizontal; row.alignment = .top; row.distribution = .fillEqually; row.spacing = 8
        blur.contentView.addSubview(row)
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor, constant: 16), row.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor, constant: -16), row.topAnchor.constraint(equalTo: blur.contentView.topAnchor, constant: 20)])
        toolRow = row
        if voiceMode {
            row.addArrangedSubview(control("mute", icon: .mic, title: "watch_call_mute") { [weak self] in self?.toggleMicrophone() })
            row.addArrangedSubview(control("speaker", icon: .speaker, title: "watch_call_speaker") { [weak self] in self?.toggleSpeaker() })
        } else {
            row.addArrangedSubview(control("speaker", icon: .speaker, title: "watch_call_speaker") { [weak self] in self?.toggleSpeaker() })
            row.addArrangedSubview(control("flip", icon: .flip, title: "watch_call_flip") { [weak self] in self?.store?.switchCamera() })
            row.addArrangedSubview(control("camera", icon: .video, title: "watch_call_camera") { [weak self] in self?.toggleCamera() })
        }
        let action = UIButton(type: .system); action.translatesAutoresizingMaskIntoConstraints = false; action.setTitle(NSLocalizedString("watch_cancel", comment: ""), for: .normal); action.setTitleColor(WatchTheme.surface, for: .normal); action.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold); action.backgroundColor = WatchTheme.red; action.layer.cornerRadius = 26; action.accessibilityIdentifier = "call.hangup"; action.addAction(UIAction { [weak self] _ in self?.finishCall() }, for: .touchUpInside)
        blur.contentView.addSubview(action)
        NSLayoutConstraint.activate([action.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor, constant: 16), action.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor, constant: -16), action.topAnchor.constraint(equalTo: row.bottomAnchor, constant: 20), action.heightAnchor.constraint(equalToConstant: 52), action.bottomAnchor.constraint(equalTo: blur.contentView.bottomAnchor, constant: -16)])
    }

    private func control(_ key: String, icon: WatchIconKind, title: String, action: @escaping () -> Void) -> CallControlView {
        let item = CallControlView(icon: icon, titleKey: title, action: action)
        item.accessibilityIdentifier = "call.\(key)"
        if key == "speaker" { item.setSelected(true) }
        controls[key] = item
        return item
    }

    private func startLocalPreviewIfNeeded() {
        guard !voiceMode, !active, !localPreviewStarted, let local = makeLocalView() else { return }
        localPreviewStarted = true
        // 本地视频预览开始后，隐藏等待页中的手表头像和背景图，避免覆盖摄像头画面。
        stageView?.isHidden = true
        waitView?.isHidden = true
        let start: () -> Void = { [weak self, weak local] in guard let self, let local else { return }; self.store?.startLocalVideo(UIKitCallVideoSurface(view: local)) }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: start()
        case .notDetermined: AVCaptureDevice.requestAccess(for: .video) { granted in if granted { DispatchQueue.main.async(execute: start) } }
        default: break
        }
    }

    private var localPreviewStarted = false
    private func makeLocalView() -> UIView? {
        if let localView { return localView }
        let local = UIView(); local.translatesAutoresizingMaskIntoConstraints = false; local.backgroundColor = .black
        view.insertSubview(local, at: min(1, view.subviews.count))
        NSLayoutConstraint.activate([local.leadingAnchor.constraint(equalTo: view.leadingAnchor), local.trailingAnchor.constraint(equalTo: view.trailingAnchor), local.topAnchor.constraint(equalTo: view.topAnchor), local.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        localView = local
        return local
    }

    private func showActiveMedia() {
        guard !active else { return }
        active = true; activeStartedAt = Date(); timer?.invalidate(); timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.updateTimer() }; updateTimer()
        waitView?.isHidden = true
        if voiceMode { voiceWave?.isHidden = false; return }
        guard let local = makeLocalView() else { return }
        stageView?.isHidden = true
        let remote = UIView(); remote.translatesAutoresizingMaskIntoConstraints = false; remote.backgroundColor = .black; view.insertSubview(remote, at: 0); NSLayoutConstraint.activate([remote.leadingAnchor.constraint(equalTo: view.leadingAnchor), remote.trailingAnchor.constraint(equalTo: view.trailingAnchor), remote.topAnchor.constraint(equalTo: view.topAnchor), remote.bottomAnchor.constraint(equalTo: view.bottomAnchor)]); remoteView = remote; store?.bindRemote(UIKitCallVideoSurface(view: remote))
        let pip = UIView(); pip.translatesAutoresizingMaskIntoConstraints = false; pip.backgroundColor = .black; pip.layer.cornerRadius = 18; pip.layer.borderWidth = 1; pip.layer.borderColor = UIColor.white.withAlphaComponent(0.82).cgColor; pip.clipsToBounds = true; view.addSubview(pip); view.bringSubviewToFront(pip); local.removeFromSuperview(); pip.addSubview(local); NSLayoutConstraint.activate([pip.widthAnchor.constraint(equalToConstant: 100), pip.heightAnchor.constraint(equalToConstant: 140), pip.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20), pip.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 59), local.leadingAnchor.constraint(equalTo: pip.leadingAnchor), local.trailingAnchor.constraint(equalTo: pip.trailingAnchor), local.topAnchor.constraint(equalTo: pip.topAnchor), local.bottomAnchor.constraint(equalTo: pip.bottomAnchor)]); localPip = pip
        let label = WatchTheme.label("watch_me", size: 11, weight: .semibold, color: WatchTheme.surface); pip.addSubview(label); NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: pip.leadingAnchor, constant: 8), label.bottomAnchor.constraint(equalTo: pip.bottomAnchor, constant: -8)])
        view.bringSubviewToFront(dock ?? UIView())
    }

    private func updateTimer() {
        guard active else { return }
        let seconds = max(0, Int(Date().timeIntervalSince(activeStartedAt))); let time = String(format: "%02d:%02d", seconds / 60, seconds % 60)
        navSubtitle?.text = String(format: NSLocalizedString(voiceMode ? "watch_call_active_voice" : "watch_call_active_video", comment: ""), time)
        statusLabel?.text = String(format: NSLocalizedString(voiceMode ? "watch_call_active_voice" : "watch_call_active_video", comment: ""), time)
    }

    private func toggleMicrophone() { microphoneEnabled.toggle(); store?.setMicrophoneEnabled(microphoneEnabled); controls["mute"]?.setSelected(!microphoneEnabled) }
    private func toggleSpeaker() { speakerEnabled.toggle(); store?.setSpeakerphoneEnabled(speakerEnabled); controls["speaker"]?.setSelected(speakerEnabled) }
    private func toggleCamera() { cameraEnabled.toggle(); if let localView { store?.setCameraEnabled(cameraEnabled, surface: UIKitCallVideoSurface(view: localView)) }; localView?.isHidden = !cameraEnabled; controls["camera"]?.setSelected(!cameraEnabled) }
    private func finishCall() { timer?.invalidate(); store?.hangupCall(); dismiss(animated: true) }

    private func addFullScreen(_ child: UIView) { child.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(child); NSLayoutConstraint.activate([child.leadingAnchor.constraint(equalTo: view.leadingAnchor), child.trailingAnchor.constraint(equalTo: view.trailingAnchor), child.topAnchor.constraint(equalTo: view.topAnchor), child.bottomAnchor.constraint(equalTo: view.bottomAnchor)]) }
    private func addOverlay(colors: [UIColor], locations: [NSNumber], height: CGFloat, top: Bool) { let overlay = WatchCallOverlayView(colors: colors, locations: locations); overlay.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(overlay); NSLayoutConstraint.activate([overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor), overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor), top ? overlay.topAnchor.constraint(equalTo: view.topAnchor) : overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor), overlay.heightAnchor.constraint(equalToConstant: height)]) }
}

private final class CallControlView: UIControl {
    private let button = UIButton(type: .system)
    private let icon: WatchIconView
    private let action: () -> Void
    init(icon kind: WatchIconKind, titleKey: String, action: @escaping () -> Void) {
        self.icon = WatchTheme.icon(kind, tint: WatchTheme.surface, size: 23); self.action = action; super.init(frame: .zero); translatesAutoresizingMaskIntoConstraints = false; button.translatesAutoresizingMaskIntoConstraints = false; button.isUserInteractionEnabled = false; button.backgroundColor = UIColor.white.withAlphaComponent(0.16); button.layer.cornerRadius = 26; button.addSubview(self.icon); addSubview(button); let title = WatchTheme.label(titleKey, size: 11, color: WatchTheme.surface); title.textAlignment = .center; addSubview(title); NSLayoutConstraint.activate([button.topAnchor.constraint(equalTo: topAnchor), button.centerXAnchor.constraint(equalTo: centerXAnchor), button.widthAnchor.constraint(equalToConstant: 52), button.heightAnchor.constraint(equalToConstant: 52), self.icon.centerXAnchor.constraint(equalTo: button.centerXAnchor), self.icon.centerYAnchor.constraint(equalTo: button.centerYAnchor), title.topAnchor.constraint(equalTo: button.bottomAnchor, constant: 6), title.centerXAnchor.constraint(equalTo: centerXAnchor), title.bottomAnchor.constraint(equalTo: bottomAnchor)]); addTarget(self, action: #selector(pressed), for: .touchUpInside)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func pressed() { action() }
    func setSelected(_ selected: Bool) { button.backgroundColor = selected ? WatchTheme.blue : UIColor.white.withAlphaComponent(0.16) }
}

private final class WatchCallWaveView: UIView {
    override func draw(_ rect: CGRect) { UIColor(red: 0.42, green: 0.86, blue: 0.78, alpha: 1).setFill(); let heights: [CGFloat] = [18, 30, 22, 36, 22, 30]; for (index, height) in heights.enumerated() { UIBezierPath(roundedRect: CGRect(x: 10 + CGFloat(index) * 24, y: (rect.height - height) / 2, width: 5, height: height), cornerRadius: 3).fill() } }
}

private final class WatchCallOverlayView: UIView {
    private let gradient = CAGradientLayer()
    init(colors: [UIColor], locations: [NSNumber]) { super.init(frame: .zero); isUserInteractionEnabled = false; gradient.colors = colors.map(\.cgColor); gradient.locations = locations; layer.addSublayer(gradient) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() { super.layoutSubviews(); gradient.frame = bounds }
}

private final class WatchCallBackgroundView: UIView {
    private let gradient = CAGradientLayer()
    override init(frame: CGRect) { super.init(frame: frame); gradient.type = .radial; gradient.colors = [UIColor(red: 0.192, green: 0.333, blue: 0.541, alpha: 1).cgColor, UIColor(red: 0.078, green: 0.141, blue: 0.243, alpha: 1).cgColor]; gradient.startPoint = CGPoint(x: 0.5, y: 0.16); gradient.endPoint = CGPoint(x: 1, y: 0.85); layer.addSublayer(gradient) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() { super.layoutSubviews(); gradient.frame = bounds }
}
