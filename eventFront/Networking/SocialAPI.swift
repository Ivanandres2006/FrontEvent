import Foundation

public struct UserSummary: Codable, Identifiable, Hashable {
    public let id: Int
    public let username: String
    public let displayName: String?
    public let avatarUrl: String?
    public let followers: Int
    public let following: Int

    public init(id: Int, username: String, displayName: String? = nil, avatarUrl: String? = nil, followers: Int = 0, following: Int = 0) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.followers = followers
        self.following = following
    }
}

public struct FollowRequest: Codable, Identifiable, Hashable {
    public var id: Int { followerId }
    public let followerId: Int
    public let username: String
    public let displayName: String?
    public let requestedAt: String
}

public enum SocialListKind {
    case followers(userId: Int)
    case following(userId: Int)
    case friends(userId: Int)

    var path: String {
        switch self {
        case .followers(let id): return "/api/social/followers/\(id)"
        case .following(let id): return "/api/social/following/\(id)"
        case .friends(let id):   return "/api/social/friends/\(id)"
        }
    }
}

struct SocialCounts: Codable { let followers: Int; let following: Int; let friends: Int }

enum SocialAPI {
    private static let base = URL(string: "https://backendevent-etce.onrender.com")!
    private static func bearer() -> String? { TokenManager.shared.getAccessToken() }
    
    static func fetchCounts(userId: Int) async throws -> SocialCounts {
        let (data, http) = try await authedRequest("/api/social/stats/\(userId)")
        guard (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return try decode(data)
    }

    // Prefer this compact helper for all authed calls
    private static func authedRequest(
        _ path: String,
        method: String = "GET",
        query: [URLQueryItem]? = nil,
        json: (any Encodable)? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if let query { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        if let t = bearer() { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(AnyEncodable(json))
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }

    private static func decode<T: Decodable>(_ data: Data) throws -> T {
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(T.self, from: data)
    }

    // MARK: - Lists
    static func fetch(_ kind: SocialListKind, limit: Int = 50) async throws -> [UserSummary] {
        let (data, http) = try await authedRequest(
            kind.path,
            query: [URLQueryItem(name: "limit", value: String(limit))]
        )
        guard (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return try decode(data)
    }

    // MARK: - Requests (incoming)
    static func fetchRequests(limit: Int = 50) async throws -> [FollowRequest] {
        let (data, http) = try await authedRequest(
            "/api/social/requests",
            query: [URLQueryItem(name: "limit", value: String(limit))]
        )
        guard (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return try decode(data)
    }

    static func acceptRequest(from followerId: Int) async throws {
        let (_, http) = try await authedRequest("/api/social/follow/\(followerId)/accept", method: "POST")
        guard (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
    }

    static func rejectRequest(from followerId: Int) async throws {
        let (_, http) = try await authedRequest("/api/social/follow/\(followerId)/reject", method: "DELETE")
        guard (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
    }

    // MARK: - Follow / Unfollow
    static func follow(userId: Int) async throws {
        let (_, http) = try await authedRequest("/api/social/follow/\(userId)", method: "POST")
        guard (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
    }

    static func unfollow(userId: Int) async throws {
        let (_, http) = try await authedRequest("/api/social/follow/\(userId)", method: "DELETE")
        guard (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
    }

    // MARK: - Relationship
    // Preferred (backend endpoint returns: { outgoing: "NONE|PENDING|ACCEPTED", incoming: "NONE|PENDING|ACCEPTED" })
    struct RelationshipDTO: Codable { let outgoing: String; let incoming: String }

    static func relationshipV2(otherId: Int) async throws -> RelationshipDTO {
        let (data, http) = try await authedRequest("/api/social/relationship/\(otherId)")
        guard (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return try decode(data)
    }

    // Fallback derived relationship (if the endpoint isn't available)
    static func relationship(meId: Int, otherId: Int) async throws -> (isFollowing: Bool, isFollowedBy: Bool) {
        async let myFollowing = fetch(.following(userId: meId), limit: 200)
        async let myFollowers = fetch(.followers(userId: meId), limit: 200)
        let (followingList, followersList) = try await (myFollowing, myFollowers)
        return (
            isFollowing: followingList.contains { $0.id == otherId },
            isFollowedBy: followersList.contains { $0.id == otherId }
        )
    }
}

// Helper for encoding arbitrary bodies
private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { self._encode = wrapped.encode }
    func encode(to encoder: Encoder) throws { try _encode(encoder) }
}
