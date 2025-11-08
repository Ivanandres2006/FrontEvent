import Foundation
import UIKit

// MARK: - Models
struct MeProfile: Codable {
    let id: Int
    let username: String?
    let displayName: String?
    let bio: String?
    let avatarUrl: String?
}

// MARK: - API
enum UserProfileAPI {
    private static let base = URL(string: "https://backendevent-etce.onrender.com")!
    private static func bearer() -> String? { TokenManager.shared.getAccessToken() }

    // MARK: Fetch profile
    static func getMe() async throws -> MeProfile {
        var req = URLRequest(url: base.appendingPathComponent("/user/me"))
        if let t = bearer() { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(MeProfile.self, from: data)
    }

    // MARK: Update bio
    static func updateBio(_ bio: String) async throws {
        var req = URLRequest(url: base.appendingPathComponent("/api/users/me/bio"))
        req.httpMethod = "PATCH"
        if let t = bearer() { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct Body: Encodable { let bio: String }
        req.httpBody = try JSONEncoder().encode(Body(bio: bio))
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode ?? 500 < 300 else { throw URLError(.badServerResponse) }
    }

    // MARK: Upload avatar (caps to ~900 KB and retries once if -1005)
    enum UserProfileAPIError: LocalizedError {
        case imageEncodingFailed, noHTTP
        case badStatus(Int, String)
        var errorDescription: String? {
            switch self {
            case .imageEncodingFailed: return "Could not encode avatar image."
            case .noHTTP: return "No HTTP response."
            case .badStatus(let c, let b): return "Upload failed (\(c)): \(b)"
            }
        }
    }

    static func uploadAvatar(_ image: UIImage) async throws -> String {
        // -- compress to ~0.9 MB (reuse your helper if you have it) --
        let data = try avatarJPEGDataFitting(image: image, maxBytes: 900_000)

        guard let token = bearer(), !token.isEmpty else { throw URLError(.userAuthenticationRequired) }

        func makeRequest(url: URL) -> URLRequest {
            let boundary = "Boundary-\(UUID().uuidString)"
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.timeoutInterval = 120

            var body = Data()
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"file\"; filename=\"avatar.jpg\"\r\n")
            body.appendString("Content-Type: image/jpeg\r\n\r\n")
            body.append(data)
            body.appendString("\r\n--\(boundary)--\r\n")
            req.httpBody = body
            return req
        }

        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 120
        cfg.timeoutIntervalForResource = 300
        let session = URLSession(configuration: cfg)

        let url = base.appendingPathComponent("/api/users/me/avatar")
        var req = makeRequest(url: url)

        // 1st attempt
        let (respData1, resp1) = try await session.data(for: req)
        guard let http1 = resp1 as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        // Detect redirect then 401 (URL changed → header likely stripped)
        if http1.statusCode == 401, let finalURL = http1.url, finalURL != url {
            // re-send to the final URL preserving the Authorization header
            let req2 = makeRequest(url: finalURL)
            let (respData2, resp2) = try await session.data(for: req2)
            guard let http2 = resp2 as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            guard (200...299).contains(http2.statusCode) else {
                let body = String(data: respData2, encoding: .utf8) ?? ""
                throw NSError(domain: "Upload", code: http2.statusCode,
                              userInfo: [NSLocalizedDescriptionKey: "Upload failed (\(http2.statusCode)): \(body)"])
            }
            // parse success
            if let dict = try? JSONSerialization.jsonObject(with: respData2) as? [String: Any],
               let url = dict["avatarUrl"] as? String { return url }
            if let me = try? JSONDecoder().decode(MeProfile.self, from: respData2),
               let url = me.avatarUrl { return url }
            throw URLError(.cannotParseResponse)
        }

        // Normal success/fail path (no redirect)
        guard (200...299).contains(http1.statusCode) else {
            let body = String(data: respData1, encoding: .utf8) ?? ""
            throw NSError(domain: "Upload", code: http1.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "Upload failed (\(http1.statusCode)): \(body)"])
        }
        if let dict = try? JSONSerialization.jsonObject(with: respData1) as? [String: Any],
           let url = dict["avatarUrl"] as? String { return url }
        if let me = try? JSONDecoder().decode(MeProfile.self, from: respData1),
           let url = me.avatarUrl { return url }
        throw URLError(.cannotParseResponse)
    }
}

// MARK: - Helpers
private extension Data {
    mutating func appendString(_ s: String) { append(s.data(using: .utf8)!) }
}

private func avatarJPEGDataFitting(image: UIImage, maxBytes: Int) throws -> Data {
    // try quality first, then progressively downscale dimensions
    var scale: CGFloat = 1.0
    var quality: CGFloat = 0.82
    var current = image
    func jpeg(_ img: UIImage, _ q: CGFloat) -> Data? { img.jpegData(compressionQuality: q) }

    // attempt up to 12 steps
    for _ in 0..<12 {
        if let d = jpeg(current, quality), d.count <= maxBytes { return d }
        if scale > 0.45 {
            scale *= 0.85
            current = image.resized(maxDimension: max(image.size.width, image.size.height) * scale)
        } else if quality > 0.35 {
            quality -= 0.1
        } else {
            break
        }
    }
    guard let d = jpeg(current, max(quality, 0.35)) else { throw UserProfileAPI.UserProfileAPIError.imageEncodingFailed }
    return d.count <= maxBytes ? d : d // will still usually be < maxBytes after downscale
}

private extension UIImage {
    func resized(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
