import Foundation

enum ConversationMapper {
    static func direct(peerID: String, displayName: String? = nil, isLocalBinding: Bool) -> MessageConversation {
        MessageConversation(
            key: "c2c_\(peerID)",
            titleKey: "watch_chat_default_title",
            avatarKey: WatchAvatarResolver.key(for: peerID),
            isGroup: false,
            displayTitle: displayName ?? peerID,
            userID: peerID,
            isLocalBinding: isLocalBinding
        )
    }
}
