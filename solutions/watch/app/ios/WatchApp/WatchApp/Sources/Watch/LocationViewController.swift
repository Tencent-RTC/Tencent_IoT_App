import UIKit

final class LocationViewController: UIViewController, UIScrollViewDelegate {
    private let store: AppStateStore
    private var boundWatches: [BoundWatch] = []
    private var selectedIndex = 0
    private let carousel = UIScrollView()
    private let carouselStack = UIStackView()
    private let pager = UIStackView()
    private let countLabel = UILabel()
    private let markerAvatar = UIImageView()
    private var pagerDots: [UIView] = []

    init(store: AppStateStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.87, green: 0.94, blue: 0.91, alpha: 1)
        boundWatches = WatchBindingStore.all(userID: store.imManager.loggedInUserID)
        buildView()
        renderSelection()
    }

    private func buildView() {
        let map = WatchMapView()
        map.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(map)
        NSLayoutConstraint.activate([
            map.leadingAnchor.constraint(equalTo: view.leadingAnchor), map.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            map.topAnchor.constraint(equalTo: view.topAnchor), map.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let title = WatchTheme.label("watch_location_title", size: 24, weight: .bold)
        view.addSubview(title)
        NSLayoutConstraint.activate([title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20), title.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16)])

        let help = WatchTheme.button("watch_location_help")
        help.titleLabel?.font = .systemFont(ofSize: 12)
        view.addSubview(help)
        NSLayoutConstraint.activate([help.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20), help.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16), help.heightAnchor.constraint(equalToConstant: 40)])

        let recent = WatchTheme.button("watch_recent_location")
        recent.titleLabel?.font = .systemFont(ofSize: 12)
        view.addSubview(recent)
        NSLayoutConstraint.activate([recent.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20), recent.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 72), recent.heightAnchor.constraint(equalToConstant: 32)])

        let actions = UIStackView()
        actions.axis = .vertical
        actions.spacing = 8
        actions.translatesAutoresizingMaskIntoConstraints = false
        [(.refresh, "watch_correct_location"), (.navigation, "watch_navigate"), (.locator, "watch_find_watch")].forEach { kind, key in
            let action = WatchTheme.button(key)
            action.titleLabel?.font = .systemFont(ofSize: 9)
            action.setTitleColor(WatchTheme.secondaryText, for: .normal)
            let icon = WatchTheme.icon(kind, tint: WatchTheme.blue, size: 20)
            action.addSubview(icon)
            NSLayoutConstraint.activate([action.widthAnchor.constraint(equalToConstant: 56), action.heightAnchor.constraint(equalToConstant: 58), icon.centerXAnchor.constraint(equalTo: action.centerXAnchor), icon.topAnchor.constraint(equalTo: action.topAnchor, constant: 8)])
            action.titleEdgeInsets = UIEdgeInsets(top: 30, left: 0, bottom: 0, right: 0)
            actions.addArrangedSubview(action)
        }
        view.addSubview(actions)
        NSLayoutConstraint.activate([actions.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16), actions.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 122)])

        let marker = UIView()
        marker.translatesAutoresizingMaskIntoConstraints = false
        marker.backgroundColor = WatchTheme.mint.withAlphaComponent(0.22)
        marker.layer.cornerRadius = 20
        marker.clipsToBounds = true
        markerAvatar.translatesAutoresizingMaskIntoConstraints = false
        markerAvatar.contentMode = .scaleAspectFill
        marker.addSubview(markerAvatar)
        let pin = WatchTheme.icon(.pin, tint: WatchTheme.blue, size: 22)
        marker.addSubview(pin)
        NSLayoutConstraint.activate([
            marker.widthAnchor.constraint(equalToConstant: 40), marker.heightAnchor.constraint(equalToConstant: 40),
            markerAvatar.leadingAnchor.constraint(equalTo: marker.leadingAnchor, constant: 4), markerAvatar.trailingAnchor.constraint(equalTo: marker.trailingAnchor, constant: -4),
            markerAvatar.topAnchor.constraint(equalTo: marker.topAnchor, constant: 4), markerAvatar.bottomAnchor.constraint(equalTo: marker.bottomAnchor, constant: -4),
            pin.centerXAnchor.constraint(equalTo: marker.centerXAnchor), pin.centerYAnchor.constraint(equalTo: marker.centerYAnchor)
        ])
        view.addSubview(marker)
        NSLayoutConstraint.activate([marker.centerXAnchor.constraint(equalTo: view.centerXAnchor), marker.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 220)])

        let card = locationCard()
        view.addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            card.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -14)
        ])
    }

    private func locationCard() -> UIView {
        let card = WatchTheme.card()

        let header = UIStackView()
        header.axis = .horizontal
        header.addArrangedSubview(WatchTheme.label("watch_bound_watches", size: 12, color: WatchTheme.secondaryText))
        header.addArrangedSubview(UIView())
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.font = .systemFont(ofSize: 12)
        countLabel.textColor = WatchTheme.tertiaryText
        header.addArrangedSubview(countLabel)

        carousel.translatesAutoresizingMaskIntoConstraints = false
        carousel.delegate = self
        carousel.isPagingEnabled = true
        carousel.showsHorizontalScrollIndicator = false
        carousel.alwaysBounceHorizontal = boundWatches.count > 1
        carousel.clipsToBounds = true
        carouselStack.translatesAutoresizingMaskIntoConstraints = false
        carouselStack.axis = .horizontal
        carouselStack.spacing = 0
        carousel.addSubview(carouselStack)
        NSLayoutConstraint.activate([
            carouselStack.leadingAnchor.constraint(equalTo: carousel.contentLayoutGuide.leadingAnchor), carouselStack.trailingAnchor.constraint(equalTo: carousel.contentLayoutGuide.trailingAnchor),
            carouselStack.topAnchor.constraint(equalTo: carousel.contentLayoutGuide.topAnchor), carouselStack.bottomAnchor.constraint(equalTo: carousel.contentLayoutGuide.bottomAnchor),
            carouselStack.heightAnchor.constraint(equalTo: carousel.frameLayoutGuide.heightAnchor)
        ])
        boundWatches.forEach { bound in
            let page = UIView()
            page.translatesAutoresizingMaskIntoConstraints = false
            let content = locationPage(bound)
            content.accessibilityIdentifier = "location.card.\(bound.deviceName)"
            page.addSubview(content)
            carouselStack.addArrangedSubview(page)
            NSLayoutConstraint.activate([
                page.widthAnchor.constraint(equalTo: carousel.frameLayoutGuide.widthAnchor),
                content.leadingAnchor.constraint(equalTo: page.leadingAnchor), content.trailingAnchor.constraint(equalTo: page.trailingAnchor),
                content.topAnchor.constraint(equalTo: page.topAnchor), content.bottomAnchor.constraint(equalTo: page.bottomAnchor)
            ])
        }
        carousel.isHidden = boundWatches.isEmpty

        let empty = WatchTheme.label("watch_call_no_bound_watch", size: 13, color: WatchTheme.secondaryText)
        empty.textAlignment = .center
        empty.isHidden = !boundWatches.isEmpty

        pager.axis = .horizontal
        pager.spacing = 6
        pager.alignment = .center
        pager.distribution = .fill
        pager.translatesAutoresizingMaskIntoConstraints = false
        pager.isHidden = boundWatches.count < 2
        boundWatches.indices.forEach { index in
            let button = UIButton(type: .system)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.accessibilityIdentifier = "location.page.\(index + 1)"
            button.accessibilityLabel = String(format: NSLocalizedString("watch_device_page_description", comment: ""), index + 1, boundWatches.count, boundWatches[index].deviceName)
            button.addAction(UIAction { [weak self] _ in self?.selectDevice(at: index, animated: true) }, for: .touchUpInside)
            let dot = UIView()
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.layer.cornerRadius = 3
            button.addSubview(dot)
            NSLayoutConstraint.activate([button.widthAnchor.constraint(equalToConstant: 32), button.heightAnchor.constraint(equalToConstant: 24), dot.centerXAnchor.constraint(equalTo: button.centerXAnchor), dot.centerYAnchor.constraint(equalTo: button.centerYAnchor), dot.heightAnchor.constraint(equalToConstant: 6)])
            pager.addArrangedSubview(button)
            pagerDots.append(dot)
        }

        let stack = UIStackView(arrangedSubviews: [header, carousel, empty, pager])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 8
        stack.setCustomSpacing(4, after: carousel)
        stack.setCustomSpacing(12, after: pager)
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            carousel.heightAnchor.constraint(equalToConstant: 145), empty.heightAnchor.constraint(equalToConstant: 145), pager.heightAnchor.constraint(equalToConstant: 24),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16), stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14), stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
        ])
        return card
    }

    private func locationPage(_ bound: BoundWatch) -> UIView {
        let avatar = WatchTheme.avatar(textKey: WatchAvatarResolver.key(for: bound.deviceName), color: WatchTheme.mint.withAlphaComponent(0.22), size: 48)
        let info = UIStackView(arrangedSubviews: [WatchTheme.label(bound.deviceName, size: 15, weight: .semibold), WatchTheme.label("watch_location_no_data", size: 12, color: WatchTheme.tertiaryText)])
        info.axis = .vertical
        info.spacing = 4
        let row = UIStackView(arrangedSubviews: [avatar, info, UIView(), WatchTheme.trailingChevronSlot()])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        let address = WatchTheme.label("watch_location_no_data", size: 13, color: WatchTheme.secondaryText)
        let time = WatchTheme.label("watch_location_no_data", size: 11, color: WatchTheme.tertiaryText)
        let stack = UIStackView(arrangedSubviews: [row, address, time])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 8
        return stack
    }

    private func renderSelection() {
        selectedIndex = max(0, min(selectedIndex, max(boundWatches.count - 1, 0)))
        countLabel.text = String(format: NSLocalizedString("watch_device_count_format", comment: ""), boundWatches.isEmpty ? 0 : selectedIndex + 1, boundWatches.count)
        if boundWatches.indices.contains(selectedIndex) {
            let selected = boundWatches[selectedIndex]
            markerAvatar.image = UIImage(named: WatchAvatarResolver.key(for: selected.deviceName).contains("boy") ? "WatchBoyAvatar" : "WatchGirlAvatar")
        } else {
            markerAvatar.image = UIImage(named: "WatchBoyAvatar")
        }
        pagerDots.enumerated().forEach { index, dot in
            dot.backgroundColor = index == selectedIndex ? WatchTheme.blue : WatchTheme.mint
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
}
