//
//  AppDelegate.swift
//  eventFront
//

import SwiftUI
import FirebaseCore
import FirebaseMessaging
import UserNotifications
import SwiftUI
import UIKit
import GooglePlaces


struct EventFrontApp: App {
    // AppDelegate hosts Firebase/UNUserNotificationCenter/Messaging plumbing
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var deepLinkEventId: String? = nil

    var body: some Scene {
        WindowGroup {
            AppRootView(deepLinkEventId: $deepLinkEventId)
                // (optional) handle custom URL deep links to set deepLinkEventId
                .onOpenURL { url in
                    if let id = DeepLinkParser.eventId(from: url) {
                        deepLinkEventId = id
                    }
                }
        }
    }
}

/// Tiny helper to parse your event deep links if you have them.
enum DeepLinkParser {
    static func eventId(from url: URL) -> String? {
        // Example: wknd://event/123  → "123"
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2, parts[0].lowercased() == "event" else { return nil }
        return parts[1]
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // 1) Configure Firebase early
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        
        GMSPlacesClient.provideAPIKey("AIzaSyAsSjybISIywrdMNKMVrKrhgDIQdX1r4pA") // ← add this
        // 2) Prepare push: center delegate + ask for permission then register for APNS
        UNUserNotificationCenter.current().delegate = self
        requestPushAuthorizationAndRegister(for: application)

        // 3) Hook FCM delegate
        Messaging.messaging().delegate = self

        return true
    }

    private func requestPushAuthorizationAndRegister(for application: UIApplication) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
            // Register for APNS on main thread
            DispatchQueue.main.async {
                application.registerForRemoteNotifications()
            }
        }
    }

    // 4) APNS device token → pass to FCM (THIS fixes “no APNS token specified”)
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        // (Optional) Immediately fetch FCM token now that APNS token is set
        Messaging.messaging().token { token, error in
            NotificationCenter.default.post(name: .fcmTokenUpdated, object: token)
            if let token { PushTokenUploader.shared.updateIfNeeded(fcmToken: token) }
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("APNS register failed:", error.localizedDescription)
    }
}

// MARK: UNUserNotificationCenterDelegate
extension AppDelegate: UNUserNotificationCenterDelegate {
    // Foreground presentation
        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    willPresent notification: UNNotification,
                                    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
            // Show it
            completionHandler([.banner, .sound, .badge])
            
