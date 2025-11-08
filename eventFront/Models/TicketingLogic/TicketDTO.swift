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

    let buyerFirstName: String?
    let buyerLastName: String?
    let buyerUsername: String?
    let buyerEmail: String?
    var paid: Bool
    let paymentMethod: String?

    let used: Bool
    let usedAt: String?
    let scannedBy: String?
    let proofUrl: String?

    // NEW (optional, won’t break old responses)
    let eventDateTime: String?
    let eventCountry: String?
    let resellEligible: Bool?
    
    let unitPrice: Double?

    enum CodingKeys: String, CodingKey {
        case id, quantity, status, qrCodeUrl, tierName, eventTitle, eventId, resold
        case buyerFirstName, buyerLastName, buyerUsername, buyerEmail, paid, paymentMethod
        case used, usedAt, scannedBy, proofUrl
        case eventDateTime, eventCountry, resellEligible, unitPrice
    }
}
