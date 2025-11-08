


import Foundation

struct MyListingDTO: Identifiable, Codable {
    let id: Int
    let title: String?
    let eventTitle: String?
    let price: Double
    let sold: Bool
    let createdAt: String?
    let pendingManualOrders: Int
}
