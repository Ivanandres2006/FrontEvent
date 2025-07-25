import SwiftUI
import GoogleSignIn
import GoogleSignInSwift
import AuthenticationServices

struct LoginView: View {
    @AppStorage("isLoggedIn") private var isLoggedIn = false
    @AppStorage("hasPassword") private var hasPassword = false
    @AppStorage("hasUsername") private var hasUsername = false
    @AppStorage("selectedLanguage") var lang: String = "en"
    
    @State private var email = ""
    @State private var password = ""
    @State private var message = ""
    @State private var isLoading = false
    @State private var animate = false

    
    @State private var needsPassword = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                VStack(spacing: 30) {
                    Spacer()

                    Text(lang == "es" ? "Bienvenido": "Welcome Back")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .opacity(animate ? 1.0 : 0)
                        .offset(y: animate ? 0 : -10)
                        .animation(.easeOut(duration: 0.5).delay(0.1), value: animate)

                    VStack(spacing: 16) {
                        CustomInputField(icon: "person", placeholder: lang == "es" ? "Correo Electronico o nombre de usuario": "Email or Username", text: $email, keyboard: .emailAddress)
                        CustomInputField(icon: "lock", placeholder: lang == "es" ? "Clave" :"Password", text: $password, isSecure: true)
                    }
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(20)
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.1)))
                    .opacity(animate ? 1.0 : 0)
                    .animation(.easeOut(duration: 0.5).delay(0.2), value: animate)

                    if !message.isEmpty {
                        Text(message)
                            .foregroundColor(message.contains("✅") ? .green : .red)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    if isLoading {
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: Color.gold))
                    } else {
                        Button("Login", action: login)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gold)
                            .foregroundColor(.black)
                            .cornerRadius(12)
                            .opacity(animate ? 1.0 : 0)
                            .animation(.easeOut(duration: 0.5).delay(0.3), value: animate)
                    }

                    HStack {
                        Spacer()
                        NavigationLink(lang == "es" ? "Olvidaste tu contraseña?": "Forgot your password?", destination: ForgotPasswordView())
                            .foregroundColor(.gray)
                            .font(.footnote)
                    }

                    HStack {
                        Rectangle().frame(height: 1).foregroundColor(.gray.opacity(0.4))
                        Text(lang == "es" ? "O" :"OR").foregroundColor(.gray).font(.caption).padding(.horizontal)
                        Rectangle().frame(height: 1).foregroundColor(.gray.opacity(0.4))
                    }
                    .padding(.horizontal)

                    Button(action: handleGoogleSignIn) {
                        HStack {
                            Image(systemName: "globe")
                            Text("Sign in with Google").fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .foregroundColor(.white)
                    }

                    SignInWithAppleButton(.signIn, onRequest: configureAppleRequest, onCompletion: handleAppleSignIn)
                        .frame(height: 45)
                        .cornerRadius(8)

                    Spacer()

                    NavigationLink(lang == "es" ? "No tienes una cuenta? Registrate":"Don't have an account? Register", destination: RegisterView())
                        .foregroundColor(.gray)
                        .font(.footnote)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 30)
                .onAppear { animate = true }
            }
            .fullScreenCover(isPresented: $needsPassword) {
                SetPasswordView()
            }
        }
    }

    func login() {
        guard let url = URL(string: "https://backendevent-etce.onrender.com/auth/login") else {
            message = "⚠️ Invalid login URL"
            return
        }

        let body: [String: Any] = ["identifier": email, "password": password]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        isLoading = true
        message = ""

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                isLoading = false

                if let error = error {
                    message = "⚠️ \(error.localizedDescription)"
                    return
                }

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    message = "❌ Unexpected error"
                    return
                }

                if let token = json["token"] as? String {
                    let refresh = json["refreshToken"] as? String ?? ""
                    TokenManager.shared.save(access: token, refresh: refresh)

                    self.hasPassword = json["hasPassword"] as? Bool ?? true
                    self.hasUsername = json["hasUsername"] as? Bool ?? true

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isLoggedIn = true
                    }
                } else {
                    message = json["message"] as? String ?? "❌ Login failed"
                }
            }
        }.resume()
    }

    func handleGoogleSignIn() {
        guard let rootViewController = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first else {
            print("❌ Root view controller not found.")
            return
        }

        let config = GIDConfiguration(clientID: "523573034096-mosqfr1g5ij5p7jg8unf37r2f3nlpi7a.apps.googleusercontent.com")
        GIDSignIn.sharedInstance.configuration = config

        GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { result, error in
            if let error = error {
                message = "❌ Google Sign-In failed: \(error.localizedDescription)"
                return
            }

            guard let token = result?.user.idToken?.tokenString else {
                message = "❌ Failed to get token"
                return
            }

            sendExternalLogin(idToken: token, provider: "google")
        }
    }

    func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.email, .fullName]
    }

    func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            if let credential = auth.credential as? ASAuthorizationAppleIDCredential,
               let identityToken = credential.identityToken,
               let tokenString = String(data: identityToken, encoding: .utf8) {
                sendExternalLogin(idToken: tokenString, provider: "apple")
            } else {
                message = "❌ Failed to retrieve Apple token"
            }
        case .failure(let error):
            message = "❌ Apple Sign-In failed: \(error.localizedDescription)"
        }
    }

    func sendExternalLogin(idToken: String, provider: String) {
        guard let url = URL(string: "https://backendevent-etce.onrender.com/auth/\(provider)-login") else {
            message = "⚠️ Invalid login URL"
            return
        }

        let body = ["idToken": idToken, "provider": provider]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        isLoading = true
        message = ""

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                isLoading = false

                if let error = error {
                    message = "⚠️ \(error.localizedDescription)"
                    return
                }

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    message = "❌ Unexpected error"
                    return
                }

                if let token = json["token"] as? String {
                    let refresh = json["refreshToken"] as? String ?? ""
                    TokenManager.shared.save(access: token, refresh: refresh)

                    self.hasPassword = json["hasPassword"] as? Bool ?? true
                    self.hasUsername = json["hasUsername"] as? Bool ?? true

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isLoggedIn = true
                    }
                } else {
                    message = json["message"] as? String ?? "❌ Login failed"
                }
            }
        }.resume()
    }

    struct CustomInputField: View {
        var icon: String
        var placeholder: String
        @Binding var text: String
        var isSecure: Bool = false
        var keyboard: UIKeyboardType = .default

        @State private var isPasswordVisible = false

        var body: some View {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.gray)

                if isSecure {
                    Group {
                        if isPasswordVisible {
                            TextField(placeholder, text: $text)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                        } else {
                            SecureField(placeholder, text: $text)
                        }
                    }
                    Button(action: { isPasswordVisible.toggle() }) {
                        Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                            .foregroundColor(.gray)
                    }
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }
            }
            .padding()
            .background(Color.white.opacity(0.08))
            .cornerRadius(10)
            .foregroundColor(.white)
        }
    }
}
