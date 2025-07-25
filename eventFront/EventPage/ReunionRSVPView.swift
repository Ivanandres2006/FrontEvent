import SwiftUI

struct ReunionRSVPView: View {
    @AppStorage("selectedLanguage") var lang: String = "en"
    let eventId: Int
    let title: String
    let location: String
    let dateTime: String
    var onComplete: (() -> Void)? = nil

    @State private var submitted = false
    @State private var message = ""

    var body: some View {
        ZStack {
            // Fullscreen blurred background
            Color.clear
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            // RSVP card
            VStack(spacing: 20) {
                Text(title)
                    .font(.title2.bold())
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text("📍 \(location)")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))

                Text("📋 \(formattedDate(dateTime))")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))

                HStack(spacing: 16) {
                    Button(action: {
                        submitRsvp(attending: true)
                    }) {
                        HStack {
                            Text("🎉")
                            Text(lang == "es" ? "Si puedo!" :"I'm attending").bold()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                    }

                    Button(action: {
                        submitRsvp(attending: false)
                    }) {
                        HStack {
                            Text("❌")
                            Text(lang == "es" ?"No puedo" :"Can't attend").bold()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                    }
                }

                if submitted {
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.top, 6)
                }
            }
            .padding()
            .frame(maxWidth: 360)
            .background(Color.black.opacity(0.9))
            .cornerRadius(24)
            .padding()
            .shadow(radius: 20)
        }
    }

    func submitRsvp(attending: Bool) {
        guard let token = TokenManager.shared.getAccessToken() else {
            print("❌ Missing token")
            return
        }

        let url = URL(string: "https://backendevent-etce.onrender.com/events/\(eventId)/rsvp")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Bool] = ["attending": attending]
        request.httpBody = try? JSONEncoder().encode(body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                submitted = true

                if let error = error {
                    message = "Error: \(error.localizedDescription)"
                    print("❌ RSVP failed: \(error.localizedDescription)")
                    return
                }

                if let httpResponse = response as? HTTPURLResponse {
                    print("📨 RSVP status: \(httpResponse.statusCode)")
                }

                message = attending
                    ? (lang == "es" ? "✅ ¡Asistirás al evento!" : "✅ You're attending!")
                    : (lang == "es" ? "❌ RSVP rechazado." : "❌ RSVP declined.")

                // Auto-dismiss after short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    onComplete?()
                }
            }
        }.resume()
    }

    func formattedDate(_ iso: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let date = formatter.date(from: iso) else { return iso }

        let output = DateFormatter()
        output.dateFormat = "MMM d 'at' h:mm a"
        return output.string(from: date)
    }
}
