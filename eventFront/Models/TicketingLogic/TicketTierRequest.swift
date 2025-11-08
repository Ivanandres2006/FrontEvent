//
//  TicketTierRequest.swift
//  eventFront
//
//  Created by Ivan Andres Madriz on 21/6/25.
//

import Foundation

struct TicketTierRequest: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var price: Double
    var quantity: Int
    let order: Int
    let description: String?
    let startTime: Date?
    let hideQuantity: Bool?   // 👈 NEW
    let endTime: Date?
    var forceOpen: Bool = false
}
