import Foundation

struct TicketDTO: Identifiable, Codable {
    let id: Int
    let quantity: Int
    let status: String
    let qrCodeUrl: String?
    let tierName: String?
    let eventTitle: String?
    let eventId: Int
    let resold: Bool

    let buyerFirstName: String
    let buyerLastName: String
    let buyerUsername: String
    let buyerEmail: String
    var paid: Bool
    let paymentMethod: String

    enum CodingKeys: String, CodingKey {
        case id, quantity, status, qrCodeUrl, tierName, eventTitle, eventId, resold
        case buyerFirstName, buyerLastName, buyerUsername, buyerEmail, paid, paymentMethod
    }
}

