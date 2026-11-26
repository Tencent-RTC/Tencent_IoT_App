import UIKit

/// 负责把多个成员头像组合成消息列表使用的头像视图。
enum GroupAvatarComposer {
    static func make(textKeys: [String], backgroundColor: UIColor, size: CGFloat) -> UIView {
        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.backgroundColor = backgroundColor
        wrapper.layer.cornerRadius = size / 2
        wrapper.clipsToBounds = true

        let keys = Array(textKeys.prefix(4))
        let gap = max(1, size * 0.04)
        let cellSize = (size - gap) / 2
        NSLayoutConstraint.activate([
            wrapper.widthAnchor.constraint(equalToConstant: size),
            wrapper.heightAnchor.constraint(equalToConstant: size)
        ])
        for (index, key) in keys.enumerated() {
            let cell = WatchTheme.avatar(textKey: key, color: backgroundColor, size: cellSize)
            let column = CGFloat(index % 2)
            let row = CGFloat(index / 2)
            wrapper.addSubview(cell)
            if keys.count == 3 && index == 0 {
                NSLayoutConstraint.activate([
                    cell.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
                    cell.topAnchor.constraint(equalTo: wrapper.topAnchor)
                ])
            } else {
                NSLayoutConstraint.activate([
                    cell.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: column * (cellSize + gap)),
                    cell.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: row * (cellSize + gap))
                ])
            }
        }
        return wrapper
    }
}
