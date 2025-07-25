import SwiftUI

struct SetUsernameView: View {
    @AppStorage("isLoggedIn") var isLoggedIn = false
    @AppStorage("hasUsername") var hasUsername = false
    @AppStorage("selectedLanguage") var lang: String = "en"

    @State private var username = ""
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

                    Text(lang == "es" ? "👤 Elige tu nombre de usuario" : "👤 Choose Username")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .opacity(animate ? 1 : 0)
                        .offset(y: animate ? 0 : -10)
                        .animation(.easeOut(duration: 0.5).delay(0.1), value: animate)

                    VStack(spacing: 16) {
                        CustomInputField(
                            icon: "person.crop.circle",
                            placeholder: lang == "es" ? "Nombre de usuario" : "Username",
                            text: $username,
                            keyboard: .default
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
                            .progressViewStyle(CircularProgressViewStyle(tint: Color.gold))
                    } else {
                        Button(action: setUsername) {
                            Text(lang == "es" ? "Guardar nombre de usuario" : "Save Username")
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.gold)
                                .foregroundColor(.black)
                                .cornerRadius(12)
                        }
                        .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty)
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

    func setUsername() {
        guard let token = TokenManager.shared.getAccessToken() else {
            message = "❌ Not logged in"
            return
        }

        isLoading = true
        message = ""

        let url = URL(string: "https://backendevent-etce.onrender.com/auth/set-username")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["username": username.trimmingCharacters(in: .whitespaces)]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                isLoading = false

                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let msg = json["message"] as? String {
                    if msg.contains("✅") {
                        message = msg
                        hasUsername = true
                        isLoggedIn = true
                    } else {
                        message = "❌ \(msg)"
                    }
                } else {
                    message = "❌ Unexpected error"
                }
            }
        }.resume()
    }

    struct CustomInputField: View {
        var icon: String
        var placeholder: String
        @Binding var text: String
        var keyboard: UIKeyboardType = .default

        var body: some View {
            HStack {
                Image(systemName: icon).foregroundColor(.gray)

                TextField(placeholder, text: $text)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
            }
            .padding()
            .background(Color.white.opacity(0.08))
            .cornerRadius(10)
            .foregroundColor(.white)
        }
    }
}
