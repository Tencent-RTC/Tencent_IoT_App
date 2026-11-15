import UIKit

struct MessageConversation {
    let key: String
    let titleKey: String
    let avatarKey: String
    let isGroup: Bool
    var displayTitle: String?
    var preview: String?
    var timestamp: Date?
    var unreadCount: Int
    var isPinned: Bool
    var isMuted: Bool
    var userID: String?
    var groupID: String?
    var isLocalBinding: Bool
    var groupAvatarKeys: [String]

    init(
        key: String,
        titleKey: String,
        avatarKey: String,
        isGroup: Bool,
        displayTitle: String? = nil,
        preview: String? = nil,
        timestamp: Date? = nil,
        unreadCount: Int = 0,
        isPinned: Bool = false,
        isMuted: Bool = false,
        userID: String? = nil,
        groupID: String? = nil,
        isLocalBinding: Bool = false,
        groupAvatarKeys: [String] = []
    ) {
        self.key = key
        self.titleKey = titleKey
        self.avatarKey = avatarKey
        self.isGroup = isGroup
        self.displayTitle = displayTitle
        self.preview = preview
        self.timestamp = timestamp
        self.unreadCount = unreadCount
        self.isPinned = isPinned
        self.isMuted = isMuted
        self.userID = userID
        self.groupID = groupID
        self.isLocalBinding = isLocalBinding
        self.groupAvatarKeys = groupAvatarKeys
    }
}
