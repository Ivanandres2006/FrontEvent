import SwiftUI

struct ContentView: View {
    @AppStorage("isLoggedIn", store: UserDefaults.standard) private var isLoggedIn = false
    @AppStorage("hasPassword") private var hasPassword = false
    @AppStorage("hasUsername") var hasUsername = false
    
    var body: some View {
        NavigationStack {
            if isLoggedIn {
                if hasPassword {
                    if hasUsername{
                        MainTabView()
                    }else{
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
