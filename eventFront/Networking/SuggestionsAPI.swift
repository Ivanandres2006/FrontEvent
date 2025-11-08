// SuggestionsAPI.swift
import Foundation

enum SuggestionsAPI {
    struct ContactsPayload: Codable {
        let hashed: Bool
        let emails: [String]
        let phones: [String]
    }
    struct IdentitiesPayload: Codable {
        let emails: [String]
        let phones: [String]
    }

    private static let base = APIConfig.baseURL

    static func upsertIdentities(emails: [String], phones: [String]) async throws {
        var req = APIConfig.authedRequest("/api/suggest/me/identities", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(IdentitiesPayload(emails: emails, phones: phones))
        try await HTTPClient.shared.sendNoBody(req)
    }

    /// POST /api/suggest/me — return UI-friendly model
    static func suggestions(hashed: Bool, emails: [String], phones: [String], limit: Int = 20) async throws -> [UserSummary] {
        var comps = URLComponents(url: base.appendingPathComponent("/api/suggest/me"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "limit", value: "\(limit)")]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = TokenManager.shared.getAccessToken() {   // <- match your other code
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let body = ContactsPayload(hashed: hashed, emails: emails, phones: phones)
        req.httpBody = try JSONEncoder().encode(body)

        let dtos: [SuggestionDTO] = try await HTTPClient.shared.send(req, decode: [SuggestionDTO].self)
        return dtos.map { $0.asUserSummary }
    }

    static func importContacts(hashed: Bool, emails: [String], phones: [String]) async throws {
        var req = APIConfig.authedRequest("/api/suggest/me/contacts", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(ContactsPayload(hashed: hashed, emails: emails, phones: phones))
        try await HTTPClient.shared.sendNoBody(req)
    }
}

// Your DTOs can stay where you defined them.
// If they live in another file, keep this extension anywhere the compiler can see both types.
private extension SuggestionDTO {
    var asUserSummary: UserSummary {
        UserSummary(
            id: id,
            username: (username ?? "").isEmpty ? "user\(id)" : (username ?? ""),
            displayName: nil,                  // backend DTO doesn't include it in your paste
            avatarUrl: avatarUrl,
            followers: 0,
            following: 0
        )
    }
}
