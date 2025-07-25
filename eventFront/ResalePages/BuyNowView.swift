import SwiftUI
import Stripe
import StripePaymentSheet

struct BuyNowView: View {
    @AppStorage("selectedLanguage") var lang: String = "en"
    let resalePost: ResalePostDTO
    @Binding var event: Event
    let userEmail: String
    var onComplete: () -> Void

    @Environment(\.dismiss) var dismiss

    @State private var isLoading = false
    @State private var paymentSheet: PaymentSheet?
    @State private var isPaymentSheetPresented = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    @State private var retryCount = 0
    @State private var isEventLoaded = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            if isEventLoaded {
                VStack(spacing: 30) {
                    VStack(spacing: 10) {
                        Text(lang == "es" ? "Comprar Entrada" : "Buy Ticket")
                            .font(.largeTitle.bold())
                            .foregroundColor(.white)

                        Text(resalePost.title)
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.8))

                        Text(
                            lang == "es"
                                ? "De \(resalePost.sellerName)"
                                : "From \(resalePost.sellerName)"
                        )
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.5))
                    }

                    Text(String(format: "$%.2f", resalePost.price))
                        .font(.system(size: 48, weight: .black))
                        .foregroundColor(.gold)

                    if isLoading {
                        ProgressView(lang == "es" ? "Cargando Pantalla de Pago..." : "Loading Payment Sheet...")
                            .foregroundColor(.white)
                    } else {
                        Button {
                            paymentSheet == nil ? startCheckout() : presentPaymentSheet()
                        } label: {
                            Text(lang == "es" ? "Pagar Ahora" : "Pay Now")
                                .font(.headline)
                                .foregroundColor(.black)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.gold)
                                .cornerRadius(14)
                        }
                    }

                    Spacer()
                }
                .padding()
            } else {
                ProgressView(lang == "es" ? "Cargando Evento..." : "Loading Event...")
                    .foregroundColor(.white)
            }

            if showError {
                VStack {
                    Spacer()
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding()
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(10)
                        .padding(.bottom, 30)
                }
                .transition(.opacity)
            }

            if showSuccess {
                VStack(spacing: 20) {
                    Image(systemName: "checkmark.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .foregroundColor(.gold)

                    Text(lang == "es" ? "¡Compra Exitosa!" : "Purchase Successful!")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                }
                .padding()
                .background(Color.white.opacity(0.05))
                .cornerRadius(20)
                .padding()
                .transition(.scale)
            }
        }
        .animation(.easeInOut, value: showSuccess)
        .onAppear {
            fetchEventDetails()
        }
    }

    private func fetchEventDetails() {
        guard let token = TokenManager.shared.getAccessToken() else { return }

        let url = URL(string: "https://backendevent-etce.onrender.com/events/\(resalePost.eventId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data = data,
               let fetchedEvent = try? JSONDecoder().decode(Event.self, from: data) {
                DispatchQueue.main.async {
                    self.event = fetchedEvent
                    self.isEventLoaded = true
                }
            } else {
                DispatchQueue.main.async {
                    self.errorMessage = "Event not found"
                    self.showError = true
                }
            }
        }.resume()
    }

    private func startCheckout() {
        isLoading = true
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/api/resale/pay/\(resalePost.id)") else {
            self.isLoading = false
            self.errorMessage = "Invalid request"
            self.showError = true
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["email": userEmail])

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async { self.isLoading = false }

            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    self.errorMessage = "No response from server"
                    self.showError = true
                }
                return
            }

            if let result = try? JSONDecoder().decode(PaymentIntentResponse.self, from: data) {
                var config = PaymentSheet.Configuration()
                config.merchantDisplayName = "WKND Events"
                config.customer = .init(id: result.customerId, ephemeralKeySecret: result.ephemeralKey)
                config.primaryButtonColor = UIColor(Color.gold)

                DispatchQueue.main.async {
                    self.paymentSheet = PaymentSheet(paymentIntentClientSecret: result.clientSecret, configuration: config)
                    self.presentPaymentSheet()
                }
            } else {
                DispatchQueue.main.async {
                    self.errorMessage = "Unexpected server response"
                    self.showError = true
                }
            }
        }.resume()
    }

    private func presentPaymentSheet() {
        guard let sheet = paymentSheet else {
            self.errorMessage = "Payment sheet not ready"
            self.showError = true
            return
        }

        if isPaymentSheetPresented { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let topVC = topViewController() {
                if topVC.presentedViewController != nil {
                    if retryCount < 3 {
                        retryCount += 1
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            self.presentPaymentSheet()
                        }
                        return
                    } else {
                        self.errorMessage = "Couldn't open payment screen. Try again later."
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
                        confirmBackendTransfer()
                    case .canceled:
                        errorMessage = "Payment canceled"
                        showError = true
                    case .failed(let error):
                        errorMessage = "Payment failed: \(error.localizedDescription)"
                        showError = true
                    }
                }
            } else {
                errorMessage = "❌ Couldn't find root view controller"
                showError = true
            }
        }
    }

    private func confirmBackendTransfer() {
        guard let token = TokenManager.shared.getAccessToken() else {
            self.errorMessage = "Token missing"
            self.showError = true
            return
        }

        let url = URL(string: "https://backendevent-etce.onrender.com/api/resale/confirm-transfer/\(resalePost.id)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { _, response, _ in
            DispatchQueue.main.async {
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    fetchUpdatedTickets {
                        showSuccess = true
                        onComplete()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            dismiss()
                        }
                    }
                } else {
                    errorMessage = "Failed to confirm ticket transfer"
                    showError = true
                }
            }
        }.resume()
    }

    private func fetchUpdatedTickets(completion: @escaping () -> Void) {
        guard let token = TokenManager.shared.getAccessToken() else {
            errorMessage = "Token missing"
            showError = true
            return
        }

        let url = URL(string: "https://backendevent-etce.onrender.com/api/tickets/my?email=\(userEmail)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data = data,
               let tickets = try? JSONDecoder().decode([TicketDTO].self, from: data) {
                DispatchQueue.main.async {
                    if let newTicket = tickets.first(where: { $0.eventId == event.id }),
                       !$event.purchasedTickets.contains(where: { $0.id == newTicket.id }) {
                        event.purchasedTickets.append(newTicket)
                    }
                    completion()
                }
            } else {
                DispatchQueue.main.async {
                    errorMessage = "Failed to fetch updated tickets"
                    showError = true
                }
            }
        }.resume()
    }
}

// MARK: - Helper

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

// MARK: - Response Model

struct PaymentIntentResponse: Decodable {
    let clientSecret: String
    let customerId: String
    let ephemeralKey: String
}
