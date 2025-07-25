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
    let type: String
    let budgetGoal: Double?
    let budgetPurpose: String?
    let zelleEmail: String?
    let zellePhone: String?
    let allowPagoMovil: Bool?
    let allowCash: Bool?
    let pagoMovilPhone: String?
    let pagoMovilCi: String?
    let pagoMovilBank: String?
    let cashNote: String?
    let reunionGuests: [ReunionGuest]?
    let createdBy: UserMini? // 👈 NEW
    var purchasedTickets: [TicketDTO] = []  // ✅ Local-only, not decoded from backend

    var dateAsDate: Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0) // ✅ parse as UTC
        return formatter.date(from: dateTime)
    }

    enum CodingKeys: String, CodingKey {
        case id, title, description, location, address, state, country,
             latitude, longitude, dateTime, imageUrl, createdByEmail,
             attendees, ticketTiers, type,
             budgetGoal, budgetPurpose, zelleEmail, zellePhone, allowPagoMovil, pagoMovilCi, pagoMovilBank, cashNote, pagoMovilPhone, allowCash, reunionGuests,createdBy
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
        type = try container.decode(String.self, forKey: .type)
        budgetGoal = try container.decodeIfPresent(Double.self, forKey: .budgetGoal)
        budgetPurpose = try container.decodeIfPresent(String.self, forKey: .budgetPurpose)
        zelleEmail = try container.decodeIfPresent(String.self, forKey: .zelleEmail)
        zellePhone = try container.decodeIfPresent(String.self, forKey: .zellePhone)
        allowPagoMovil = try container.decodeIfPresent(Bool.self, forKey: .allowPagoMovil)
        allowCash = try container.decodeIfPresent(Bool.self, forKey: .allowCash)
        pagoMovilPhone = try container.decodeIfPresent(String.self, forKey: .pagoMovilPhone)
        pagoMovilCi = try container.decodeIfPresent(String.self, forKey: .pagoMovilCi)
        pagoMovilBank = try container.decodeIfPresent(String.self, forKey: .pagoMovilBank)
        cashNote = try container.decodeIfPresent(String.self, forKey: .cashNote)

        reunionGuests = try container.decodeIfPresent([ReunionGuest].self, forKey: .reunionGuests)
        createdBy = try container.decodeIfPresent(UserMini.self, forKey: .createdBy) // 👈 NEW
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
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(budgetGoal, forKey: .budgetGoal)
        try container.encodeIfPresent(budgetPurpose, forKey: .budgetPurpose)
        try container.encodeIfPresent(zelleEmail, forKey: .zelleEmail)
        try container.encodeIfPresent(zellePhone, forKey: .zellePhone)
        try container.encodeIfPresent(allowPagoMovil, forKey: .allowPagoMovil)
        try container.encodeIfPresent(allowCash, forKey: .allowCash)
        try container.encodeIfPresent(pagoMovilPhone, forKey: .pagoMovilPhone)
        try container.encodeIfPresent(pagoMovilCi, forKey: .pagoMovilCi)
        try container.encodeIfPresent(pagoMovilBank, forKey: .pagoMovilBank)
        try container.encodeIfPresent(cashNote, forKey: .cashNote)
        try container.encodeIfPresent(reunionGuests, forKey: .reunionGuests)
        try container.encodeIfPresent(createdBy, forKey: .createdBy) // 👈 NEW
        try container.encode(ticketTiers, forKey: .ticketTiers)
        // Note: purchasedTickets is not encoded
    }
    
    init(id: Int, title: String) {
        self.id = id
        self.title = title
        self.description = ""
        self.location = ""
        self.address = ""
        self.state = ""
        self.country = ""
        self.latitude = nil
        self.longitude = nil
        self.dateTime = "2025-01-01T00:00:00"
        self.imageUrl = nil
        self.createdByEmail = nil
        self.attendees = []
        self.ticketTiers = []
        self.type = "DIRECT"
        self.budgetGoal = nil
        self.budgetPurpose = nil
        self.zelleEmail = nil
        self.zellePhone = nil
        self.allowPagoMovil = false
        self.allowCash = false
        self.pagoMovilCi = nil
        self.pagoMovilPhone = nil
        self.pagoMovilBank = nil
        self.cashNote = ""
        self.reunionGuests = nil
        self.createdBy = nil
        self.purchasedTickets = []
    }
    
}

struct UserMini: Codable {
    let id: Int
    let email: String
    let username: String
}




// ✅ Manual Equatable conformance
extension Event: Equatable {
    static func == (lhs: Event, rhs: Event) -> Bool {
        return lhs.id == rhs.id
    }
}



