import Foundation

struct ReunionGuest: Identifiable, Codable, Equatable {
    let id = UUID()
    var username: String        // ✅ used for RSVP and backend logic
    var name: String            // for display
    var email: String           // for display
    var paid: Bool
    let attending: Bool
}


