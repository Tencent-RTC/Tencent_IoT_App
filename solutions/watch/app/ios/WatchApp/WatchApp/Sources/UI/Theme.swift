import UIKit

enum WatchIconKind {
    case message, pin, phone, hangup, device, user, link, users, watch, profile, search, plus, more, emoji, keyboard, voice, mic, speaker, flip, home, grid, lock, eye, video, bag, refresh, navigation, locator, shield, bell, info, back, chevron, check, group, avatar, scan, appid, batterySave
}

final class WatchIconView: UIView {
    let kind: WatchIconKind
    var tintColorValue: UIColor

    init(_ kind: WatchIconKind, tint: UIColor = WatchTheme.secondaryText) {
        self.kind = kind
        self.tintColorValue = tint
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        let path = UIBezierPath()
        path.lineWidth = max(1.5, rect.width * 0.075)
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        let inset = rect.width * 0.2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let iconScale = min(rect.width, rect.height) / 24
        let iconOrigin = CGPoint(x: rect.midX - 12 * iconScale, y: rect.midY - 12 * iconScale)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: iconOrigin.x + x * iconScale, y: iconOrigin.y + y * iconScale) }
        switch kind {
        case .message:
            path.move(to: CGPoint(x: inset, y: inset + 2)); path.addLine(to: CGPoint(x: rect.maxX - inset, y: inset + 2)); path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset - 2)); path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - inset - 2)); path.addLine(to: CGPoint(x: inset + 2, y: rect.maxY - inset + 3)); path.close()
        case .pin:
            path.move(to: CGPoint(x: center.x, y: rect.maxY - inset)); path.addCurve(to: CGPoint(x: center.x, y: inset), controlPoint1: CGPoint(x: rect.maxX - inset, y: rect.midY + 2), controlPoint2: CGPoint(x: rect.maxX - inset, y: inset)); path.addCurve(to: CGPoint(x: center.x, y: rect.maxY - inset), controlPoint1: CGPoint(x: inset, y: inset), controlPoint2: CGPoint(x: inset, y: rect.midY + 2)); path.close(); UIColor.clear.setFill(); path.fill(); UIBezierPath(ovalIn: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4)).fill()
        case .phone:
            path.move(to: point(5, 4)); path.addLine(to: point(9, 4)); path.addLine(to: point(11, 9)); path.addLine(to: point(9, 11)); path.addCurve(to: point(15, 17), controlPoint1: point(10, 13), controlPoint2: point(13, 16)); path.addLine(to: point(17, 15)); path.addLine(to: point(22, 17)); path.addLine(to: point(22, 21)); path.addCurve(to: point(20, 23), controlPoint1: point(22, 23), controlPoint2: point(21, 23)); path.addCurve(to: point(2, 6), controlPoint1: point(8, 22), controlPoint2: point(2, 14)); path.addCurve(to: point(5, 4), controlPoint1: point(2, 4), controlPoint2: point(3, 4)); path.close()
        case .hangup:
            path.move(to: CGPoint(x: inset - 1, y: rect.maxY - inset)); path.addLine(to: CGPoint(x: inset - 1, y: center.y + 1)); path.addCurve(to: CGPoint(x: rect.maxX - inset + 1, y: center.y + 1), controlPoint1: CGPoint(x: center.x - 7, y: center.y - 8), controlPoint2: CGPoint(x: center.x + 7, y: center.y - 8)); path.addLine(to: CGPoint(x: rect.maxX - inset + 1, y: rect.maxY - inset)); path.addLine(to: CGPoint(x: rect.maxX - inset - 3, y: rect.maxY - inset)); path.addLine(to: CGPoint(x: rect.maxX - inset - 5, y: center.y + 7)); path.addLine(to: CGPoint(x: inset + 5, y: center.y + 7)); path.addLine(to: CGPoint(x: inset + 3, y: rect.maxY - inset)); path.close()
        case .device:
            path.append(UIBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset * 0.65), cornerRadius: 3)); path.move(to: CGPoint(x: center.x - 3, y: rect.maxY - inset * 0.55)); path.addLine(to: CGPoint(x: center.x + 3, y: rect.maxY - inset * 0.55))
        case .user:
            path.append(UIBezierPath(ovalIn: CGRect(x: point(8, 3).x, y: point(8, 3).y, width: 8 * iconScale, height: 8 * iconScale)))
            path.move(to: point(4, 21)); path.addCurve(to: point(20, 21), controlPoint1: point(5, 14), controlPoint2: point(19, 14))
        case .link:
            path.move(to: point(10, 13)); path.addCurve(to: point(17, 13), controlPoint1: point(12, 15), controlPoint2: point(15, 15)); path.addLine(to: point(20, 10)); path.addCurve(to: point(13, 3), controlPoint1: point(22, 8), controlPoint2: point(18, 1)); path.addLine(to: point(11, 5)); path.move(to: point(14, 11)); path.addCurve(to: point(7, 11), controlPoint1: point(12, 9), controlPoint2: point(9, 9)); path.addLine(to: point(4, 14)); path.addCurve(to: point(11, 21), controlPoint1: point(2, 16), controlPoint2: point(6, 23)); path.addLine(to: point(13, 19))
        case .users:
            path.append(UIBezierPath(ovalIn: CGRect(x: point(5, 3).x, y: point(5, 3).y, width: 8 * iconScale, height: 8 * iconScale))); path.move(to: point(2, 21)); path.addLine(to: point(2, 19)); path.addCurve(to: point(16, 19), controlPoint1: point(3, 12), controlPoint2: point(15, 12)); path.addLine(to: point(16, 21)); path.move(to: point(16, 3)); path.addCurve(to: point(16, 11), controlPoint1: point(20, 4), controlPoint2: point(20, 10)); path.move(to: point(19, 15)); path.addCurve(to: point(22, 21), controlPoint1: point(22, 17), controlPoint2: point(22, 20))
        case .watch:
            path.move(to: point(9, 3)); path.addLine(to: point(15, 3)); path.addLine(to: point(16, 7)); path.addLine(to: point(8, 7)); path.close(); path.move(to: point(8, 17)); path.addLine(to: point(16, 17)); path.addLine(to: point(15, 21)); path.addLine(to: point(9, 21)); path.close(); path.append(UIBezierPath(rect: CGRect(x: point(5, 7).x, y: point(5, 7).y, width: 14 * iconScale, height: 10 * iconScale)));
        case .scan:
            path.move(to: point(4, 9)); path.addLine(to: point(4, 5)); path.addCurve(to: point(5, 4), controlPoint1: point(4, 4), controlPoint2: point(5, 4)); path.addLine(to: point(9, 4)); path.move(to: point(15, 4)); path.addLine(to: point(19, 4)); path.addCurve(to: point(20, 5), controlPoint1: point(20, 4), controlPoint2: point(20, 5)); path.addLine(to: point(20, 9)); path.move(to: point(20, 15)); path.addLine(to: point(20, 19)); path.addCurve(to: point(19, 20), controlPoint1: point(20, 20), controlPoint2: point(19, 20)); path.addLine(to: point(15, 20)); path.move(to: point(9, 20)); path.addLine(to: point(5, 20)); path.addCurve(to: point(4, 19), controlPoint1: point(4, 20), controlPoint2: point(4, 19)); path.addLine(to: point(4, 15)); path.append(UIBezierPath(rect: CGRect(x: point(9, 9).x, y: point(9, 9).y, width: 6 * iconScale, height: 6 * iconScale)))
        case .appid:
            [CGRect(x: point(4, 4).x, y: point(4, 4).y, width: 6 * iconScale, height: 6 * iconScale), CGRect(x: point(14, 4).x, y: point(14, 4).y, width: 6 * iconScale, height: 6 * iconScale), CGRect(x: point(4, 14).x, y: point(4, 14).y, width: 6 * iconScale, height: 6 * iconScale), CGRect(x: point(14, 14).x, y: point(14, 14).y, width: 6 * iconScale, height: 6 * iconScale)].forEach { path.append(UIBezierPath(rect: $0)) }
        case .batterySave:
            path.append(UIBezierPath(rect: CGRect(x: point(3, 8).x, y: point(3, 8).y, width: 15 * iconScale, height: 8 * iconScale))); path.append(UIBezierPath(rect: CGRect(x: point(18, 10.5).x, y: point(18, 10.5).y, width: 2.5 * iconScale, height: 3 * iconScale))); path.move(to: point(10.5, 9.5)); path.addLine(to: point(8.5, 12.5)); path.addLine(to: point(11.5, 12.5)); path.addLine(to: point(9.5, 15.5))
        case .profile, .avatar:
            path.append(UIBezierPath(ovalIn: CGRect(x: center.x - 4, y: inset, width: 8, height: 8))); path.move(to: CGPoint(x: inset, y: rect.maxY - inset)); path.addCurve(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset), controlPoint1: CGPoint(x: inset + 1, y: center.y + 6), controlPoint2: CGPoint(x: rect.maxX - inset - 1, y: center.y + 6))
        case .search:
            path.append(UIBezierPath(ovalIn: CGRect(x: inset, y: inset, width: rect.width * 0.42, height: rect.width * 0.42))); path.move(to: CGPoint(x: rect.width * 0.56, y: rect.width * 0.56)); path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset))
        case .plus:
            path.move(to: CGPoint(x: center.x, y: inset)); path.addLine(to: CGPoint(x: center.x, y: rect.maxY - inset)); path.move(to: CGPoint(x: inset, y: center.y)); path.addLine(to: CGPoint(x: rect.maxX - inset, y: center.y))
        case .more:
            [center.x - 7, center.x, center.x + 7].forEach { x in path.append(UIBezierPath(ovalIn: CGRect(x: x - 1.4, y: center.y - 1.4, width: 2.8, height: 2.8))) }; path.fill()
        case .emoji:
            path.append(UIBezierPath(ovalIn: rect.insetBy(dx: inset * 0.45, dy: inset * 0.45))); path.move(to: CGPoint(x: center.x - 4.5, y: center.y - 1)); path.addLine(to: CGPoint(x: center.x - 3.5, y: center.y - 1)); path.move(to: CGPoint(x: center.x + 3.5, y: center.y - 1)); path.addLine(to: CGPoint(x: center.x + 4.5, y: center.y - 1)); path.move(to: CGPoint(x: center.x - 5, y: center.y + 4)); path.addCurve(to: CGPoint(x: center.x + 5, y: center.y + 4), controlPoint1: CGPoint(x: center.x - 2, y: center.y + 8), controlPoint2: CGPoint(x: center.x + 2, y: center.y + 8))
        case .keyboard:
            path.append(UIBezierPath(roundedRect: CGRect(x: inset * 0.5, y: rect.height * 0.28, width: rect.width - inset, height: rect.height * 0.44), cornerRadius: 2)); for row in 0..<2 { for column in 0..<5 { let x = rect.width * (0.29 + CGFloat(column) * 0.12); let y = rect.height * (0.42 + CGFloat(row) * 0.14); path.append(UIBezierPath(ovalIn: CGRect(x: x, y: y, width: 1.4, height: 1.4))) } }; path.move(to: CGPoint(x: rect.width * 0.35, y: rect.height * 0.65)); path.addLine(to: CGPoint(x: rect.width * 0.65, y: rect.height * 0.65))
        case .voice:
            path.append(UIBezierPath(ovalIn: rect.insetBy(dx: inset * 0.45, dy: inset * 0.45))); for (x, height) in [(center.x - 5, 5.0), (center.x, 9.0), (center.x + 5, 6.5)] { path.move(to: CGPoint(x: x, y: center.y - height / 2)); path.addLine(to: CGPoint(x: x, y: center.y + height / 2)) }
        case .mic:
            path.append(UIBezierPath(roundedRect: CGRect(x: center.x - 4.5, y: inset, width: 9, height: rect.height * 0.48), cornerRadius: 4.5)); path.move(to: CGPoint(x: inset + 3, y: center.y)); path.addCurve(to: CGPoint(x: rect.maxX - inset - 3, y: center.y), controlPoint1: CGPoint(x: inset + 3, y: center.y + 8), controlPoint2: CGPoint(x: rect.maxX - inset - 3, y: center.y + 8)); path.move(to: CGPoint(x: center.x, y: center.y + 8)); path.addLine(to: CGPoint(x: center.x, y: rect.maxY - inset)); path.move(to: CGPoint(x: center.x - 5, y: rect.maxY - inset)); path.addLine(to: CGPoint(x: center.x + 5, y: rect.maxY - inset))
        case .speaker:
            path.move(to: point(4, 10)); path.addLine(to: point(8, 10)); path.addLine(to: point(13, 6)); path.addLine(to: point(13, 18)); path.addLine(to: point(8, 14)); path.addLine(to: point(4, 14)); path.close(); path.move(to: point(16, 9)); path.addCurve(to: point(16, 15), controlPoint1: point(19, 10), controlPoint2: point(19, 14)); path.move(to: point(19, 6)); path.addCurve(to: point(19, 18), controlPoint1: point(23, 8), controlPoint2: point(23, 16))
        case .flip:
            path.move(to: point(5, 8)); path.addLine(to: point(8, 5)); path.addLine(to: point(8, 8)); path.addLine(to: point(18, 8)); path.addLine(to: point(18, 5)); path.addLine(to: point(21, 8)); path.addLine(to: point(18, 11)); path.addLine(to: point(18, 9)); path.addLine(to: point(8, 9)); path.addLine(to: point(8, 11)); path.close(); path.move(to: point(5, 16)); path.addLine(to: point(8, 13)); path.addLine(to: point(8, 15)); path.addLine(to: point(18, 15)); path.addLine(to: point(18, 13)); path.addLine(to: point(21, 16)); path.addLine(to: point(18, 19)); path.addLine(to: point(18, 17)); path.addLine(to: point(8, 17)); path.addLine(to: point(8, 19)); path.close()
        case .home:
            path.move(to: CGPoint(x: inset, y: center.y)); path.addLine(to: CGPoint(x: center.x, y: inset)); path.addLine(to: CGPoint(x: rect.maxX - inset, y: center.y)); path.move(to: CGPoint(x: inset + 3, y: center.y)); path.addLine(to: CGPoint(x: inset + 3, y: rect.maxY - inset)); path.addLine(to: CGPoint(x: rect.maxX - inset - 3, y: rect.maxY - inset)); path.addLine(to: CGPoint(x: rect.maxX - inset - 3, y: center.y))
        case .grid:
            for x in [inset, center.x, rect.maxX - inset] { path.move(to: CGPoint(x: x, y: inset)); path.addLine(to: CGPoint(x: x, y: rect.maxY - inset)) }; for y in [inset, center.y, rect.maxY - inset] { path.move(to: CGPoint(x: inset, y: y)); path.addLine(to: CGPoint(x: rect.maxX - inset, y: y)) }
        case .lock:
            path.append(UIBezierPath(roundedRect: CGRect(x: inset, y: center.y - 1, width: rect.width - inset * 2, height: rect.height * 0.35), cornerRadius: 2)); path.addArc(withCenter: CGPoint(x: center.x, y: center.y - 1), radius: rect.width * 0.22, startAngle: .pi, endAngle: 0, clockwise: true)
        case .eye:
            path.move(to: CGPoint(x: inset, y: center.y)); path.addCurve(to: CGPoint(x: rect.maxX - inset, y: center.y), controlPoint1: CGPoint(x: center.x - 8, y: inset), controlPoint2: CGPoint(x: center.x + 8, y: inset)); path.addCurve(to: CGPoint(x: inset, y: center.y), controlPoint1: CGPoint(x: center.x + 8, y: rect.maxY - inset), controlPoint2: CGPoint(x: center.x - 8, y: rect.maxY - inset)); path.append(UIBezierPath(ovalIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)))
        case .video:
            path.append(UIBezierPath(roundedRect: CGRect(x: inset, y: center.y - 5, width: rect.width * 0.48, height: 10), cornerRadius: 2)); path.move(to: CGPoint(x: rect.width * 0.62, y: center.y - 4)); path.addLine(to: CGPoint(x: rect.maxX - inset, y: center.y - 8)); path.addLine(to: CGPoint(x: rect.maxX - inset, y: center.y + 8)); path.addLine(to: CGPoint(x: rect.width * 0.62, y: center.y + 4))
        case .bag:
            path.append(UIBezierPath(roundedRect: CGRect(x: inset, y: center.y - 3, width: rect.width - inset * 2, height: rect.height * 0.35), cornerRadius: 2)); path.addArc(withCenter: CGPoint(x: center.x, y: center.y - 3), radius: 4, startAngle: .pi, endAngle: 0, clockwise: true)
        case .refresh:
            path.append(UIBezierPath(arcCenter: center, radius: rect.width * 0.28, startAngle: -.pi * 0.75, endAngle: .pi * 0.9, clockwise: true)); path.move(to: CGPoint(x: rect.maxX - inset, y: center.y - 6)); path.addLine(to: CGPoint(x: rect.maxX - inset, y: center.y + 2)); path.addLine(to: CGPoint(x: rect.maxX - inset - 7, y: center.y))
        case .navigation:
            path.move(to: CGPoint(x: center.x, y: inset)); path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset)); path.addLine(to: CGPoint(x: center.x, y: center.y + 3)); path.addLine(to: CGPoint(x: inset, y: rect.maxY - inset)); path.close()
        case .locator:
            path.append(UIBezierPath(ovalIn: rect.insetBy(dx: inset, dy: inset))); path.move(to: CGPoint(x: center.x, y: inset - 2)); path.addLine(to: CGPoint(x: center.x, y: inset + 5)); path.move(to: CGPoint(x: center.x, y: rect.maxY - inset - 5)); path.addLine(to: CGPoint(x: center.x, y: rect.maxY - inset + 2)); path.move(to: CGPoint(x: inset - 2, y: center.y)); path.addLine(to: CGPoint(x: inset + 5, y: center.y)); path.move(to: CGPoint(x: rect.maxX - inset - 5, y: center.y)); path.addLine(to: CGPoint(x: rect.maxX - inset + 2, y: center.y))
        case .shield:
            path.move(to: CGPoint(x: center.x, y: inset)); path.addLine(to: CGPoint(x: rect.maxX - inset, y: inset + 3)); path.addLine(to: CGPoint(x: rect.maxX - inset - 2, y: center.y + 5)); path.addCurve(to: CGPoint(x: center.x, y: rect.maxY - inset), controlPoint1: CGPoint(x: rect.maxX - inset - 3, y: rect.maxY - inset - 2), controlPoint2: CGPoint(x: center.x + 3, y: rect.maxY - inset)); path.addCurve(to: CGPoint(x: inset + 2, y: center.y + 5), controlPoint1: CGPoint(x: center.x - 3, y: rect.maxY - inset), controlPoint2: CGPoint(x: inset + 3, y: rect.maxY - inset - 2)); path.addLine(to: CGPoint(x: inset, y: inset + 3)); path.close()
        case .bell:
            path.addArc(withCenter: CGPoint(x: center.x, y: center.y), radius: rect.width * 0.26, startAngle: .pi, endAngle: 0, clockwise: false); path.move(to: CGPoint(x: inset + 2, y: center.y + 5)); path.addLine(to: CGPoint(x: rect.maxX - inset - 2, y: center.y + 5)); path.move(to: CGPoint(x: center.x - 2, y: rect.maxY - inset)); path.addLine(to: CGPoint(x: center.x + 2, y: rect.maxY - inset))
        case .info:
            path.append(UIBezierPath(ovalIn: rect.insetBy(dx: inset, dy: inset))); path.move(to: CGPoint(x: center.x, y: center.y - 1)); path.addLine(to: CGPoint(x: center.x, y: center.y + 7)); path.move(to: CGPoint(x: center.x, y: center.y - 6)); path.addLine(to: CGPoint(x: center.x, y: center.y - 6))
        case .back:
            path.move(to: point(14.5, 5.5)); path.addLine(to: point(8.5, 12)); path.addLine(to: point(14.5, 18.5))
        case .chevron:
            path.move(to: CGPoint(x: inset, y: inset)); path.addLine(to: CGPoint(x: rect.maxX - inset, y: center.y)); path.addLine(to: CGPoint(x: inset, y: rect.maxY - inset))
        case .check:
            path.move(to: CGPoint(x: rect.width * 0.22, y: rect.height * 0.52)); path.addLine(to: CGPoint(x: rect.width * 0.43, y: rect.height * 0.73)); path.addLine(to: CGPoint(x: rect.width * 0.8, y: rect.height * 0.3))
        case .group:
            path.append(UIBezierPath(ovalIn: CGRect(x: center.x - 5, y: inset, width: 10, height: 10))); path.move(to: CGPoint(x: inset, y: rect.maxY - inset)); path.addCurve(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset), controlPoint1: CGPoint(x: inset + 1, y: center.y + 7), controlPoint2: CGPoint(x: rect.maxX - inset - 1, y: center.y + 7))
        }
        tintColorValue.setStroke(); tintColorValue.setFill(); if kind == .hangup { path.fill() }; path.stroke()
    }
}

