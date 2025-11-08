import Foundation

enum APIConfig {
    static var baseURL: URL = URL(string: "https://backendevent-etce.onrender.com")!

    static func authedRequest(_ path: String,
                              method: String = "GET",
                              headers: [String:String] = [:]) -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.timeoutInterval = 30
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        headers.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        if let token = TokenManager.shared.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }
}

enum APIError: Error, LocalizedError {
    case invalidResponse
    case server(String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid server response"
        case .server(let msg): return msg
        case .decoding: return "Could not decode server data"
        }
    }
}
