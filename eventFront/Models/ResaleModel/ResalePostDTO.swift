import Foundation

struct ResalePostDTO: Identifiable, Codable {
    let id: Int
    let ticketId: Int
    let price: Double
    let title: String
    let description: String?
    let sellerName: String
    let eventTitle: String
    let eventImageUrl: String?
    let unreadMessages: Int?
    let eventId: Int
    let sold: Bool  // ✅ NEW FIELD

}
