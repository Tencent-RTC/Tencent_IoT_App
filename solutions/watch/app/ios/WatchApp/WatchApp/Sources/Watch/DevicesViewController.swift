import UIKit

final class DevicesViewController: UIViewController, UIScrollViewDelegate {
    private let store: AppStateStore
    var onAddWatch: (() -> Void)?

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let toolbar = UIStackView()
    private let carousel = UIScrollView()
    private let carouselStack = UIStackView()
    private let pager = UIStackView()
    private var boundWatches: [BoundWatch] = []
    private var selectedIndex = 0
    private var pagerDots: [UIView] = []

    init(store: AppStateStore) { self.store = store; super.init(nibName: nil, bundle: nil) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = WatchTheme.background
        boundWatches = WatchBindingStore.all(userID: store.imManager.loggedInUserID)
        buildView()
        renderSelection()
    }

    private func buildView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 0
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        toolbar.axis = .horizontal
        toolbar.alignment = .center
        toolbar.isLayoutMarginsRelativeArrangement = true
        toolbar.layoutMargins = UIEdgeInsets(top: 0, left: 24, bottom: 0, right: 16)
        toolbar.addArrangedSubview(WatchTheme.label("watch_devices", size: 27, weight: .bold))
        let spacer = UIView(); toolbar.addArrangedSubview(spacer)
        let scan = UIButton(type: .system)
        scan.translatesAutoresizingMaskIntoConstraints = false
        scan.addSubview(WatchTheme.icon(.scan, tint: WatchTheme.blue, size: 24))
        if let icon = scan.subviews.first {
            NSLayoutConstraint.activate([icon.centerXAnchor.constraint(equalTo: scan.centerXAnchor), icon.centerYAnchor.constraint(equalTo: scan.centerYAnchor)])
        }
        scan.accessibilityLabel = NSLocalizedString("watch_scan_title", comment: "")
        scan.addAction(UIAction { [weak self] _ in self?.onAddWatch?() }, for: .touchUpInside)
        toolbar.addArrangedSubview(scan)
        scan.widthAnchor.constraint(equalToConstant: 44).isActive = true
        scan.heightAnchor.constraint(equalToConstant: 44).isActive = true
        toolbar.heightAnchor.constraint(equalToConstant: 44).isActive = true
        stack.addArrangedSubview(toolbar)

        if boundWatches.isEmpty {
            let empty = WatchTheme.label("watch_call_no_bound_watch", size: 13, color: WatchTheme.secondaryText)
            empty.textAlignment = .center
            empty.backgroundColor = WatchTheme.surface
            empty.layer.cornerRadius = 20
            empty.clipsToBounds = true
            empty.heightAnchor.constraint(equalToConstant: 100).isActive = true
            empty.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
            stack.setCustomSpacing(12, after: toolbar)
            stack.addArrangedSubview(empty)
            pager.isHidden = true
            return
        }

        buildCarousel()
        stack.setCustomSpacing(12, after: toolbar)
        stack.addArrangedSubview(carousel)
        carousel.heightAnchor.constraint(equalToConstant: 140).isActive = true

        pager.axis = .horizontal
        pager.alignment = .center
        pager.spacing = 0
        pager.isLayoutMarginsRelativeArrangement = true
        pager.layoutMargins = .zero
        pager.heightAnchor.constraint(equalToConstant: 24).isActive = true
        stack.addArrangedSubview(pager)

        stack.setCustomSpacing(12, after: pager)
        stack.addArrangedSubview(settingsGroup(rows: [
            settingRow(icon: .watch, color: WatchTheme.blue, background: WatchTheme.lavender, title: "watch_watch_system", value: "watch_view_version"),
            settingRow(icon: .user, color: UIColor(red: 1, green: 0.54, blue: 0.24, alpha: 1), background: UIColor(red: 1, green: 0.94, blue: 0.89, alpha: 1), title: "watch_bind_member", value: "watch_view_member"),
            settingRow(icon: .message, color: WatchTheme.purple, background: UIColor(red: 0.95, green: 0.92, blue: 1, alpha: 1), title: "watch_watch_contacts", value: "watch_view_contacts")
        ]))
        stack.setCustomSpacing(12, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(settingsGroup(rows: [
            settingRow(icon: .appid, color: WatchTheme.purple, background: UIColor(red: 0.95, green: 0.92, blue: 1, alpha: 1), title: "watch_app_management", value: "watch_view_apps"),
            settingRow(icon: .locator, color: WatchTheme.mint, background: UIColor(red: 0.88, green: 0.98, blue: 0.94, alpha: 1), title: "watch_find_device", value: "watch_ring_to_find"),
            settingRow(icon: .batterySave, color: UIColor(red: 0.18, green: 0.61, blue: 1, alpha: 1), background: UIColor(red: 0.89, green: 0.95, blue: 1, alpha: 1), title: "watch_long_battery", value: "watch_not_enabled")
        ]))
    }

