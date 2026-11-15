import Foundation

/// 为绑定设备稳定分配男孩／女孩头像，避免每次重绘随机变化。
enum WatchAvatarResolver {
    static func key(for identity: String) -> String {
        let value = identity.utf8.reduce(0) { ($0 &* 31) &+ Int($1) }
        return value & 1 == 0 ? "watch_avatar_boy" : "watch_avatar_girl"
    }
}
