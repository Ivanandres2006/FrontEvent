struct EventAnalyticsDTO: Decodable {
    struct SalesData: Decodable {
        let date: String
        let sold: Int
    }

    struct TierBreakdown: Decodable {
        let tier: String
        let sold: Int
    }

    let eventId: Int
    let title: String
    let totalTicketsSold: Int
    let totalTicketsAvailable: Int
    let revenue: Double
    let salesOverTime: [SalesData]
    let ticketTierBreakdown: [TierBreakdown]
}