    private func buildCarousel() {
        carousel.translatesAutoresizingMaskIntoConstraints = false
        carousel.delegate = self
        carousel.clipsToBounds = true
        carousel.isPagingEnabled = true
        carousel.showsHorizontalScrollIndicator = false
        carousel.alwaysBounceHorizontal = boundWatches.count > 1
        carouselStack.translatesAutoresizingMaskIntoConstraints = false
        carouselStack.axis = .horizontal
        carouselStack.spacing = 0
        carousel.addSubview(carouselStack)
        NSLayoutConstraint.activate([
            carouselStack.leadingAnchor.constraint(equalTo: carousel.contentLayoutGuide.leadingAnchor),
            carouselStack.trailingAnchor.constraint(equalTo: carousel.contentLayoutGuide.trailingAnchor),
            carouselStack.topAnchor.constraint(equalTo: carousel.contentLayoutGuide.topAnchor),
            carouselStack.bottomAnchor.constraint(equalTo: carousel.contentLayoutGuide.bottomAnchor),
            carouselStack.heightAnchor.constraint(equalTo: carousel.frameLayoutGuide.heightAnchor)
        ])
        boundWatches.forEach { bound in
            let page = UIView()
            page.translatesAutoresizingMaskIntoConstraints = false
            let card = deviceCard(bound)
            card.accessibilityIdentifier = "device.card.\(bound.deviceName)"
            page.addSubview(card)
            carouselStack.addArrangedSubview(page)
            NSLayoutConstraint.activate([
                page.widthAnchor.constraint(equalTo: carousel.frameLayoutGuide.widthAnchor),
                card.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: 16),
                card.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -16),
                card.topAnchor.constraint(equalTo: page.topAnchor),
                card.bottomAnchor.constraint(equalTo: page.bottomAnchor)
            ])
        }
        let dots = UIStackView()
        dots.axis = .horizontal
        dots.alignment = .center
        dots.spacing = 0
        dots.translatesAutoresizingMaskIntoConstraints = false
        boundWatches.indices.forEach { index in
            let button = UIButton(type: .system)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.accessibilityIdentifier = "device.page.\(index + 1)"
            button.accessibilityLabel = String(format: NSLocalizedString("watch_device_page_description_current", comment: ""), index + 1, boundWatches[index].deviceName)
            button.addAction(UIAction { [weak self] _ in self?.selectDevice(at: index, animated: true) }, for: .touchUpInside)
            let dot = UIView()
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.layer.cornerRadius = 3
            button.addSubview(dot)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 32), button.heightAnchor.constraint(equalToConstant: 24),
                dot.centerXAnchor.constraint(equalTo: button.centerXAnchor), dot.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                dot.heightAnchor.constraint(equalToConstant: 6)
            ])
            dot.transform = CGAffineTransform(translationX: 0, y: 6)
            dots.addArrangedSubview(button)
            pagerDots.append(dot)
        }
        pager.addArrangedSubview(dots)
    }

    private func renderSelection() {
        let total = boundWatches.count
        selectedIndex = selectedIndex.clamped(to: 0, max: max(total - 1, 0))
        pagerDots.enumerated().forEach { index, dot in
            dot.backgroundColor = index == selectedIndex ? WatchTheme.blue : WatchTheme.tertiaryText
            dot.constraints.filter { $0.firstAttribute == .width }.forEach { $0.isActive = false }
            dot.widthAnchor.constraint(equalToConstant: index == selectedIndex ? 20 : 6).isActive = true
        }
    }

    private func selectDevice(at index: Int, animated: Bool) {
        guard boundWatches.indices.contains(index) else { return }
        selectedIndex = index
        carousel.setContentOffset(CGPoint(x: carousel.bounds.width * CGFloat(index), y: 0), animated: animated)
        renderSelection()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { updateSelectionFromScroll() }
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { updateSelectionFromScroll() }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) { if !decelerate { updateSelectionFromScroll() } }

    private func updateSelectionFromScroll() {
        guard carousel.bounds.width > 0, !boundWatches.isEmpty else { return }
        let index = Int(round(carousel.contentOffset.x / carousel.bounds.width))
        guard boundWatches.indices.contains(index) else { return }
        selectedIndex = index
        renderSelection()
    }

    private func deviceCard(_ bound: BoundWatch) -> UIView {
        let isGirl = WatchAvatarResolver.key(for: bound.deviceName).contains("girl")
        let card = WatchDeviceCardView(isGirl: isGirl)
        card.translatesAutoresizingMaskIntoConstraints = false
        card.layer.cornerRadius = 20
        card.clipsToBounds = true
        let avatar = WatchTheme.avatar(textKey: WatchAvatarResolver.key(for: bound.deviceName), color: UIColor.white.withAlphaComponent(0.35), size: 48)
        let name = WatchTheme.label(bound.deviceName, size: 17, weight: .medium, color: WatchTheme.surface)
        name.numberOfLines = 1
        name.lineBreakMode = .byTruncatingTail
        let status = WatchTheme.label("watch_bound", size: 11, color: WatchTheme.surface)
        status.backgroundColor = UIColor.white.withAlphaComponent(0.18)
        status.layer.cornerRadius = 8
        status.clipsToBounds = true
        status.textAlignment = .center
        status.heightAnchor.constraint(equalToConstant: 18).isActive = true
        status.widthAnchor.constraint(equalToConstant: 76).isActive = true
        let info = UIStackView(arrangedSubviews: [name, status]); info.axis = .vertical; info.alignment = .leading; info.spacing = 3
        let top = UIStackView(arrangedSubviews: [avatar, info]); top.axis = .horizontal; top.alignment = .center; top.spacing = 13
        let divider = UIView(); divider.backgroundColor = UIColor.white.withAlphaComponent(0.25); divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        let metrics = UIStackView(arrangedSubviews: [metric("watch_battery"), metric("watch_network")]); metrics.axis = .horizontal; metrics.distribution = .fillEqually
        let content = UIStackView(arrangedSubviews: [top, divider, metrics]); content.translatesAutoresizingMaskIntoConstraints = false; content.axis = .vertical; content.spacing = 7; card.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18), content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 16), content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])
        return card
    }

    private func metric(_ title: String) -> UIView {
        let value = WatchTheme.label("watch_no_value", size: 18, weight: .bold, color: WatchTheme.surface)
        let stack = UIStackView(arrangedSubviews: [WatchTheme.label(title, size: 11, color: UIColor.white.withAlphaComponent(0.75)), value])
        stack.axis = .vertical; stack.spacing = 1
        return stack
    }

    private func settingsGroup(rows: [UIView]) -> UIView {
        let card = WatchTheme.card()
        card.layer.cornerRadius = 20
        let stack = UIStackView(); stack.translatesAutoresizingMaskIntoConstraints = false; stack.axis = .vertical; stack.spacing = 0; card.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14), stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14), stack.topAnchor.constraint(equalTo: card.topAnchor), stack.bottomAnchor.constraint(equalTo: card.bottomAnchor)])
        rows.enumerated().forEach { index, row in
            stack.addArrangedSubview(row)
            if index < rows.count - 1 { let line = UIView(); line.backgroundColor = WatchTheme.line; line.heightAnchor.constraint(equalToConstant: 1).isActive = true; stack.addArrangedSubview(line) }
        }
        return card
    }

    private func settingRow(icon: WatchIconKind, color: UIColor, background: UIColor, title: String, value: String) -> UIView {
        let row = UIStackView(); row.axis = .horizontal; row.alignment = .center; row.spacing = 11; row.heightAnchor.constraint(equalToConstant: 54).isActive = true
        let tile = UIView(); tile.translatesAutoresizingMaskIntoConstraints = false; tile.backgroundColor = background; tile.layer.cornerRadius = 10; let image = WatchTheme.icon(icon, tint: color, size: 18); tile.addSubview(image); NSLayoutConstraint.activate([tile.widthAnchor.constraint(equalToConstant: 32), tile.heightAnchor.constraint(equalToConstant: 32), image.centerXAnchor.constraint(equalTo: tile.centerXAnchor), image.centerYAnchor.constraint(equalTo: tile.centerYAnchor)])
        row.addArrangedSubview(tile); row.addArrangedSubview(WatchTheme.label(title, size: 13)); row.addArrangedSubview(UIView()); row.addArrangedSubview(WatchTheme.label(value, size: 11, color: WatchTheme.secondaryText)); row.addArrangedSubview(WatchTheme.trailingChevronSlot()); return row
    }
}

private final class WatchDeviceCardView: UIView {
    private let gradient = CAGradientLayer()
    init(isGirl: Bool) {
        super.init(frame: .zero)
        gradient.colors = (isGirl ? [UIColor(red: 0.545, green: 0.361, blue: 0.965, alpha: 1), UIColor(red: 0.949, green: 0.608, blue: 0.816, alpha: 1)] : [UIColor(red: 0.29, green: 0.404, blue: 1, alpha: 1), UIColor(red: 0.56, green: 0.69, blue: 1, alpha: 1)]).map(\.cgColor)
        gradient.startPoint = CGPoint(x: 0, y: 0); gradient.endPoint = CGPoint(x: 1, y: 1); layer.insertSublayer(gradient, at: 0)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() { super.layoutSubviews(); gradient.frame = bounds; gradient.cornerRadius = layer.cornerRadius }
}

private extension Int {
    func clamped(to minValue: Int, max maxValue: Int) -> Int { Swift.max(minValue, Swift.min(self, maxValue)) }
}
