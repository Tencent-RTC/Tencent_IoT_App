import Foundation

enum AppDialog: Equatable, Identifiable {
    case endSession
    case leaveSession
    case discardConfirm
    case conflict
    case meetingInfo

    var id: String {
        switch self {
        case .endSession: "end"
        case .leaveSession: "leave"
        case .discardConfirm: "discard"
        case .conflict: "conflict"
        case .meetingInfo: "meeting-info"
        }
    }
}
