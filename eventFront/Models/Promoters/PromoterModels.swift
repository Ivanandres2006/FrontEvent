// Models/Promoters/PromoterModels.swift
import Foundation

// Minimal user/event refs to decode nested objects safely (unknown fields ignored)
struct UserRef: Codable, Identifiable, Hashable {
    let id: Int64?
    let username: String?
    let email: String?
    let displayName: String?
}

struct EventRef: Codable, Identifiable, Hashable {
    let id: Int64?
    let title: String?
}

struct Promoter: Codable, Identifiable, Hashable {
    let id: Int64?
    let referralCode: String?
    let user: UserRef?
}

struct PromoterEventDTO: Codable, Identifiable, Hashable {
    let id: Int64
    let promoter: Promoter?
    let event: EventRef?
    let ticketsSold: Int
    let grossRevenue: Double?
    let commissionRate: Double?
    let commissionEarned: Double?
    let commissionEnabled: Bool?
    let commissionActivatedAt: String?
}
