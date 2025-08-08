import Foundation

struct WaitlistEntry: Identifiable, Codable {
    let id: Int
    let fullName: String
    let username: String
    let status: String

    private enum CodingKeys: String, CodingKey {
        case id, fullName, username, status
    }
}

