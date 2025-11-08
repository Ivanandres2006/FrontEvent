//
//  PromoterAPI.swift
//  eventFront
//
import Foundation

final class PromoterAPI {
    private let baseURL: URL
    private let tokenProvider: () -> String?
    
    init(baseURL: URL = URL(string: "https://backendevent-etce.onrender.com")!,
         tokenProvider: @escaping () -> String? = { TokenManager.shared.getAccessToken() }) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
    }
    
    // MARK: - Core request
    @discardableResult
    private func request<T: Decodable>(_ path: String,
                                       method: String = "GET",
                                       query: [URLQueryItem] = [],
                                       body: Encodable? = nil) async throws -> T {
        guard let token = tokenProvider() else {
            throw APIError.http(401, "Missing auth token")
        }
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }
        
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.http(-1, "No HTTPURLResponse")
        }
        if http.statusCode == 204 {
            if T.self == Empty.self { return Empty() as! T }
            throw APIError.http(http.statusCode, "No Content")
        }
        if let ctype = http.value(forHTTPHeaderField: "Content-Type"),
           !ctype.lowercased().contains("application/json") {
            let txt = String(data: data, encoding: .utf8) ?? ""
            throw APIError.http(http.statusCode, "Non-JSON response: \(txt.prefix(200))")
        }
        if (200..<300).contains(http.statusCode) == false {
            let txt = String(data: data, encoding: .utf8) ?? ""
            throw APIError.http(http.statusCode, txt)
        }
        return try JSONDecoder.iso8601.decode(T.self, from: data)
    }
    
    enum APIError: Error, LocalizedError {
        case http(Int, String)
        var errorDescription: String? {
            switch self {
            case .http(let code, let msg): return "HTTP \(code): \(msg)"
            }
        }
    }
    
    // MARK: - Endpoints (mirror backend)
    func becomeMe() async throws -> Promoter {
        try await request("/api/promoters/become-me", method: "POST")
    }
    func me() async throws -> Promoter {
        try await request("/api/promoters/me")
    }
    func eventPromoters(eventId: Int64) async throws -> [PromoterEventDTO] {
        try await request("/api/promoters/events/\(eventId)")
    }
    func assign(eventId: Int64, username: String) async throws -> PromoterEventDTO {
        try await request("/api/promoters/\(eventId)/assign",
                          method: "POST",
                          query: [URLQueryItem(name: "username", value: username)])
    }
    /// Buyers for the *current* promoter on this event.
    func myBuyers(eventId: Int64) async throws -> [ReferredBuyerDTO] {
        try await request("/api/promoters/buyers/\(eventId)")
    }
    /// Buyers for a specific promoter (owner/admin only).
    func buyersForPromoter(eventId: Int64, promoterId: Int64) async throws -> [ReferredBuyerDTO] {
        try await request("/api/promoters/events/\(eventId)/promoter/\(promoterId)/buyers")
    }
}

// MARK: - Plumbing

private struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void
    init(_ encodable: Encodable) { self.encodeFunc = encodable.encode }
    func encode(to encoder: Encoder) throws { try encodeFunc(encoder) }
}
private struct Empty: Codable {}

extension JSONDecoder {
    static let iso8601: JSONDecoder = {
        let d = JSONDecoder()
        if #available(iOS 15.0, *) { d.dateDecodingStrategy = .iso8601 }
        return d
    }()
}