final class WatchGradientView: UIView {
    let gradient = CAGradientLayer()
    override init(frame: CGRect) { super.init(frame: frame); translatesAutoresizingMaskIntoConstraints = false; layer.insertSublayer(gradient, at: 0); gradient.colors = [WatchTheme.blue.cgColor, WatchTheme.purple.cgColor]; gradient.startPoint = CGPoint(x: 0, y: 0); gradient.endPoint = CGPoint(x: 1, y: 1) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() { super.layoutSubviews(); gradient.frame = bounds; gradient.cornerRadius = layer.cornerRadius }
}

final class WatchTabItemView: UIButton {
    private let icon: WatchIconView
    private let title: UILabel
    init(title titleKey: String, iconKind: WatchIconKind) {
        icon = WatchIconView(iconKind)
        title = UILabel()
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = true
        adjustsImageWhenHighlighted = false
        contentHorizontalAlignment = .center
        contentVerticalAlignment = .center
        title.text = NSLocalizedString(titleKey, comment: "")
        isAccessibilityElement = true
        accessibilityLabel = title.text
        accessibilityTraits = .button
        title.font = .systemFont(ofSize: 12, weight: .medium)
        title.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [icon, title])
        stack.translatesAutoresizingMaskIntoConstraints = false; stack.axis = .vertical; stack.alignment = .center; stack.spacing = 3; stack.isUserInteractionEnabled = false
        addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: centerXAnchor), stack.centerYAnchor.constraint(equalTo: centerYAnchor), icon.widthAnchor.constraint(equalToConstant: 24), icon.heightAnchor.constraint(equalToConstant: 24)])
        isSelected = false
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isSelected: Bool { didSet { let color = isSelected ? WatchTheme.blue : WatchTheme.secondaryText; icon.tintColorValue = color; icon.setNeedsDisplay(); title.textColor = color; backgroundColor = .clear } }
    override func accessibilityActivate() -> Bool { sendActions(for: .touchUpInside); return true }
}

