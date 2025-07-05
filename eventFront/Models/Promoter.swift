import Foundation

struct Promoter: Codable, Identifiable {
    let id: Int
    let referralCode: String
    let user: UserDTO  // 🔥 Add this
}

struct UserDTO: Codable {
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

struct PromoterEvent: Codable, Identifiable {
    let id: Int
    let ticketsSold: Int
    let event: Event?         // Reuse your existing Event model
    let promoter: PromoterDTO?
}
