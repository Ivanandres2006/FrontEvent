import SwiftUI

struct EmailVerificationView: View {
    let email: String
    @AppStorage("isLoggedIn") private var isLoggedIn = false
    @AppStorage("selectedLanguage") var lang: String = "en"
    
    @State private var code = ""
    @State private var message = ""
    @State private var isLoading = false
    @State private var showSplash = false
    @State private var animate = false
    @State private var canResend = true
    @State private var resendCooldown = 0

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                VStack(spacing: 28) {
                    Spacer()

                    Image(systemName: "envelope.badge")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .foregroundColor(.gold)
                        .scaleEffect(animate ? 1.0 : 0.7)
                        .opacity(animate ? 1.0 : 0)
                        .animation(.easeOut(duration: 0.6), value: animate)

                    Text(lang == "es" ? "Verifique su correo electrónico" : "Verify Your Email")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .opacity(animate ? 1.0 : 0)
                        .offset(y: animate ? 0 : -10)
                        .animation(.easeOut(duration: 0.5).delay(0.1), value: animate)

                    Text(lang == "es" ? "Te enviamos un codigo a:": "We sent a code to:")
                        .foregroundColor(.gray)
                        .font(.subheadline)

                    Text(email)
                        .foregroundColor(.white)
                        .font(.body)
                        .multilineTextAlignment(.center)

                    TextField(lang == "es" ? "Introduzca el código de verificación" : "Enter verification code", text: $code)
                        .padding()
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(10)
                        .foregroundColor(.white)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)

                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .gold))
                    } else {
                        Button(lang == "es" ? "Verificar correo electrónico" : "Verify Email") {
                            verifyCode()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gold)
                        .foregroundColor(.black)
                        .cornerRadius(12)

                        Button {
                            resendCode()
                        } label: {
                            Text(resendCooldown > 0
                                 ? (lang == "es" ? "Reenviar en \(resendCooldown)s..." : "Resend in \(resendCooldown)s...")
                                 : (lang == "es" ? "Reenviar código" : "Resend Code"))
                        }
                        .disabled(!canResend)
                        .foregroundColor(canResend ? .gray : .gray.opacity(0.5))
                        .font(.footnote)
                    }

                    if !message.isEmpty {
                        Text(message)
                            .foregroundColor(message.contains("✅") ? .green : .red)
                            .font(.subheadline)
                    }

                    Spacer()
                }
                .padding(.horizontal, 30)
                .onAppear {
                    animate = true
                    //resendCode()
                }
            }
            .fullScreenCover(isPresented: $showSplash) {
                LoginView()
            }
        }
    }

    func verifyCode() {
        guard let url = URL(string: "https://backendevent-etce.onrender.com/auth/verify") else { return }

        let body: [String: Any] = [
            "email": email,
            "code": code
        ]

        let jsonData = try? JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        isLoading = true

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    message = "❌ Server error or no response"
                    return
                }

                if let accessToken = json["accessToken"] as? String,
                   let refreshToken = json["refreshToken"] as? String {
                    TokenManager.shared.save(access: accessToken, refresh: refreshToken)
                    message = "✅ Verified!"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        showSplash = true
                    }
                } else if let backendMsg = json["message"] as? String {
                    message = "❌ \(backendMsg)"
                } else {
                    message = "❌ Invalid code. Please try again."
                }
            }
        }.resume()
    }

    func resendCode() {
        guard canResend else { return }

        canResend = false
        resendCooldown = 5

        // Countdown timer
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            if resendCooldown > 1 {
                resendCooldown -= 1
            } else {
                timer.invalidate()
                resendCooldown = 0
                canResend = true
            }
        }

        guard let url = URL(string: "https://backendevent-etce.onrender.com/auth/resend") else { return }

        let body: [String: Any] = [
            "email": email,
            "useSms": false
        ]

        let jsonData = try? JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    message = "❌ Error: \(error.localizedDescription)"
                    return
                }

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let backendMsg = json["message"] as? String else {
                    message = "❌ Unexpected server response."
                    return
                }

                message = "✅ \(backendMsg)"
                code = ""
            }
        }.resume()
    }

}

