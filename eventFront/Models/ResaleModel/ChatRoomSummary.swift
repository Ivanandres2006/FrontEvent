import Foundation

struct ChatRoomSummary: Identifiable, Codable, Hashable {
    var chatRoomId: Int           // 👈 Make sure this comes from backend
    var resalePostId: Int
    var title: String
    var sellerName: String
    var unreadMessages: Int?

    var id: Int { chatRoomId }    // ✅ Now guaranteed unique
}
