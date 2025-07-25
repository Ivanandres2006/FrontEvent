import SwiftUI

struct SplashView: View {
    var finishSplash: () -> Void

    @AppStorage("isLoggedIn", store: UserDefaults.standard) private var isLoggedIn = false
    @AppStorage("hasSeenLanguagePrompt", store: UserDefaults.standard) private var hasSeenLanguagePrompt = false
    @AppStorage("selectedLanguage", store: UserDefaults.standard) private var selectedLanguage: String = "en"
    @State private var showLanguagePrompt = false
    @State private var showIntro = true
    @State private var isChecking = false
    @State private var splashOpacity = 0.0
    @State private var show3D = false
    @State private var showEvents = false

    var body: some View {
        if showLanguagePrompt {
            LanguageSelectionView(onLanguageSelected: { lang in
                self.selectedLanguage = lang
                self.hasSeenLanguagePrompt = true
                self.runSplash()
                self.showLanguagePrompt = false
            })
        } else if showIntro {
            splashIntroScreen
        } else if isChecking {
            loadingCheckScreen
        } else {
            Color.clear.onAppear {
                finishSplash()
            }
        }
    }

    var splashIntroScreen: some View {
        ZStack {
            LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: -8) {
                Text("WKND")
                    .font(.system(size: 60, weight: .heavy, design: .rounded))
                    .foregroundColor(.gold)
                    .scaleEffect(show3D ? 1.0 : 0.3)
                    .opacity(show3D ? 1.0 : 0.0)
                    .rotation3DEffect(.degrees(show3D ? 0 : 60), axis: (x: 1, y: 0, z: 0))
                    .shadow(color: .gold.opacity(0.5), radius: 30, x: 0, y: 10)
                    .animation(.easeOut(duration: 1.6), value: show3D)

                Text("Events")
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundColor(.gold.opacity(0.9))
                    .offset(y: show3D ? 0 : 10)
                    .opacity(showEvents ? 1.0 : 0.0)
                    .animation(.easeIn(duration: 1.0).delay(0.9), value: showEvents)
            }
        }
        .onAppear {
            runSplash()
        }
    }

    var loadingCheckScreen: some View {
        ZStack {
            LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView("Loading...")
                    .progressViewStyle(CircularProgressViewStyle(tint: .gold))
                    .foregroundColor(.white)
                    .font(.headline)

                Text("Checking session...")
                    .foregroundColor(.gray)
                    .font(.subheadline)
            }
        }
    }

    func runSplash() {
        splashOpacity = 1.0
        show3D = false
        showEvents = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation { show3D = true }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            withAnimation { showEvents = true }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            withAnimation {
                splashOpacity = 0.0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showIntro = false

                if !hasSeenLanguagePrompt {
                    showLanguagePrompt = true
                } else {
                    isChecking = true
                    validateSession()
                }
            }
        }
    }



    func validateSession() {
        TokenManager.shared.validateToken { success in
            DispatchQueue.main.async {
                isLoggedIn = success
                if !success {
                    TokenManager.shared.deleteToken()
                }
                isChecking = false
            }
        }
    }
}
