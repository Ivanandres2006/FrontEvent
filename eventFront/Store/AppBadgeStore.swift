//
//  AppBadgeStore.swift
//  eventFront
//
//  Created by Ivan Andres Madriz on 1/9/25.
//


import Foundation
import Combine

final class AppBadgeStore: ObservableObject {
    static let shared = AppBadgeStore()
    @Published var unreadChats: Int = 0
    @Published var pendingResale: Int = 0
    private init() {}
}
