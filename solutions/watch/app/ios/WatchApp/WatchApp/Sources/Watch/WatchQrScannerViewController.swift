import AVFoundation
import UIKit

final class WatchQrScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onBack: (() -> Void)?
    var onScan: ((String) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.tencent.iot.watchapp.watch-scan")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasScanned = false
    private let deniedLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        buildView()
        requestCameraAccess()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startSessionIfAuthorized()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }

    private func buildView() {
        let previewContainer = UIView()
        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewContainer)

        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        view.addSubview(header)

        let back = WatchTheme.backButton(
            identifier: "scan.back",
            label: NSLocalizedString("watch_scan_back", comment: ""),
            tint: .white
        ) { [weak self] in
            self?.onBack?()
        }
        let title = WatchTheme.label("watch_scan_title", size: 18, weight: .bold, color: .white)
        title.textAlignment = .center
        header.addSubview(back); header.addSubview(title)

        let scanBox = UIView()
        scanBox.translatesAutoresizingMaskIntoConstraints = false
        scanBox.layer.borderColor = UIColor.white.cgColor
        scanBox.layer.borderWidth = 2
        scanBox.layer.cornerRadius = 18
        view.addSubview(scanBox)
        let hint = WatchTheme.label("watch_scan_hint", size: 14, color: .white)
        hint.textAlignment = .center
        view.addSubview(hint)

        deniedLabel.translatesAutoresizingMaskIntoConstraints = false
        deniedLabel.text = NSLocalizedString("watch_scan_permission_denied", comment: "")
        deniedLabel.textColor = .white
        deniedLabel.font = .systemFont(ofSize: 14)
        deniedLabel.textAlignment = .center
        deniedLabel.numberOfLines = 0
        deniedLabel.isHidden = true
        view.addSubview(deniedLabel)

        NSLayoutConstraint.activate([
            previewContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor), previewContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor), previewContainer.topAnchor.constraint(equalTo: view.topAnchor), previewContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor), header.trailingAnchor.constraint(equalTo: view.trailingAnchor), header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8), header.heightAnchor.constraint(equalToConstant: 52),
            back.leadingAnchor.constraint(equalTo: header.leadingAnchor), back.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            title.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 48), title.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -48), title.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            scanBox.centerXAnchor.constraint(equalTo: view.centerXAnchor), scanBox.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20), scanBox.widthAnchor.constraint(equalToConstant: 248), scanBox.heightAnchor.constraint(equalToConstant: 248),
            hint.topAnchor.constraint(equalTo: scanBox.bottomAnchor, constant: 20), hint.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            deniedLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24), deniedLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24), deniedLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        previewContainer.layer.insertSublayer(layer, at: 0)
        previewLayer = layer
    }

    private func requestCameraAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: startSessionIfAuthorized()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async { granted ? self?.startSessionIfAuthorized() : self?.showDenied() }
            }
        default: showDenied()
        }
    }

    private func startSessionIfAuthorized() {
        guard isViewLoaded, AVCaptureDevice.authorizationStatus(for: .video) == .authorized, !session.isRunning else { return }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard !self.session.isRunning else { return }
            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }
            if self.session.inputs.isEmpty {
                guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device), self.session.canAddInput(input) else { return }
                self.session.addInput(input)
            }
            if self.session.outputs.isEmpty {
                let output = AVCaptureMetadataOutput()
                guard self.session.canAddOutput(output) else { return }
                self.session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                output.metadataObjectTypes = [.qr]
            }
            self.session.startRunning()
            DispatchQueue.main.async { self.previewLayer?.frame = self.view.bounds }
        }
    }

    private func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func showDenied() { deniedLabel.isHidden = false }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !hasScanned, let code = metadataObjects.compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }).first, !code.isEmpty else { return }
        hasScanned = true
        stopSession()
        onScan?(code)
    }
}
