import SwiftUI

struct ResetPasswordView: View {
    @AppStorage("selectedLanguage") var lang: String = "en"
    let email: String
    let code: String

    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var message = ""
    @State private var isLoading = false
    @State private var animate = false
    @State private var goToLogin = false

    var body: some View {
            ZStack {
                LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                VStack(spacing: 30) {
                    Spacer()

                    Text(lang == "es" ? "🔒 Reiniciar Clave": "🔒 Reset Password")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .opacity(animate ? 1.0 : 0)
                        .offset(y: animate ? 0 : -10)
                        .animation(.easeOut(duration: 0.5).delay(0.1), value: animate)

                    VStack(spacing: 16) {
                        SecureInputField(placeholder: lang == "es" ? "Nueva Clave": "New Password", text: $newPassword)
                        SecureInputField(placeholder: lang == "es" ? "Confirmar Clave":  "Confirm Password", text: $confirmPassword)
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
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color.gold))
                    } else {
                        Button(lang == "es" ? "Reiniciar Clave": "Reset Password") {
                            resetPassword()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gold)
                        .foregroundColor(.black)
                        .cornerRadius(12)
                        .opacity(animate ? 1.0 : 0)
                        .animation(.easeOut(duration: 0.5).delay(0.3), value: animate)
                    }

                    Spacer()
                }
                .padding(.horizontal, 30)
                .onAppear {
                    animate = true
                }
                .navigationBarBackButtonHidden(true)
            }
            .fullScreenCover(isPresented: $goToLogin) {
                LoginView()
            }
        .navigationBarBackButtonHidden(true)
    }

    func resetPassword() {
        guard !newPassword.isEmpty, !confirmPassword.isEmpty else {
            message = "❌ Please fill in both password fields."
            return
        }

        guard newPassword == confirmPassword else {
            message = "❌ Passwords do not match."
            return
        }

        guard let url = URL(string: "https://backendevent-etce.onrender.com/auth/reset-password") else { return }

        let body: [String: Any] = [
            "email": email,
            "code": code,
            "newPassword": newPassword
        ]

        let jsonData = try? JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        isLoading = true
        message = ""

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let msg = json["message"] as? String else {
                    message = "❌ Server error"
                    return
                }

                if let status = (response as? HTTPURLResponse)?.statusCode, status == 200 {
                    message = "✅ \(msg)"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        goToLogin = true
                    }
                } else {
                    message = "❌ \(msg)"
                }
            }
        }.resume()
    }

    struct SecureInputField: View {
        let placeholder: String
        @Binding var text: String

        var body: some View {
            SecureField(placeholder, text: $text)
                .padding()
                .background(Color.white.opacity(0.08))
                .cornerRadius(10)
                .foregroundColor(.white)
        }
    }
}
