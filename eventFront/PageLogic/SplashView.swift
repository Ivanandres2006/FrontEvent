import SwiftUI

struct SplashView: View {
    var finishSplash: () -> Void

    @AppStorage("isLoggedIn", store: UserDefaults.standard) private var isLoggedIn = false
    @State private var showIntro = true
    @State private var isChecking = false
    @State private var splashOpacity = 0.0
    @State private var show3D = false
    @State private var showEvents = false

    var body: some View {
        if showIntro {
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
                    .foregroundColor(.neonGreen)
                    .scaleEffect(show3D ? 1.0 : 0.3)
                    .opacity(show3D ? 1.0 : 0.0)
                    .rotation3DEffect(.degrees(show3D ? 0 : 60), axis: (x: 1, y: 0, z: 0))
                    .shadow(color: .neonGreen.opacity(0.5), radius: 30, x: 0, y: 10)
                    .animation(.easeOut(duration: 1.6), value: show3D)

                Text("Events")
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundColor(.neonGreen.opacity(0.9))
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
                    .progressViewStyle(CircularProgressViewStyle(tint: .neonGreen))
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

        // Trigger WKND zoom-in slowly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation {
                show3D = true
            }
        }

        // Fade in "Events"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            withAnimation {
                showEvents = true
            }
        }

        // End splash and move on
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            withAnimation {
                splashOpacity = 0.0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showIntro = false
                isChecking = true
                validateSession()
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