final class WatchActionControl: UIControl {
    var activationHandler: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
        isExclusiveTouch = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func accessibilityActivate() -> Bool {
        activationHandler?()
        sendActions(for: .touchUpInside)
        return true
    }
}

final class WatchBackButton: UIButton {
    override var isHighlighted: Bool {
        didSet {
            backgroundColor = isHighlighted ? WatchTheme.surfaceStrong : .clear
        }
    }

    override func accessibilityActivate() -> Bool {
        sendActions(for: .touchUpInside)
        return true
    }
}

final class WatchDashedBorderButton: UIButton {
    private let borderLayer = CAShapeLayer()

    init() {
        super.init(frame: .zero)
        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.strokeColor = WatchTheme.tertiaryText.cgColor
        borderLayer.lineWidth = 1
        borderLayer.lineDashPattern = [4, 4]
        layer.addSublayer(borderLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        borderLayer.frame = bounds
        borderLayer.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 14).cgPath
    }
}

enum WatchTheme {
    static let background = UIColor(red: 0.965, green: 0.965, blue: 1, alpha: 1)
    static let surface = UIColor.white
    static let surfaceStrong = UIColor(red: 0.945, green: 0.949, blue: 0.98, alpha: 1)
    static let primaryText = UIColor(red: 0.125, green: 0.149, blue: 0.227, alpha: 1)
    static let secondaryText = UIColor(red: 0.541, green: 0.565, blue: 0.635, alpha: 1)
    static let callSecondaryText = UIColor(red: 0.773, green: 0.839, blue: 0.937, alpha: 1)
    static let tertiaryText = UIColor(red: 0.659, green: 0.678, blue: 0.733, alpha: 1)
    static let blue = UIColor(red: 0.353, green: 0.404, blue: 0.949, alpha: 1)
    static let purple = UIColor(red: 0.486, green: 0.345, blue: 0.961, alpha: 1)
    static let mint = UIColor(red: 0.263, green: 0.749, blue: 0.643, alpha: 1)
    static let red = UIColor(red: 0.89, green: 0.42, blue: 0.45, alpha: 1)
    static let line = UIColor(red: 0.902, green: 0.91, blue: 0.953, alpha: 1)
    static let lavender = UIColor(red: 0.933, green: 0.937, blue: 1, alpha: 1)
    static let addSectionText = UIColor(red: 0.29, green: 0.325, blue: 0.447, alpha: 1)
    static let addDivider = UIColor(red: 0.945, green: 0.953, blue: 0.969, alpha: 1)

