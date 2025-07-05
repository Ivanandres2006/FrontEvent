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

        var request = URLRequest(url: URL(string: "http://localhost:8080/auth/validate")!)
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
    func refreshIfNeeded(completion: @escaping (Bool) -> Void) {
        guard let refreshToken = getRefreshToken() else {
            completion(false)
            return
        }

        var request = URLRequest(url: URL(string: "http://localhost:8080/auth/refresh")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["refreshToken": refreshToken]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newAccess = json["accessToken"] as? String,
                  let newRefresh = json["refreshToken"] as? String else {
                completion(false)
                return
            }

            self.save(access: newAccess, refresh: newRefresh)
            completion(true)
        }.resume()
    }
}
