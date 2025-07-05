struct AdminUser: Identifiable, Codable {
    let id: Int
    let email: String
    let firstName: String
    let lastName: String
}

struct AdminEvent: Identifiable, Codable {
    let id: Int
    let title: String
    let location: String
    let totalTickets: Int
    let soldTickets: Int
    let totalRevenue: Double
}


struct AdminResalePost: Identifiable, Codable {
    let id: Int
    let ticketId: Int
    let price: Double
    let title: String
    let description: String?
    let sellerName: String?
    let eventTitle: String?
    let eventImageUrl: String?
}


