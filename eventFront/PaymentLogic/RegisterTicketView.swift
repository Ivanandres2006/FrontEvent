import SwiftUI
import Stripe
import StripePaymentSheet

struct RegisterTicketView: View {
    @AppStorage("selectedLanguage") var lang: String = "en"
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
    
    @State private var showPaymentPopup = false
    @State private var selectedPaymentMethod: String = "card" // or "zelle"
    @State private var isZelleAvailable: Bool = false


    var selectedTier: TicketTier? {
        event.ticketTiers.first(where: { $0.id == selectedTierId })
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 28) {
                    // 🔹 Header
                    VStack(spacing: 6) {
                        Text(lang == "es" ? "🎟️ Registrarse para" : "🎟️ Register for")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                        
                        Text(event.title)
                            .font(.title.bold())
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white)
                    }
                    
                    let sortedTiers = event.ticketTiers.sorted(by: { ($0.tierOrder ?? 0) < ($1.tierOrder ?? 0) })
                    let now = Date()
                    
                    let hasAvailableTier = sortedTiers.contains { tier in
                        let isSoldOut = (tier.availableQuantity ?? 0) == 0
                        let startLocked = tier.startTime.map { now < $0 } ?? false
                        let endLocked = tier.endTime.map { now > $0 } ?? false
                        let isLockedByTime = startLocked || endLocked
                        let shouldBeLockedByOrder = tier.id != nextAvailableTierId()
                        return !(isSoldOut || isLockedByTime || shouldBeLockedByOrder)
                    }
                    
                    if sortedTiers.isEmpty || !hasAvailableTier {
                        VStack(spacing: 32) {
                            Spacer(minLength: 100)
                            
                            VStack(spacing: 12) {
                                Image(systemName: "nosign")
                                    .font(.system(size: 48))
                                    .foregroundColor(.red)
                                
                                Text(lang == "es"
                                     ? "Este evento no tiene entradas disponibles"
                                     : "This event has no available tickets")
                                .font(.title2.bold())
                                .multilineTextAlignment(.center)
                                .foregroundColor(.white)
                                .padding(.horizontal)
                            }
                            
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // 🔹 Ticket Tier Selector
                        VStack(alignment: .leading, spacing: 14) {
                            Text(lang == "es" ? "Selecciona un Nivel de Entrada" : "Select a Ticket Tier")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            ForEach(sortedTiers, id: \.id) { tier in
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
                                            
                                            Text(
                                                lang == "es"
                                                ? "$\(tier.price, specifier: "%.2f") • \(tier.availableQuantity ?? 0) disponibles"
                                                : "$\(tier.price, specifier: "%.2f") • \(tier.availableQuantity ?? 0) left"
                                            )
                                            .font(.caption)
                                            .foregroundColor(isUnavailable ? .gray.opacity(0.6) : .white.opacity(0.7))
                                            
                                            if isSoldOut {
                                                Text(lang == "es" ? "❌ Agotado" : "❌ Sold Out")
                                                    .font(.caption2)
                                                    .foregroundColor(.red)
                                            } else if isLockedByTime {
                                                Text(lang == "es" ? "⏰ Aún no disponible" : "⏰ Not yet available")
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
                                                .foregroundColor(.gold)
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
                                                .stroke(isSelected && !isUnavailable ? Color.gold : Color.clear, lineWidth: 1.5)
                                        )
                                )
                                .opacity(isUnavailable ? 0.4 : 1.0)
                                .onTapGesture {
                                    if !isUnavailable {
                                        selectedTierId = tier.id
                                    }
                                }
                                .onAppear {
                                    isZelleAvailable = !(event.zelleEmail?.isEmpty ?? true) || !(event.zellePhone?.isEmpty ?? true)
                                }
                            }
                        }
                        
                        // 🔹 Quantity and Total
                        VStack(spacing: 8) {
                            Stepper(
                                lang == "es" ? "Cantidad: \(quantity)" : "Quantity: \(quantity)",
                                value: $quantity,
                                in: 1...10
                            )
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(12)
                            
                            if let tier = selectedTier {
                                Text(
                                    lang == "es"
                                    ? "Total: $\(Double(quantity) * tier.price, specifier: "%.2f")"
                                    : "Total: $\(Double(quantity) * tier.price, specifier: "%.2f")"
                                )
                                .foregroundColor(.white)
                                .font(.subheadline)
                                .padding(.top, 4)
                            }
                        }
                        
                        let hasNonCardPayments = isZelleAvailable ||
                            (event.country.lowercased() == "venezuela" &&
                             ((event.allowPagoMovil ?? false) || (event.allowCash ?? false)))
                        
                        // 🔹 Pay Now Button
                        Button {
                            if hasNonCardPayments {
                                    showPaymentPopup = true
                                    selectedPaymentMethod = "card"
                                } else {
                                    startCheckout()
                                }
                        } label: {
                            HStack {
                                Spacer()
                                Text(isLoading
                                     ? (lang == "es" ? "Procesando..." : "Processing...")
                                     : (lang == "es" ? "Pagar Ahora" : "Pay Now"))
                                    .fontWeight(.bold)
                                    .padding(.vertical, 12)
                                    .foregroundColor(.black)
                                Spacer()
                            }
                            .background(isLoading ? Color.gray : Color.gold)
                            .cornerRadius(16)
                        }
                        .disabled(isLoading || selectedTier == nil)

                    }
                    
