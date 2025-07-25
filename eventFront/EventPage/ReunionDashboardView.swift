import SwiftUI
import Stripe
import StripePaymentSheet

struct ReunionDashboardView: View {
    @AppStorage("selectedLanguage") var lang: String = "en"
    @EnvironmentObject var userSession: UserSession
    var budgetGoal: Double
    var attendees: [ReunionGuest]
    var isOwner: Bool
    var eventId: Int

    @State private var isLoading = false
    @State private var message = ""
    @State private var paymentSheet: PaymentSheet?
    @State private var guests: [ReunionGuest] = []

    var body: some View {
        VStack(spacing: 24) {
            Text(lang == "es" ? "📊 Panel de la Reunión" : "📊 Reunion Dashboard")
                .font(.largeTitle.bold())
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Summary Section
            VStack(alignment: .leading, spacing: 14) {
                Text(lang == "es" ? "💰 Resumen del Presupuesto" : "💰 Budget Summary")
                    .font(.headline)
                    .foregroundColor(.white)

                HStack {
                    summaryCard(
                        title: lang == "es" ? "Total" : "Total",
                        value: String(format: "$%.2f", budgetGoal),
                        icon: "dollarsign.circle.fill",
                        color: .mint
                    )

                    summaryCard(
                        title: lang == "es" ? "Por Persona" : "Per Person",
                        value: String(format: "$%.2f", budgetPerGuest()),
                        icon: "person.fill",
                        color: .gold
                    )

                    summaryCard(
                        title: lang == "es" ? "Pagado" : "Paid",
                        value: "\(paidCount())/\(guests.count)",
                        icon: "checkmark.seal.fill",
                        color: .green
                    )
                }
            }

            Divider().background(Color.white.opacity(0.2))

            // Guest List Section
            VStack(alignment: .leading, spacing: 14) {
                Text(lang == "es" ? "👥 Contribuciones de los Invitados" : "👥 Guest Contributions")
                    .font(.headline)
                    .foregroundColor(.white)

                if guests.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.4))
                        Text(lang == "es" ? "👥 Contribuciones de los Invitados" : "👥 Guest Contributions")
                            .foregroundColor(.white.opacity(0.5))
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(guests.indices, id: \.self) { i in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(guests[i].name)
                                            .font(.headline)
                                            .foregroundColor(.white)
                                        Text(guests[i].email)
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.5))
                                    }

                                    Spacer()

                                    if isOwner {
                                        Button {
                                                guests[i].paid.toggle()
                                                updatePaidStatus(email: guests[i].email, paid: guests[i].paid)
                                            } label: {
                                                Image(systemName: guests[i].paid ? "checkmark.circle.fill" : "xmark.circle")
                                                    .foregroundColor(guests[i].paid ? .green : .red)
                                                    .font(.title3)
                                            }
                                    } else {
                                        if guests[i].email == userSession.email {
                                            if guests[i].paid {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.green)
                                                    .font(.title3)
                                            } else {
                                                Button {
                                                    startCheckout()
                                                } label: {
                                                    Text(lang == "es" ? "Pagar" : "Pay")
                                                        .font(.caption)
                                                        .padding(.horizontal, 10)
                                                        .padding(.vertical, 6)
                                                        .background(Color.gold)
                                                        .foregroundColor(.black)
                                                        .cornerRadius(8)
                                                }
                                            }
                                        } else {
                                            Image(systemName: guests[i].paid ? "checkmark.circle.fill" : "circle")
                                                .foregroundColor(guests[i].paid ? .green : .gray)
                                                .font(.title3)
                                        }
                                    }
                                }
                                .padding()
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(12)
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 30)
        }
        .padding()
        .background(LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .onAppear {
            self.guests = attendees
        }
    }

    // MARK: - Helpers

    func summaryCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            Text(title)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
            Text(value)
                .font(.headline)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }

    func budgetPerGuest() -> Double {
        let totalGuests = max(guests.count + 1, 1)
        return budgetGoal / Double(totalGuests)
    }

    private func presentPaymentSheet(paymentIntentId: String) {
        guard let sheet = paymentSheet else {
            message = "Payment sheet not ready."
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let topVC = topViewController() {
                if topVC.presentedViewController != nil {
                    // Retry logic if needed
                    return
                }
                
                sheet.present(from: topVC) { result in
                    paymentSheet = nil

                    switch result {
                    case .completed:
                        if let guestIndex = guests.firstIndex(where: { $0.email == userSession.email }) {
                            guests[guestIndex].paid = true
                        }
                        updatePaidStatus(email: userSession.email, paid: true)
                    case .canceled:
                        message = "❌ Payment canceled"
                    case .failed(let error):
                        message = "❌ Payment failed: \(error.localizedDescription)"
                    }
                }
            } else {
                message = "Couldn't find view controller"
            }
        }
    }

    private func topViewController(controller: UIViewController? = UIApplication.shared
        .connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first(where: { $0.isKeyWindow })?.rootViewController) -> UIViewController? {

        if let nav = controller as? UINavigationController {
            return topViewController(controller: nav.visibleViewController)
        }
        if let tab = controller as? UITabBarController {
            return topViewController(controller: tab.selectedViewController)
        }
        if let presented = controller?.presentedViewController {
            return topViewController(controller: presented)
        }
        return controller
    }

    
    func paidCount() -> Int {
        guests.filter { $0.paid }.count
    }

    func startCheckout() {
        guard let token = TokenManager.shared.getAccessToken() else { return }

        let email = userSession.email
        let urlString = "https://backendevent-etce.onrender.com/api/payments/reunion-checkout?eventId=\(eventId)&email=\(email)"

        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                print("❌ Stripe error: \(error)")
                return
            }

            guard let data = data else {
                print("❌ No data returned from server")
                return
            }

            if let raw = String(data: data, encoding: .utf8) {
                print("🧾 Raw response:")
                print(raw)
            }

            guard let response = try? JSONDecoder().decode(PaymentSheetResponse.self, from: data) else {
                print("❌ Failed to decode payment response")
                return
            }

            var config = PaymentSheet.Configuration()
            config.merchantDisplayName = "WKND"
            config.primaryButtonColor = .systemPink

            DispatchQueue.main.async {
                paymentSheet = PaymentSheet(paymentIntentClientSecret: response.clientSecret, configuration: config)

                if let intentId = extractPaymentIntentId(from: response.clientSecret) {
                    presentPaymentSheet(paymentIntentId: intentId)
                }
            }
        }.resume()
    }


    
    private func extractPaymentIntentId(from clientSecret: String) -> String? {
        return clientSecret.components(separatedBy: "_secret").first
    }

    func updatePaidStatus(email: String, paid: Bool) {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/events/\(eventId)/update-guest") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = GuestUpdateRequest(email: email, paid: paid)
        request.httpBody = try? JSONEncoder().encode(body)

        URLSession.shared.dataTask(with: request) { _, _, error in
            if let error = error {
                print("❌ Update guest failed: \(error)")
            } else {
                print("✅ Updated guest paid status for \(email)")
            }
        }.resume()
    }
}

struct GuestUpdateRequest: Encodable {
    let email: String
    let paid: Bool
}

struct PaymentSheetResponse: Decodable {
    let clientSecret: String
}