    static func label(_ key: String, size: CGFloat, weight: UIFont.Weight = .regular, color: UIColor = primaryText) -> UILabel {
        let label = UILabel(); label.translatesAutoresizingMaskIntoConstraints = false; label.text = NSLocalizedString(key, comment: ""); label.font = .systemFont(ofSize: size, weight: weight); label.textColor = color; label.numberOfLines = 0; return label
    }

    static func button(_ key: String, filled: Bool = false, color: UIColor? = nil) -> UIButton {
        let button = UIButton(type: .system); button.translatesAutoresizingMaskIntoConstraints = false; button.setTitle(NSLocalizedString(key, comment: ""), for: .normal); button.setTitleColor(color ?? (filled ? surface : primaryText), for: .normal); button.titleLabel?.font = .systemFont(ofSize: 14, weight: filled ? .semibold : .regular); button.backgroundColor = filled ? blue : surface; button.layer.cornerRadius = 15; button.layer.borderWidth = filled ? 0 : 1; button.layer.borderColor = line.cgColor; button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14); return button
    }

    static func backButton(identifier: String? = nil, label: String, tint: UIColor = primaryText, action: @escaping () -> Void) -> WatchBackButton {
        let button = WatchBackButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityIdentifier = identifier
        button.accessibilityLabel = label
        button.tintColor = tint
        button.contentHorizontalAlignment = .center
        button.contentVerticalAlignment = .center
        button.adjustsImageWhenHighlighted = false
        button.layer.cornerRadius = 22
        button.accessibilityTraits = .button
        let icon = WatchTheme.icon(.back, tint: tint, size: 24)
        button.addSubview(icon)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 44),
            button.heightAnchor.constraint(equalToConstant: 44),
            icon.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    static func icon(_ kind: WatchIconKind, tint: UIColor = secondaryText, size: CGFloat = 22) -> WatchIconView { let view = WatchIconView(kind, tint: tint); NSLayoutConstraint.activate([view.widthAnchor.constraint(equalToConstant: size), view.heightAnchor.constraint(equalToConstant: size)]); return view }
    static func trailingChevronSlot(tint: UIColor = tertiaryText) -> UIView {
        let slot = UIView(); slot.translatesAutoresizingMaskIntoConstraints = false
        let chevron = WatchIconView(.chevron, tint: tint); slot.addSubview(chevron)
        NSLayoutConstraint.activate([
            slot.widthAnchor.constraint(equalToConstant: 24),
            chevron.centerXAnchor.constraint(equalTo: slot.centerXAnchor),
            chevron.centerYAnchor.constraint(equalTo: slot.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 12),
            chevron.heightAnchor.constraint(equalToConstant: 20)
        ])
        return slot
    }
    static func card() -> UIView { let view = UIView(); view.translatesAutoresizingMaskIntoConstraints = false; view.backgroundColor = surface; view.layer.cornerRadius = 18; view.layer.shadowColor = UIColor.black.withAlphaComponent(0.04).cgColor; view.layer.shadowOpacity = 1; view.layer.shadowRadius = 10; view.layer.shadowOffset = CGSize(width: 0, height: 4); return view }
    static func gradientCard() -> UIView { let view = WatchGradientView(); view.translatesAutoresizingMaskIntoConstraints = false; view.layer.cornerRadius = 20; view.clipsToBounds = true; return view }
    static func avatar(textKey: String, color: UIColor, size: CGFloat) -> UIView {
        let wrapper = UIView(); wrapper.translatesAutoresizingMaskIntoConstraints = false; wrapper.backgroundColor = color; wrapper.layer.cornerRadius = size / 2; wrapper.clipsToBounds = true
        if textKey.contains("dad") {
            let image = UIImageView(image: UIImage(named: "WatchDadAvatar")); image.translatesAutoresizingMaskIntoConstraints = false; image.contentMode = .scaleAspectFill; wrapper.addSubview(image)
            NSLayoutConstraint.activate([wrapper.widthAnchor.constraint(equalToConstant: size), wrapper.heightAnchor.constraint(equalToConstant: size), image.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor), image.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor), image.topAnchor.constraint(equalTo: wrapper.topAnchor), image.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor)])
            return wrapper
        }
        if textKey.contains("boy") || textKey.contains("lele") {
            return imageAvatar(named: "WatchBoyAvatar", wrapper: wrapper, size: size)
        }
        if textKey.contains("girl") || textKey.contains("xiaoya") || textKey.contains("mom") || textKey.contains("device") {
            return imageAvatar(named: "WatchGirlAvatar", wrapper: wrapper, size: size)
        }
        let kind: WatchIconKind = textKey.contains("group") || textKey.contains("family") ? .group : .avatar; let icon = WatchIconView(kind, tint: primaryText); wrapper.addSubview(icon); icon.translatesAutoresizingMaskIntoConstraints = false; NSLayoutConstraint.activate([wrapper.widthAnchor.constraint(equalToConstant: size), wrapper.heightAnchor.constraint(equalToConstant: size), icon.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor), icon.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor), icon.widthAnchor.constraint(equalToConstant: size * 0.52), icon.heightAnchor.constraint(equalToConstant: size * 0.52)]); return wrapper
    }

    private static func imageAvatar(named name: String, wrapper: UIView, size: CGFloat) -> UIView {
        let image = UIImageView(image: UIImage(named: name)); image.translatesAutoresizingMaskIntoConstraints = false; image.contentMode = .scaleAspectFill; wrapper.addSubview(image)
        NSLayoutConstraint.activate([wrapper.widthAnchor.constraint(equalToConstant: size), wrapper.heightAnchor.constraint(equalToConstant: size), image.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor), image.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor), image.topAnchor.constraint(equalTo: wrapper.topAnchor), image.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor)])
        return wrapper
    }
}

extension UIViewController {
    func attachChild(_ child: UIViewController, to container: UIView) { addChild(child); container.addSubview(child.view); child.view.translatesAutoresizingMaskIntoConstraints = false; NSLayoutConstraint.activate([child.view.leadingAnchor.constraint(equalTo: container.leadingAnchor), child.view.trailingAnchor.constraint(equalTo: container.trailingAnchor), child.view.topAnchor.constraint(equalTo: container.topAnchor), child.view.bottomAnchor.constraint(equalTo: container.bottomAnchor)]); child.didMove(toParent: self) }

    func installWatchSystemBottomBar() {
        let bottomBar = UIView()
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.backgroundColor = WatchTheme.surface
        bottomBar.isUserInteractionEnabled = false
        bottomBar.accessibilityElementsHidden = true
        view.addSubview(bottomBar)
        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
