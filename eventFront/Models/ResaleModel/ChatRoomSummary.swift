import Foundation

struct ChatRoomSummary: Identifiable, Codable, Hashable {
    var chatRoomId: Int           // 👈 Make sure this comes from backend
    var resalePostId: Int?
    var title: String
    var sellerName: String?
    var unreadMessages: Int?
    var otherUsername: String?
    var buyerId: Int?
    var otherUserId: Int?
    let eventId: Int64?
    let type: String // Add this


    var id: Int { chatRoomId }    // ✅ Now guaranteed unique
}
