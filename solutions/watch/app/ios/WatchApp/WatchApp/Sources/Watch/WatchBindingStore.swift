import Foundation

struct BoundWatch {
    let productId: String
    let deviceName: String
}

/// 首期本地绑定数据源；设备上线后由服务端绑定接口替换。
enum WatchBindingStore {
    private static let keyPrefix = "watch.binding.deviceName."
    private static let namesKeyPrefix = "watch.binding.deviceNames."

    @discardableResult
    static func bind(deviceName: String, userID: String) -> BoundWatch? {
        let normalized = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        var names = all(userID: userID).map(\.deviceName)
        if !names.contains(normalized) {
            names.append(normalized)
            UserDefaults.standard.set(names, forKey: namesKey(for: userID))
        }
        return BoundWatch(productId: WatchSdkConfig.boundWatchProductId, deviceName: normalized)
    }

    static func all(userID: String?) -> [BoundWatch] {
        let normalizedUserID = userID ?? ""
        let defaults = UserDefaults.standard
        let names: [String]
        if let stored = defaults.array(forKey: namesKey(for: normalizedUserID)) as? [String] {
            names = stored
        } else if let legacy = defaults.string(forKey: key(for: normalizedUserID))?.trimmingCharacters(in: .whitespacesAndNewlines), !legacy.isEmpty {
            names = [legacy]
            defaults.set(names, forKey: namesKey(for: normalizedUserID))
        } else {
            names = []
        }
        var unique: [String] = []
        for name in names {
            let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty, !unique.contains(normalized) { unique.append(normalized) }
        }
        return unique.map { BoundWatch(productId: WatchSdkConfig.boundWatchProductId, deviceName: $0) }
    }

    static func current(userID: String?) -> BoundWatch? {
        all(userID: userID).first
    }

    private static func key(for userID: String) -> String {
        "\(keyPrefix)\(userID.isEmpty ? "anonymous" : userID)"
    }

    private static func namesKey(for userID: String) -> String {
        "\(namesKeyPrefix)\(userID.isEmpty ? "anonymous" : userID)"
    }
}
