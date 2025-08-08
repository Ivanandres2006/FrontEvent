import SwiftUI

struct AppRootView: View {
    @AppStorage("isLoggedIn", store: UserDefaults.standard) private var isLoggedIn = false
    @AppStorage("hasPassword", store: UserDefaults.standard) private var hasPassword = false
    @AppStorage("hasUsername") var hasUsername = false
    
    @State private var showSplash = true
    
    @Binding var deepLinkEventId: String?
    
    var body: some View {
        if showSplash {
            SplashView(finishSplash: {
                self.showSplash = false
            })
        } else {
            if isLoggedIn {
                if hasPassword {
                    if hasUsername {
                        MainTabView(deepLinkEventId: $deepLinkEventId) // <--
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