            // Optional: also persist to Activity when received in foreground
            persistToActivity(from: notification.request.content.userInfo)
        }

        // User tapped a notification
        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    didReceive response: UNNotificationResponse,
                                    withCompletionHandler completionHandler: @escaping () -> Void) {
            let userInfo = response.notification.request.content.userInfo
            
            // 1) Deep links (your existing logic)
            if let type = userInfo["type"] as? String {
                if type == "CHAT", let chatId = valueAsString(userInfo["chatId"]) {
                    NotificationCenter.default.post(name: .openChatFromPush, object: chatId)
                } else if type == "EVENT", let eventId = valueAsString(userInfo["eventId"]) {
                    NotificationCenter.default.post(name: .openEventFromPush, object: eventId)
                }
            }
            
            // 2) Persist to local Activity
            persistToActivity(from: userInfo)
            
            completionHandler()
        }

        // MARK: - Normalize + persist
    private func persistToActivity(from userInfo: [AnyHashable: Any]) {
        // Type
        let rawType = (userInfo["type"] as? String)
        ?? (userInfo["notificationType"] as? String)
        ?? (userInfo["category"] as? String)
        ?? "PUSH"
        
        // Actor id (int from Int/String/NSNumber)
        let actorId: Int = valueAsInt(userInfo["actorId"])
        ?? valueAsInt(userInfo["userId"])
        ?? -1
        
        // Username / display
        let username = (userInfo["username"] as? String)
        ?? (userInfo["handle"] as? String)
        ?? "user"
        let displayName = (userInfo["displayName"] as? String)
        ?? (userInfo["name"] as? String)
        
        // Avatar / thumb
        let avatarUrl = (userInfo["avatarUrl"] as? String)
        ?? (userInfo["avatar"] as? String)
        var entityThumb = (userInfo["entityThumb"] as? String)
        ?? (userInfo["thumbUrl"] as? String)
        ?? (userInfo["coverUrl"] as? String)
        ?? (userInfo["imageUrl"] as? String)
        
        // Target entity id (event/post/chat/etc.)
        let entityId: Int? = valueAsInt(userInfo["entityId"])
        ?? valueAsInt(userInfo["targetId"])
        ?? valueAsInt(userInfo["photoId"])
        ?? valueAsInt(userInfo["eventId"])
        ?? valueAsInt(userInfo["chatId"])
        ?? valueAsInt(userInfo["postId"])
        
        // Pull some fallback bits from APS
        if let aps = userInfo["aps"] as? [String: Any] {
            if entityThumb == nil, let thumb = aps["entityThumb"] as? String {
                entityThumb = thumb
            }
            // If your provider puts a title in APS, you can use it as a displayName fallback:
            if displayName == nil,
               let alert = aps["alert"] as? [String: Any],
               let title = alert["title"] as? String,
               !title.isEmpty {
                // not stored separately; just an example if you want to override
            }
        }
        
        let item = ActivityItem(
            type: rawType,
            actorId: actorId,
            username: username,
            displayName: displayName,
            avatarUrl: avatarUrl,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            entityId: entityId,
            entityThumb: entityThumb
        )
        
        LocalActivityStore.insert(item)
        NotificationCenter.default.post(name: .newActivitySaved, object: nil)
    }

        // MARK: - Small helpers to coerce Any to Int/String safely
    private func valueAsInt(_ any: Any?) -> Int? {
        switch any {
        case let n as NSNumber: return n.intValue
        case let i as Int:      return i
        case let s as String:   return Int(s)
        default:                return nil
        }
    }
    private func valueAsString(_ any: Any?) -> String? {
        switch any {
        case let s as String:   return s
        case let n as NSNumber: return n.stringValue
        case let i as Int:      return String(i)
        default:                return nil
        }
    }


    
    func applicationWillEnterForeground(_ application: UIApplication) {
        ChatAPI.shared.fetchUnreadCount { count in
            DispatchQueue.main.async {
                UIApplication.shared.applicationIconBadgeNumber = count
            }
        }
    }

}

// MARK: MessagingDelegate
extension AppDelegate: MessagingDelegate {
    // FCM token is ready or refreshed
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        NotificationCenter.default.post(name: .fcmTokenUpdated, object: fcmToken)
        if let fcmToken { PushTokenUploader.shared.updateIfNeeded(fcmToken: fcmToken) }
    }
}

extension Notification.Name {
    static let fcmTokenUpdated    = Notification.Name("fcmTokenUpdated")
    static let openChatFromPush   = Notification.Name("openChatFromPush")
    static let openEventFromPush  = Notification.Name("openEventFromPush")
    static let newActivitySaved = Notification.Name("newActivitySaved")
    static let chatListNeedsRefresh = Notification.Name("chatListNeedsRefresh")
    static let openBuyFromOffer = Notification.Name("openBuyFromOffer")
    static let offerMarkedSold = Notification.Name("offerMarkedSold")
    
}


/// Replace the backend call inside `send(_:)` with your existing API.
final class PushTokenUploader {
    static let shared = PushTokenUploader()
    private var lastSent: String?

    func updateIfNeeded(fcmToken: String) {
        guard lastSent != fcmToken else { return }
        lastSent = fcmToken
        send(fcmToken)
    }

    private func send(_ token: String) {
        // TODO: call your backend to save token for current user.
        // e.g. ProfileAPI.shared.updatePushToken(token)
        print("✅ FCM token ready:", token)
    }
}
