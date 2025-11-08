import Foundation

struct BadgeDTO: Codable, Identifiable, Hashable {
    var id: String { key }
    let key: String
    let name: String
    let iconUrl: String?
    let description: String?
    let awardedAt: String?
}

enum BadgesAPI {
    private static let base = URL(string: "https://backendevent-etce.onrender.com")!
    private static func bearer() -> String? { TokenManager.shared.getAccessToken() }

    static func myBadges() async throws -> [BadgeDTO] {
        var req = URLRequest(url: base.appendingPathComponent("/api/badges/me"))
        if let t = bearer() { req.addValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode([BadgeDTO].self, from: data)
    }

    static func badges(userId: Int) async throws -> [BadgeDTO] {
        var req = URLRequest(url: base.appendingPathComponent("/api/badges/\(userId)"))
        if let t = bearer() { req.addValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode([BadgeDTO].self, from: data)
    }
}
