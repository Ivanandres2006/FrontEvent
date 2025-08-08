import SwiftUI

struct ContentView: View {
    @AppStorage("isLoggedIn", store: UserDefaults.standard) private var isLoggedIn = false
    @AppStorage("hasPassword") private var hasPassword = false
    @AppStorage("hasUsername") var hasUsername = false
    @State private var deepLinkEventId: String? = nil

    
    var body: some View {
        NavigationStack {
            if isLoggedIn {
                if hasPassword {
                    if hasUsername {
                        MainTabView(deepLinkEventId: $deepLinkEventId)
                            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenEventFromNotification"))) { notification in
                                if let eventId = notification.object as? String {
                                    self.deepLinkEventId = eventId
                                }
                            }
                    } else {
                        SetUsernameView()
                    }
                } else {
                    SetPasswordView()
                }
            } else {
                LoginView()
            }
        }
    }
}
