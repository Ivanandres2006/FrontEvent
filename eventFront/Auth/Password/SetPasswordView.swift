import SwiftUI

struct SetPasswordView: View {
    @AppStorage("isLoggedIn") var isLoggedIn = false
    @AppStorage("hasPassword") var hasPassword = false
    @AppStorage("hasUsername") private var hasUsername = false

    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var message = ""
    @State private var isLoading = false
    @State private var animate = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                VStack(spacing: 30) {
                    Spacer()

                    Text("🔐 Set Password")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .opacity(animate ? 1 : 0)
                        .offset(y: animate ? 0 : -10)
                        .animation(.easeOut(duration: 0.5).delay(0.1), value: animate)

                    VStack(spacing: 16) {
                        CustomInputField(
                            icon: "lock",
                            placeholder: "New Password",
                            text: $newPassword,
                            isSecure: true
                        )
                        CustomInputField(
                            icon: "lock.fill",
                            placeholder: "Confirm Password",
                            text: $confirmPassword,
                            isSecure: true
                        )
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
                            .progressViewStyle(CircularProgressViewStyle(tint: .neonGreen))
                    } else {
                        Button(action: setPassword) {
                            Text("Save Password")
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.neonGreen)
                                .foregroundColor(.black)
                                .cornerRadius(12)
                        }
                        .disabled(newPassword.count < 6 || newPassword != confirmPassword)
                        .opacity(animate ? 1.0 : 0)
                        .animation(.easeOut(duration: 0.5).delay(0.3), value: animate)
                    }

                    Spacer()
                }
                .padding(.horizontal, 30)
                .onAppear { animate = true }
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    func setPassword() {
        guard newPassword == confirmPassword else {
            message = "❌ Passwords do not match"
            return
        }

        guard let token = TokenManager.shared.getAccessToken() else {
            message = "❌ Not logged in"
            return
        }

        isLoading = true
        message = ""

        let url = URL(string: "http://localhost:8080/auth/set-password")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["newPassword": newPassword]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                isLoading = false
                message = "✅ Password set successfully!"
                hasPassword = true // 🟢 mark they now have a password
                isLoggedIn = true // ✅ instantly switch to home
            }
        }.resume()
    }

    struct CustomInputField: View {
        var icon: String
        var placeholder: String
        @Binding var text: String
        var isSecure: Bool = false
        var keyboard: UIKeyboardType = .default

        var body: some View {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.gray)
                if isSecure {
                    SecureField(placeholder, text: $text)
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
