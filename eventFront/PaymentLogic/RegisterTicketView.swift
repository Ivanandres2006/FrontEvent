import SwiftUI
import Stripe
import StripePaymentSheet

struct RegisterTicketView: View {
    let event: Event
    let userEmail: String
    var onComplete: ([TicketDTO]) -> Void

    @Environment(\.dismiss) var dismiss

    @State private var selectedTierId: Int?
    @State private var quantity = 1
    @State private var isLoading = false
    @State private var message = ""
    @State private var paymentSheet: PaymentSheet?
    @State private var isPaymentSheetPresented = false
    @State private var retryCount = 0
    @State private var showFreeTicketSuccess = false
    @Namespace private var animation

    var selectedTier: TicketTier? {
        event.ticketTiers.first(where: { $0.id == selectedTierId })
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 6) {
                        Text("🎟️ Register for")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))

                        Text(event.title)
                            .font(.title.bold())
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Select a Ticket Tier")
                            .font(.headline)
                            .foregroundColor(.white)

                        let sortedTiers = event.ticketTiers.sorted(by: { (a, b) in
                            (a.tierOrder ?? 0) < (b.tierOrder ?? 0)
                        })

                        ForEach(sortedTiers, id: \.id) { tier in
                            let now = Date()
                            let isSoldOut = (tier.availableQuantity ?? 0) == 0
                            let startLocked = tier.startTime.map { now < $0 } ?? false
                            let endLocked = tier.endTime.map { now > $0 } ?? false
                            let isLockedByTime = startLocked || endLocked
                            let shouldBeLockedByOrder = tier.id != nextAvailableTierId()
                            let isUnavailable = isSoldOut || isLockedByTime || shouldBeLockedByOrder
                            let isSelected = selectedTierId == tier.id

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(tier.name)
                                            .font(.headline)
                                            .foregroundColor(isUnavailable ? .gray : .white)

                                        Text("$\(tier.price, specifier: "%.2f") • \(tier.availableQuantity ?? 0) left")
                                            .font(.caption)
                                            .foregroundColor(isUnavailable ? .gray.opacity(0.6) : .white.opacity(0.7))

                                        if isSoldOut {
                                            Text("❌ Sold Out")
                                                .font(.caption2)
                                                .foregroundColor(.red)
                                        } else if isLockedByTime {
                                            Text("⏰ Not yet available")
                                                .font(.caption2)
                                                .foregroundColor(.orange)
                                        } else if let start = tier.startTime, let end = tier.endTime {
                                            Text("⏰ \(format(start)) - \(format(end))")
                                                .font(.caption2)
                                                .foregroundColor(.white.opacity(0.4))
                                        }
                                    }

                                    Spacer()

                                    if isSelected && !isUnavailable {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.neonGreen)
                                            .font(.title3)
                                    } else if isLockedByTime {
                                        Image(systemName: "lock.fill")
                                            .foregroundColor(.orange)
                                            .font(.title3)
                                    }
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(isUnavailable ? Color.white.opacity(0.02) : Color.white.opacity(0.05))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(isSelected && !isUnavailable ? Color.neonGreen : Color.clear, lineWidth: 1.5)
                                    )
                            )
                            .opacity(isUnavailable ? 0.4 : 1.0)
                            .onTapGesture {
                                if !isUnavailable {
                                    selectedTierId = tier.id
                                }
                            }
                        }
                    }

                    VStack(spacing: 8) {
                        Stepper("Quantity: \(quantity)", value: $quantity, in: 1...10)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(12)

                        if let tier = selectedTier {
                            Text("Total: $\(Double(quantity) * tier.price, specifier: "%.2f")")
                                .foregroundColor(.white)
                                .font(.subheadline)
                                .padding(.top, 4)
                        }
                    }

                    Button(action: startCheckout) {
                        HStack {
                            Spacer()
                            Text(isLoading ? "Processing..." : "Pay Now")
                                .fontWeight(.bold)
                                .padding(.vertical, 12)
                                .foregroundColor(.black)
                            Spacer()
                        }
                        .background(isLoading ? Color.gray : Color.neonGreen)
                        .cornerRadius(16)
                    }
                    .disabled(isLoading || selectedTier == nil)

                    if !message.isEmpty {
                        Text(message)
                            .foregroundColor(.red)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }

                    Spacer()
                }
                .padding()
            }
        }
    }

    private func startCheckout() {
        guard let tier = selectedTier else { return }
        guard let token = TokenManager.shared.getAccessToken() else {
            message = "❌ Not authenticated. Please log in again."
            return
        }

        isLoading = true
        message = ""

        let url = URL(string: "http://localhost:8080/api/tickets/checkout")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let payload: [String: Any] = [
            "eventId": event.id,
            "ticketTierId": tier.id,
            "quantity": quantity,
            "email": userEmail
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                isLoading = false
            }

            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async {
                    self.message = "Failed to get response."
                }
                return
            }

            if json["free"] as? String == "true" {
                DispatchQueue.main.async {
                    withAnimation {
                        self.showFreeTicketSuccess = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.fetchTickets()
                    }
                }
                return
            }

            guard let clientSecret = json["clientSecret"] as? String,
                  let paymentIntentId = extractPaymentIntentId(from: clientSecret) else {
                DispatchQueue.main.async {
                    self.message = "Failed to get client secret."
                }
                return
            }

            var config = PaymentSheet.Configuration()
            config.merchantDisplayName = "WKND Events"

            DispatchQueue.main.async {
                self.paymentSheet = PaymentSheet(paymentIntentClientSecret: clientSecret, configuration: config)
                self.presentPaymentSheet(paymentIntentId: paymentIntentId)
            }
        }.resume()
    }

    private func presentPaymentSheet(paymentIntentId: String) {
        guard let sheet = paymentSheet else {
            message = "Payment sheet not ready."
            return
        }

        if isPaymentSheetPresented {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let topVC = topViewController() {
                if topVC.presentedViewController != nil {
                    if retryCount < 3 {
                        retryCount += 1
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            self.presentPaymentSheet(paymentIntentId: paymentIntentId)
                        }
                        return
                    } else {
                        message = "Couldn't open payment screen. Try again later."
                        retryCount = 0
                        return
                    }
                }

                retryCount = 0
                isPaymentSheetPresented = true

                sheet.present(from: topVC) { result in
                    isPaymentSheetPresented = false
                    paymentSheet = nil

                    switch result {
                    case .completed:
                        confirmBackend(paymentIntentId: paymentIntentId)
                    case .canceled:
                        message = "❌ Payment canceled."
                    case .failed(let error):
                        message = "❌ Payment failed: \(error.localizedDescription)"
                    }
                }
            } else {
                message = "❌ Couldn't find view controller"
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

    private func confirmBackend(paymentIntentId: String) {
        guard let token = TokenManager.shared.getAccessToken() else {
            message = "Missing token for confirmation."
            return
        }

        var request = URLRequest(url: URL(string: "http://localhost:8080/api/tickets/confirm?paymentIntentId=\(paymentIntentId)")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { _, _, _ in
            fetchTickets()
        }.resume()
    }

    private func fetchTickets() {
        guard let token = TokenManager.shared.getAccessToken() else {
            message = "Token missing."
            return
        }

        let url = URL(string: "http://localhost:8080/api/tickets/my?email=\(userEmail)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                if let data = data,
                   let tickets = try? JSONDecoder().decode([TicketDTO].self, from: data) {
                    self.onComplete(tickets)
                    self.dismiss()
                } else {
                    self.message = "Failed to load tickets."
                }
            }
        }.resume()
    }

    private func extractPaymentIntentId(from clientSecret: String) -> String? {
        return clientSecret.components(separatedBy: "_secret").first
    }
    
    private func nextAvailableTierId() -> Int? {
        let sorted = event.ticketTiers.sorted(by: { ($0.tierOrder ?? 0) < ($1.tierOrder ?? 0) })
        return sorted.first(where: { ($0.availableQuantity ?? 0) > 0 })?.id
    }

    private func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }
}
