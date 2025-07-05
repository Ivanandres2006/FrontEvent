//
//  UserSession.swift
//  eventFront
//
//  Created by Ivan Andres Madriz on 17/6/25.
//

import Foundation

class UserSession: ObservableObject {
    @Published var fullName = "User"
    @Published var firstName = "User"
    @Published var lastName = "User"
    @Published var username = "User"
    @Published var email = ""
    @Published var userId: Int = 0
    @Published var role: String = "USER"
    

    func loadUser() {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "http://localhost:8080/user/me") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            DispatchQueue.main.async {
                let first = json["firstName"] as? String ?? ""
                let last = json["lastName"] as? String ?? ""
                let username = json["username"] as? String ?? ""
                self.firstName = first
                self.lastName = last
                self.username = username
                self.fullName = "\(first) \(last)"
                self.email = json["email"] as? String ?? ""
                self.userId = json["id"] as? Int ?? 0
                self.role = (json["role"] as? String ?? "USER").uppercased() // ✅ Extract role
            }
        }.resume()
    }
}
