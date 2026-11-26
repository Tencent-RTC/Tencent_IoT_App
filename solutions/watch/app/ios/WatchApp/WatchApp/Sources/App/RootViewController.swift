import UIKit

final class RootViewController: UIViewController {
    private let store = AppStateStore()
    private let contentView = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = WatchTheme.background
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: view.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        installWatchSystemBottomBar()
        showLogin()
    }

    private func showLogin() {
        let controller = LoginViewController()
        store.onLoginStateChange = { [weak self, weak controller] state in
            controller?.renderLoginState(state)
            switch state {
            case .loggedIn:
                self?.showMain()
            case .failed(code: "SDK_UNAVAILABLE", message: _):
                // 模拟器没有设备端 SDK 能力时仍进入本地演示主界面，保持导航状态与界面一致。
                self?.store.authenticate()
                self?.showMain()
            default:
                break
            }
        }
        controller.onLogin = { [weak self] channel, appID, secret in
            guard let self else { return }
            store.login(channel: channel, appID: appID, appSecret: secret)
        }
        replaceContent(with: controller)
    }

    private func showMain() {
        let controller = MainTabViewController(store: store)
        controller.onLogout = { [weak self] in self?.showLogin() }
        replaceContent(with: controller)
    }

    private func replaceContent(with controller: UIViewController) {
        children.forEach { child in
            child.willMove(toParent: nil)
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
        attachChild(controller, to: contentView)
    }
}
