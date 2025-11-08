import Foundation

enum SocialEventKind {
    case followed(userId: Int)              // I followed someone
    case unfollowed(userId: Int)            // I unfollowed someone
    case requestAccepted(followerId: Int)   // I accepted someone (my Followers +1)
    case requestRejected(followerId: Int)   // I rejected someone (no change, but useful)
}

struct SocialEvent { let kind: SocialEventKind }

extension Notification.Name {
    static let socialDidChange = Notification.Name("socialDidChange")
}

enum SocialBus {
    static func post(_ e: SocialEvent) {
        NotificationCenter.default.post(name: .socialDidChange, object: e)
    }
}
