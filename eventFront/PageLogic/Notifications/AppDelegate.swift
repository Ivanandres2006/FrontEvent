import UIKit
import Firebase
import FirebaseMessaging
import UserNotifications
import GooglePlaces


class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    var userSession: UserSession? // <-- Will be injected from SwiftUI if you want

    override init() {
        super.init()
        // Listen for userSession loaded (username ready)
        NotificationCenter.default.addObserver(self, selector: #selector(userSessionLoaded(_:)), name: .userSessionLoaded, object: nil)
    }

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        GMSPlacesClient.provideAPIKey("AIzaSyAsSjybISIywrdMNKMVrKrhgDIQdX1r4pA")
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self

        requestPushPermissions()

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            Messaging.messaging().token { token, error in
                if let error = error {
                    print("❌ Error fetching token manually: \(error.localizedDescription)")
                } else if let token = token {
                    print("✅ Manual fetch FCM Token: \(token)")
                }
            }
        }

        return true
    }

    func requestPushPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            print("🔔 Notification permission granted: \(granted)")
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        print("📦 APNs token received and set ✅")
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Failed to register for remote notifications: \(error.localizedDescription)")
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               didReceive response: UNNotificationResponse,
                               withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if let eventId = userInfo["eventId"] as? String {
            print("🔗 User tapped notification for event: \(eventId)")
            NotificationCenter.default.post(name: Notification.Name("OpenEventFromNotification"), object: eventId)
        }
        completionHandler()
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("📱 FCM Token: \(fcmToken ?? "nil")")
        guard let token = fcmToken else { return }

        // Only send if username is available and valid
        if let username = userSession?.username, !username.isEmpty, username != "unknown" {
            registerFCMToken(token: token, username: username)
        } else {
            print("⏳ Username not ready for FCM registration. Waiting for UserSession.")
        }
    }

    // Called when UserSession is loaded/refreshed and username is ready
    @objc func userSessionLoaded(_ notification: Notification) {
        guard let username = notification.object as? String, !username.isEmpty, username != "unknown" else { return }
        guard let token = Messaging.messaging().fcmToken else {
            print("❌ No FCM token available yet when username loaded")
            return
        }
        registerFCMToken(token: token, username: username)
    }

    // Helper function to send FCM token with username
    func registerFCMToken(token: String, username: String) {
        guard let url = URL(string: "https://backendevent-etce.onrender.com/api/notifications/register") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = ["token": token, "username": username]
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: body)
            request.httpBody = jsonData
        } catch {
            print("❌ Error encoding JSON token body: \(error.localizedDescription)")
            return
        }
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Error sending token: \(error.localizedDescription)")
            } else if let httpResponse = response as? HTTPURLResponse {
                print("✅ Token sent with status: \(httpResponse.statusCode)")
                if let data = data, let responseBody = String(data: data, encoding: .utf8) {
                    print("🔁 Response body: \(responseBody)")
                }
            }
        }.resume()
    }
}
