import Foundation

/// Backend DTO for the dashboard endpoint:
/// GET /api/promoters/event/{eventId}/dashboard
struct PromoterEventView: Codable, Identifiable {
    let id: Int
    let promoter: PromoterSummary
    let ticketsSold: Int

    // Optional extras (present if your backend includes them)
    let grossRevenue: Double?
    let commissionEnabled: Bool?
    let commissionRate: Double?
    let commissionEarned: Double?

    struct PromoterSummary: Codable {
        let id: Int
        let user: UserSummary
    }

    struct UserSummary: Codable {
        let id: Int
        let username: String?
        let fullName: String
    }
}
