import Foundation

struct UserSummaryDTO: Codable, Identifiable, Hashable {
    let id: Int
    let username: String?
    let avatarUrl: String?
}

struct EventSummaryDTO: Codable, Identifiable, Hashable {
    let id: Int
    let title: String?
    let imageUrl: String?
    let location: String?
}

struct SuggestionDTO: Codable, Identifiable, Hashable {
    let id: Int
    let username: String?
    let avatarUrl: String?
    let reason: String?
    let mutualCount: Int?
}
