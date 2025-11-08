import Foundation

final class HTTPClient {
    static let shared = HTTPClient()
    private init() {}

    func send<T: Decodable>(_ request: URLRequest,
                            decode: T.Type,
                            allowed: Range<Int> = 200..<300) async throws -> T {
        let (data, resp) = try await URLSession.shared.data(for: request)
        guard let http = resp as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard allowed.contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw APIError.server(message)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            #if DEBUG
            print("Decoding error:", error, "\nPayload:", String(data: data, encoding: .utf8) ?? "")
            #endif
            throw APIError.decoding
        }
    }

    func sendNoBody(_ request: URLRequest,
                    allowed: Range<Int> = 200..<300) async throws {
        let (_, resp) = try await URLSession.shared.data(for: request)
        guard let http = resp as? HTTPURLResponse, allowed.contains(http.statusCode)
        else { throw APIError.invalidResponse }
    }
}
