import Foundation

// Models used by the admin dashboard (match AdminController DTOs)
struct AdminUser: Identifiable, Decodable {
    let id: Int
    let email: String
    let firstName: String
    let lastName: String
    var canCreateEvents: Bool
    var role: String? = nil        // backend doesn’t send role; keep optional
}

struct AdminEvent: Identifiable, Decodable {
    let id: Int
    let title: String
    let location: String
    let totalTickets: Int
    let soldTickets: Int
    let totalRevenue: Double
}

struct AdminResalePost: Identifiable, Decodable {
    let id: Int
    let title: String
    let description: String?
    let price: Double?
    let sold: Bool?
    let ticketId: Int?
    let sellerEmail: String?
    let createdAt: String?         // keep String to avoid date decode issues
}
