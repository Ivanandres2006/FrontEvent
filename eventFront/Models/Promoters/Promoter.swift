import Foundation



struct UserDTO: Codable {
    let id: Int?            // ← add this
    let firstName: String
    let lastName: String
    let username: String

    var fullName: String {
        "\(firstName.capitalized) \(lastName.capitalized)"
    }
}

struct PromoterDTO: Codable {
    let id: Int
    let referralCode: String
    let user: UserDTO
}

// Keep the rest of the file unchanged; just add these fields
struct PromoterEvent: Codable, Identifiable {
    let id: Int
    let ticketsSold: Int
    let event: Event?
    let promoter: PromoterDTO?

    // 👇 NEW (optional – depends on backend)
    let grossRevenue: Double?

    enum CodingKeys: String, CodingKey {
        case id, ticketsSold, event, promoter
        case grossRevenue
    }
}

