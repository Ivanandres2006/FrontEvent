import SwiftUI

struct VerifyResetCodeView: View {
    let email: String

    @State private var code = ""
    @State private var message = ""
    @State private var isLoading = false
    @State private var goToReset = false
    @State private var animate = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                VStack(spacing: 30) {
                    Spacer()

                    Text("✉️ Enter Reset Code")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .opacity(animate ? 1.0 : 0)
                        .offset(y: animate ? 0 : -10)
                        .animation(.easeOut(duration: 0.5).delay(0.1), value: animate)

                    VStack(spacing: 8) {
                        Text("We sent a verification code to:")
                            .foregroundColor(.gray)
                            .font(.subheadline)

                        Text(email)
                            .font(.body)
                            .foregroundStyle(.white)
                            .fontWeight(.medium)

                        TextField("Enter code", text: $code)
                            .padding()
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(10)
                            .foregroundColor(.white)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
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
                            .progressViewStyle(CircularProgressViewStyle(tint: Color.neonGreen))
                    } else {
                        Button("Verify Code") {
                            verifyCode()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.neonGreen)
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
                .fullScreenCover(isPresented: $goToReset) {
                    ResetPasswordView(email: email, code: code)
                }
            }
        }
    }

    func verifyCode() {
        guard let url = URL(string: "http://localhost:8080/auth/verify-reset-code") else { return }

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
                    goToReset = true
                } else {
                    message = "❌ \(msg)"
                }
            }
        }.resume()
    }
}
