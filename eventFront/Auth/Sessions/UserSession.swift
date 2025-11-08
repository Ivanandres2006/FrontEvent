//
//  UserSession.swift
//  eventFront
//

import Foundation

extension Notification.Name {
    static let userSessionLoaded = Notification.Name("userSessionLoaded")
}

// Mirrors /user/me JSON exactly
struct MeResponse: Codable {
    let id: Int64
    let firstName: String
    let lastName: String
    let email: String
    let phone: String
    let role: String
    let canCreateEvents: Bool
    let username: String

    let avatarUrl: String
    let bio: String
    let hideProfile: Bool
    let hideAttendance: Bool

    let promotedEvents: [Int64]

    // Stats
    let followersCount: Int64
    let followingCount: Int64
    let friendsCount: Int64
    let eventsCount: Int64
}

final class UserSession: ObservableObject {
    // Core identity
    @Published var userId: Int64 = 0
    @Published var email: String = ""
    @Published var firstName: String = ""
    @Published var lastName: String = ""
    @Published var fullName: String = ""
    @Published var username: String = ""
    @Published var role: String = "USER"
    @Published var canCreateEvent: Bool = false

    // Profile
    @Published var avatarUrl: String = ""
    @Published var bio: String = ""
    @Published var hideProfile: Bool = false
    @Published var hideAttendance: Bool = false

    // Relationships / permissions
    @Published var promotedEvents: [Int64] = []

    // Stats
    @Published var followersCount: Int64 = 0
    @Published var followingCount: Int64 = 0
    @Published var friendsCount: Int64 = 0
    @Published var eventsCount: Int64 = 0

    // MARK: - Load current user from API
    func loadUser() {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/user/me") else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data else { return }
            guard let me = try? JSONDecoder().decode(MeResponse.self, from: data) else {
                #if DEBUG
                if let raw = String(data: data, encoding: .utf8) {
                    print("⚠️ Failed to decode MeResponse. Raw:\n\(raw)")
                }
                #endif
                return
            }

            DispatchQueue.main.async {
                self.apply(me)
                NotificationCenter.default.post(name: .userSessionLoaded, object: self.username)
            }
        }.resume()
    }

    private func apply(_ me: MeResponse) {
        userId = me.id
        email = me.email
        firstName = me.firstName
        lastName = me.lastName
        fullName = "\(me.firstName) \(me.lastName)".trimmingCharacters(in: .whitespaces)
        username = me.username
        role = me.role.uppercased()
        canCreateEvent = me.canCreateEvents

        avatarUrl = me.avatarUrl
        bio = me.bio
        hideProfile = me.hideProfile
        hideAttendance = me.hideAttendance

        promotedEvents = me.promotedEvents

        followersCount = me.followersCount
        followingCount = me.followingCount
        friendsCount = me.friendsCount
        eventsCount = me.eventsCount
    }
    
    
    // MARK: - Small helper to PATCH profile (optional use from ProfileView toggles)
    func updateProfile(avatarUrl: String? = nil,
                       bio: String? = nil,
                       hideProfile: Bool? = nil,
                       hideAttendance: Bool? = nil) {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/user/update-profile") else { return }

        var body: [String: Any] = [:]
        if let avatarUrl { body["avatarUrl"] = avatarUrl }
        if let bio { body["bio"] = bio }
        if let hideProfile { body["hideProfile"] = hideProfile }
        if let hideAttendance { body["hideAttendance"] = hideAttendance }

        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { _, _, _ in
            // Optimistic update; you can re-call loadUser() if you prefer server source of truth
            DispatchQueue.main.async {
                if let avatarUrl { self.avatarUrl = avatarUrl }
                if let bio { self.bio = bio }
                if let hideProfile { self.hideProfile = hideProfile }
                if let hideAttendance { self.hideAttendance = hideAttendance }
            }
        }.resume()
    }
}
