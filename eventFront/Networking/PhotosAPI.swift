import Foundation
import UIKit

struct PhotoDTO: Codable, Identifiable, Hashable {
    let id: Int
    let url: String
    let eventId: Int
    let createdAt: String
}

// Custom error for local image encoding failures
enum PhotosAPIError: LocalizedError {
    case imageEncodingFailed
    var errorDescription: String? { "Could not encode image for upload." }
}

enum PhotosAPI {
    private static let base = URL(string: "https://backendevent-etce.onrender.com")!
    private static func bearer() -> String? { TokenManager.shared.getAccessToken() }

    static func eligibility(eventId: Int) async throws -> Bool {
        var req = URLRequest(url: base.appendingPathComponent("/api/photos/eligibility/\(eventId)"))
        if let t = bearer() { req.addValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return (try? JSONDecoder().decode(Bool.self, from: data)) ?? (String(data: data, encoding: .utf8) == "true")
    }

    static func myPhotos() async throws -> [PhotoDTO] {
        var req = URLRequest(url: base.appendingPathComponent("/api/photos/me"))
        if let t = bearer() { req.addValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode([PhotoDTO].self, from: data)
    }

    static func userPhotos(userId: Int) async throws -> [PhotoDTO] {
        var req = URLRequest(url: base.appendingPathComponent("/api/photos/user/\(userId)"))
        if let t = bearer() { req.addValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode([PhotoDTO].self, from: data)
    }

    static func upload(image: UIImage, eventId: Int) async throws {
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            throw PhotosAPIError.imageEncodingFailed
        }
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: base.appendingPathComponent("/api/photos"))
        req.httpMethod = "POST"
        if let t = bearer() { req.addValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func append(_ s: String) { body.append(s.data(using: .utf8)!) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"eventId\"\r\n\r\n")
        append("\(eventId)\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"photo.jpg\"\r\n")
        append("Content-Type: image/jpeg\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")
        req.httpBody = body

        let (_, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode ?? 500 < 300 else { throw URLError(.badServerResponse) }
    }
}
