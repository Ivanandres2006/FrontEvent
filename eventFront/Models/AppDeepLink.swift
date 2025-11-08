//
//  AppDeepLink.swift
//  eventFront
//
//  Created by Ivan Andres Madriz on 1/9/25.
//


// eventFront/Shared/DeepLinking.swift
import Foundation

extension Notification.Name {
    static let openResalePostFromLink = Notification.Name("openResalePostFromLink")
}

enum AppDeepLink {
    case resalePost(id: Int)

    static func parse(url: URL) -> AppDeepLink? {
        // Support: https://app.example.com/r/123  OR  eventx://r/123
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let comps = path.split(separator: "/")
        if comps.count == 2, comps[0] == "r", let id = Int(comps[1]) {
            return .resalePost(id: id)
        }
        return nil
    }
}