                    // 🔺 Error Message
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
                
                if showPaymentPopup {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .onTapGesture { showPaymentPopup = false }

                    VStack(spacing: 18) {
                        Text("💰 " + (lang == "es" ? "Total a Pagar" : "Total to Pay"))
                            .font(.title3.bold())
                            .foregroundColor(.white)

                        if let tier = selectedTier {
                            Text("$\(Double(quantity) * tier.price, specifier: "%.2f")")
                                .font(.largeTitle.bold())
                                .foregroundColor(.gold)
                        }

                        // 👉 Selectable Buttons
                        VStack(spacing: 12) {
                            // Zelle Button
                            Button {
                                selectedPaymentMethod = "zelle"
                            } label: {
                                HStack {
                                    Image(systemName: "banknote.fill")
                                    Text(lang == "es" ? "Contribuir con Zelle" : "Pay with Zelle")
                                }
                                .foregroundColor(selectedPaymentMethod == "zelle" ? .black : .white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(selectedPaymentMethod == "zelle" ? Color.gold : Color.white.opacity(0.1))
                                .cornerRadius(14)
                            }

                            if selectedPaymentMethod == "zelle" {
                                VStack(spacing: 4) {
                                    if let email = event.zelleEmail, !email.isEmpty {
                                        HStack {
                                            Image(systemName: "envelope")
                                            Text(email)
                                        }
                                        .foregroundColor(.white)
                                    }
                                    if let phone = event.zellePhone, !phone.isEmpty {
                                        HStack {
                                            Image(systemName: "phone")
                                            Text(phone)
                                        }
                                        .foregroundColor(.white)
                                    }

                                    Text(lang == "es"
                                         ? "Después de pagar por Zelle, toca Pagar abajo para notificar al organizador."
                                         : "After sending your Zelle payment, tap Pay below to notify the organizer.")
                                        .font(.footnote)
                                        .foregroundColor(.white.opacity(0.6))
                                        .multilineTextAlignment(.center)
                                        .padding(.top, 4)
                                }
                            }
                            
                            if event.country.lowercased() == "venezuela" && (event.allowPagoMovil ?? false) {
                                Button {
                                    selectedPaymentMethod = "pagoMovil"
                                } label: {
                                    HStack {
                                        Image(systemName: "iphone.gen3")
                                        Text(lang == "es" ? "Pago Móvil" : "Pago Móvil")
                                    }
                                    .foregroundColor(selectedPaymentMethod == "pagoMovil" ? .black : .white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(selectedPaymentMethod == "pagoMovil" ? Color.gold : Color.white.opacity(0.1))
                                    .cornerRadius(14)
                                }
                            }

                            if event.country.lowercased() == "venezuela" && (event.allowCash ?? false) {
                                Button {
                                    selectedPaymentMethod = "cash"
                                } label: {
                                    HStack {
                                        Image(systemName: "banknote")
                                        Text(lang == "es" ? "Pagar en Efectivo" : "Pay with Cash")
                                    }
                                    .foregroundColor(selectedPaymentMethod == "cash" ? .black : .white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(selectedPaymentMethod == "cash" ? Color.gold : Color.white.opacity(0.1))
                                    .cornerRadius(14)
                                }
                            }
                            
                            if selectedPaymentMethod == "pagoMovil" {
                                VStack(spacing: 6) {
                                    if let phone = event.pagoMovilPhone {
                                        Text("📱 \(phone)").foregroundColor(.white)
                                    }
                                    if let ci = event.pagoMovilCi {
                                        Text("🪪 C.I.: \(ci)").foregroundColor(.white)
                                    }
                                    if let bank = event.pagoMovilBank {
                                        Text("🏦 \(bank)").foregroundColor(.white)
                                    }
                                    Text(lang == "es"
                                         ? "Después de pagar por Pago Móvil, toca Pagar abajo para notificar al organizador."
                                         : "After sending your Pago Móvil payment, tap Pay below to notify the organizer.")
                                    .font(.footnote)
                                    .foregroundColor(.white.opacity(0.6))
                                    .multilineTextAlignment(.center)
                                }
                            }

                            if selectedPaymentMethod == "cash", let note = event.cashNote {
                                VStack(spacing: 6) {
                                    Text("📝 " + note)
                                        .font(.footnote)
                                        .foregroundColor(.white)
                                        .multilineTextAlignment(.center)
                                    Text(lang == "es"
                                         ? "Toca Pagar abajo para notificar al organizador."
                                         : "Tap Pay below to notify the organizer.")
                                    .font(.footnote)
                                    .foregroundColor(.white.opacity(0.6))
                                }
                            }

                            

                            // Card Button
                            Button {
                                selectedPaymentMethod = "card"
                            } label: {
                                HStack {
                                    Image(systemName: "creditcard.fill")
                                    Text(lang == "es" ? "Pagar con Tarjeta" : "Pay with Card")
                                }
                                .foregroundColor(selectedPaymentMethod == "card" ? .black : .white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(selectedPaymentMethod == "card" ? Color.gold : Color.white.opacity(0.1))
                                .cornerRadius(14)
                            }
                        }

                        // Final Action Button
                        Button {
                            showPaymentPopup = false
                            startCheckout() // always call this for all payment methods
                        } label: {
                            Text(lang == "es" ? "Pagar" : "Pay")
                                .fontWeight(.bold)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.gold)
                                .foregroundColor(.black)
                                .cornerRadius(16)
                        }

                        // Cancel
                        Button(action: { showPaymentPopup = false }) {
                            Text(lang == "es" ? "Cancelar" : "Cancel")
                                .foregroundColor(.white.opacity(0.6))
                        }

                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(22)
                    .padding()
                    .frame(maxWidth: 350)
                }
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

        let url = URL(string: "https://backendevent-etce.onrender.com/api/tickets/checkout")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let payload: [String: Any] = [
            "eventId": event.id,
            "ticketTierId": tier.id,
            "quantity": quantity,
            "email": userEmail,
            "paymentMethod": selectedPaymentMethod
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

            // ✅ Free ticket success
            if let isFree = json["free"] as? Bool, isFree {
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

            // ✅ Manual payment: Zelle, PagoMovil, or Cash
            if let isManual = json["manual"] as? Bool, isManual {
                DispatchQueue.main.async {
                    self.message = lang == "es"
                        ? "✅ Hemos notificado al organizador. Espera confirmación."
                        : "✅ We've notified the organizer. Wait for confirmation."
                    self.fetchTickets()
                }
                return
            }

            // ✅ Stripe flow
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

        var request = URLRequest(url: URL(string: "https://backendevent-etce.onrender.com/api/tickets/confirm?paymentIntentId=\(paymentIntentId)")!)
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

        let url = URL(string: "https://backendevent-etce.onrender.com/api/tickets/my?email=\(userEmail)")!
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
