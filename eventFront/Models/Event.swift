import Foundation
import CoreLocation

struct Event: Identifiable, Codable {
    let id: Int
    let title: String
    let description: String
    let location: String        // City / venue
    let address: String         // Full street address
    let state: String           // e.g. Illinois
    let country: String         // e.g. USA
    let latitude: Double?       // Optional in case geocoding fails
    let longitude: Double?      // Optional in case geocoding fails
    let dateTime: String
    let imageUrl: String?
    let createdByEmail: String?
    let attendees: [String]
    let ticketTiers: [TicketTier]
    var purchasedTickets: [TicketDTO] = []  // ✅ Local-only, not decoded from backend

    var dateAsDate: Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter.date(from: dateTime)
    }

    enum CodingKeys: String, CodingKey {
        case id, title, description, location, address, state, country,
             latitude, longitude, dateTime, imageUrl, createdByEmail,
             attendees, ticketTiers
        // purchasedTickets is intentionally excluded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        location = try container.decode(String.self, forKey: .location)
        address = try container.decode(String.self, forKey: .address)
        state = try container.decode(String.self, forKey: .state)
        country = try container.decode(String.self, forKey: .country)
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        dateTime = try container.decode(String.self, forKey: .dateTime)
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        createdByEmail = try container.decodeIfPresent(String.self, forKey: .createdByEmail)
        attendees = try container.decodeIfPresent([String].self, forKey: .attendees) ?? []
        ticketTiers = try container.decodeIfPresent([TicketTier].self, forKey: .ticketTiers) ?? []
        purchasedTickets = []  // default local
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(location, forKey: .location)
        try container.encode(address, forKey: .address)
        try container.encode(state, forKey: .state)
        try container.encode(country, forKey: .country)
        try container.encodeIfPresent(latitude, forKey: .latitude)
        try container.encodeIfPresent(longitude, forKey: .longitude)
        try container.encode(dateTime, forKey: .dateTime)
        try container.encodeIfPresent(imageUrl, forKey: .imageUrl)
        try container.encodeIfPresent(createdByEmail, forKey: .createdByEmail)
        try container.encode(attendees, forKey: .attendees)
        try container.encode(ticketTiers, forKey: .ticketTiers)
        // Note: purchasedTickets is not encoded
    }
}

// ✅ Manual Equatable conformance
extension Event: Equatable {
    static func == (lhs: Event, rhs: Event) -> Bool {
        return lhs.id == rhs.id
    }
}
