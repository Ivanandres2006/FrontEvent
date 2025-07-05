//
//  TicketTier.swift
//  eventFront
//
//  Created by Ivan Andres Madriz on 21/6/25.
//

import Foundation

struct TicketTier: Identifiable, Codable, Equatable, Hashable {
    let id: Int
    let name: String
    let price: Double
    let availableQuantity: Int
    let tierOrder: Int?
    let startTime: Date?
    let endTime: Date?
    let forceOpen: Bool?
}

