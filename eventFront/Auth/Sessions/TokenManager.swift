import Foundation

class TokenManager {
    static let shared = TokenManager()

    private let accessKey = "eventFront.jwtToken"
    private let refreshKey = "eventFront.refreshToken"

    private init() {}

    func save(access: String, refresh: String) {
        UserDefaults.standard.set(access, forKey: accessKey)
        UserDefaults.standard.set(refresh, forKey: refreshKey)
    }

    func getAccessToken() -> String? {
        UserDefaults.standard.string(forKey: accessKey)
    }

    func getRefreshToken() -> String? {
        UserDefaults.standard.string(forKey: refreshKey)
    }

    func deleteToken() {
        UserDefaults.standard.removeObject(forKey: accessKey)
        UserDefaults.standard.removeObject(forKey: refreshKey)
    }

    func isLoggedIn() -> Bool {
        return getAccessToken() != nil
    }

    /// Validates and refreshes token if needed
    func validateToken(completion: @escaping (Bool) -> Void) {
        guard let accessToken = getAccessToken() else {
            completion(false)
            return
        }

        var request = URLRequest(url: URL(string: "https://backendevent-etce.onrender.com/auth/validate")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { _, response, _ in
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    completion(true)
                } else {
                    self.refreshIfNeeded(completion: completion)
                }
            } else {
                completion(false)
            }
        }.resume()
    }

    /// Attempts to refresh the token
    // TokenManager.swift
    func refreshIfNeeded(completion: @escaping (Bool) -> Void) {
        guard let refreshToken = getRefreshToken() else {
            completion(false); return
        }

        var request = URLRequest(url: URL(string: "https://backendevent-etce.onrender.com/auth/refresh")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15   // ⏱️
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["refreshToken": refreshToken])

        URLSession.shared.dataTask(with: request) { data, response, error in
            // Always finish one way or another
            guard error == nil, let http = response as? HTTPURLResponse, let data = data else {
                print("🔴 refresh error:", error?.localizedDescription ?? "nil")
                completion(false); return
            }
            guard (200..<300).contains(http.statusCode) else {
                let raw = String(data: data, encoding: .utf8) ?? ""
                print("🔴 refresh non-2xx:", http.statusCode, raw)
                completion(false); return
            }
            guard
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let newAccess = json["accessToken"] as? String,
                let newRefresh = json["refreshToken"] as? String
            else {
                print("🔴 refresh bad JSON")
                completion(false); return
            }
            self.save(access: newAccess, refresh: newRefresh)
            completion(true)
        }.resume()
    }
    
    func normalizedAccessToken() -> String? {
        guard let t = getAccessToken() else { return nil }
        if t.hasPrefix("Bearer ") { return String(t.dropFirst(7)) }
        return t
    }
    
    var token: String? {
        getAccessToken()
    }
}
