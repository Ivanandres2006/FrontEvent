import UIKit
import Firebase
import FirebaseMessaging
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self

        // ✅ Solo registramos si el usuario da permiso (ver abajo)
        requestPushPermissions()
        
        // ✅ Verificación manual del token FCM (muy útil para debug)
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


    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("📱 FCM Token: \(fcmToken ?? "nil")")

        guard let token = fcmToken,
              let url = URL(string: "https://backendevent-etce.onrender.com/api/notifications/register") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = "\"\(token)\"".data(using: .utf8)

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
