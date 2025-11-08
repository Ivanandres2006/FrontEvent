

import Foundation

struct ResaleOrderDTO: Identifiable, Codable {
    let id: Int
    let resalePostId: Int
    let postTitle: String?
    let amount: Double
    let currency: String?
    let method: String?
    let status: String?

    let buyerId: Int?
    let buyerUsername: String?
    let buyerName: String?
    let reference: String?

    let createdAt: String?
}
