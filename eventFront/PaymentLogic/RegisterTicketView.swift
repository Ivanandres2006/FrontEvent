import SwiftUI
import Stripe
import StripePaymentSheet

struct RegisterTicketView: View {
    @AppStorage("selectedLanguage") var lang: String = "en"
    @State var event: Event
    @EnvironmentObject var userSession: UserSession
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
    
    @State private var showWaitlistPopup = false
    @State private var waitlistStatus: String? = nil // "pending", "approved", "denied"
    @State private var waitlistLoading = false

    @State private var showWaitlistStatusSheet = false
    @State private var waitlistSheetType: String? = nil // "pending" or "denied"
    @State private var autoDismissWorkItem: DispatchWorkItem?

    @State private var waitlistDragOffset: CGFloat = 0
    @State private var waitlistShouldHide: Bool = false
    
    @State private var isRefreshingEvent = false



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
                        NoTicketsView(lang: lang)
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
                                    let isListOnly = event.listOnly ?? false
                                    if !isUnavailable && isListOnly && waitlistStatus == "pending" {
                                        showWaitlistSheet(type: "pending")
                                    } else if !isUnavailable && isListOnly && waitlistStatus == "denied" {
                                        showWaitlistSheet(type: "denied")
                                    } else if !isUnavailable && (!isListOnly || waitlistStatus == "approved") {
                                        selectedTierId = tier.id
                                    }
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
                        
                        let hasNonCardPayments: Bool = {
                            let venezuela = event.country.lowercased() == "venezuela"
                            let altPayments = (event.allowPagoMovil ?? false) || (event.allowCash ?? false)
                            return isZelleAvailable || (venezuela && altPayments)
                        }()
                        
                        // 🔹 Pay Now Button
                        Button {
                            if hasNonCardPayments {
                                withAnimation {
                                    showPaymentPopup = true
                                }
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
                
                
                
            }
            
            if showPaymentPopup {
                ZStack {
                    // Dimmed background
                    Color.black.opacity(0.6)
                        .ignoresSafeArea()
                        .onTapGesture { showPaymentPopup = false }
                    
                    // Centered Modal Card
                    VStack(spacing: 18) {
                        Text("💰 " + (lang == "es" ? "Total a Pagar" : "Total to Pay"))
                            .font(.title3.bold())
                            .foregroundColor(.white)
                        
                        if let tier = selectedTier {
                            Text("$\(Double(quantity) * tier.price, specifier: "%.2f")")
                                .font(.largeTitle.bold())
                                .foregroundColor(.gold)
                        }
                        
                        // 👉 Payment Options (conditionally shown)
                        VStack(spacing: 12) {
                            if isZelleAvailable {
                                paymentOptionButton("zelle", icon: "banknote.fill", titleES: "Contribuir con Zelle", titleEN: "Pay with Zelle")
                            }
                            
                            if event.country.lowercased() == "venezuela" && (event.allowPagoMovil ?? false) {
                                paymentOptionButton("pagoMovil", icon: "iphone.gen3", titleES: "Pago Móvil", titleEN: "Pago Móvil")
                            }
                            
                            if event.country.lowercased() == "venezuela" && (event.allowCash ?? false) {
                                paymentOptionButton("cash", icon: "banknote", titleES: "Pagar en Efectivo", titleEN: "Pay with Cash")
                            }
                            
                            // Always show card
                            paymentOptionButton("card", icon: "creditcard.fill", titleES: "Pagar con Tarjeta", titleEN: "Pay with Card")
                        }
                        
                        // Info details based on selected method
                        paymentDetailsView()
                        
                        // Final Pay Button
                        Button {
                            showPaymentPopup = false
                            startCheckout()
                        } label: {
                            Text(lang == "es" ? "Pagar" : "Pay")
                                .fontWeight(.bold)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.gold)
                                .foregroundColor(.black)
                                .cornerRadius(16)
                        }
                        
                        // Cancel Button
                        Button(action: { showPaymentPopup = false }) {
                            Text(lang == "es" ? "Cancelar" : "Cancel")
                                .foregroundColor(.white.opacity(0.6))
                        }
                        
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(22)
                    .padding(.horizontal)
                    .frame(maxWidth: 350)
                }
                .transition(.scale)
                .zIndex(10)
            }
            
            if showWaitlistPopup {
                ZStack {
                    Color.black.opacity(0.6)
                        .ignoresSafeArea()
                        .onTapGesture { showWaitlistPopup = false }

                    VStack(spacing: 16) {
                        Text("📝 " + (lang == "es" ? "Este evento es con lista" : "This event uses a list"))
                            .font(.title3.bold())
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white)

                        Text(lang == "es"
                             ? "Debes solicitar acceso antes de poder registrarte. Notificaremos al organizador."
                             : "You must request access before registering. We’ll notify the organizer.")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white.opacity(0.7))

                        if waitlistStatus == nil {
                            Button {
                                sendWaitlistRequest()
                            } label: {
                                if waitlistLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    Text(lang == "es" ? "Solicitar Acceso" : "Request Access")
                                        .bold()
                                        .padding()
                                        .frame(maxWidth: .infinity)
                                        .background(Color.gold)
                                        .foregroundColor(.black)
                                        .cornerRadius(14)
                                }
                            }
                        } else {
                            let msg = waitlistStatus == "pending"
                                ? (lang == "es" ? "⏳ Solicitud Enviada" : "⏳ Request Sent")
                                : waitlistStatus == "denied"
                                    ? (lang == "es" ? "❌ Acceso Denegado" : "❌ Access Denied")
                                    : (lang == "es" ? "✅ Acceso Aprobado" : "✅ Access Approved")

                            Text(msg)
                                .font(.headline)
                                .foregroundColor(.white)
                        }

                        Button(lang == "es" ? "Cerrar" : "Close") {
                            showWaitlistPopup = false
                        }
                        .foregroundColor(.white.opacity(0.6))
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                    .padding(.horizontal, 24)
                }
                .transition(.scale)
                .zIndex(20)
            }
            
            if showWaitlistStatusSheet {
                miniWaitlistSheet()
            }
            
            if isRefreshingEvent {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                ProgressView(lang == "es" ? "Actualizando..." : "Updating...")
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
            }
        }
        
        .animation(.easeInOut, value: showPaymentPopup)
        .animation(.spring(response: 0.7, dampingFraction: 0.82, blendDuration: 0.21), value: showWaitlistStatusSheet)
        .onAppear {
            isZelleAvailable = !(event.zelleEmail?.isEmpty ?? true) || !(event.zellePhone?.isEmpty ?? true)
            
            if event.listOnly ?? false {
                checkWaitlistStatus()
            }
            
            fetchUpdatedEventData()
        }
    }

    @ViewBuilder
    private func paymentOptionButton(_ method: String, icon: String, titleES: String, titleEN: String) -> some View {
        Button {
            selectedPaymentMethod = method
        } label: {
            HStack {
                Image(systemName: icon)
                Text(lang == "es" ? titleES : titleEN)
            }
            .foregroundColor(selectedPaymentMethod == method ? .black : .white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(selectedPaymentMethod == method ? Color.gold : Color.white.opacity(0.1))
            .cornerRadius(14)
        }
    }
    
    @ViewBuilder
    private func miniWaitlistSheet() -> some View {
        let isPending = waitlistSheetType == "pending"
        let isDenied = waitlistSheetType == "denied"
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                // Animated Emoji
                if isPending {
                    Text("⏳")
                        .font(.system(size: 46))
                        .scaleEffect(showWaitlistStatusSheet ? 1.1 : 1)
                        .animation(.spring(), value: showWaitlistStatusSheet)
                }
                if isDenied {
                    Text("❌")
                        .font(.system(size: 46))
                        .scaleEffect(showWaitlistStatusSheet ? 1.1 : 1)
                        .animation(.spring(), value: showWaitlistStatusSheet)
                }
                // Main Title
                Text(isPending ?
                     (lang == "es" ? "Solicitud Enviada" : "Request Sent") :
                     (lang == "es" ? "Acceso Denegado" : "Access Denied")
                )
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(isDenied ? .red : .white)
                    .padding(.bottom, -4)

                // Subtitle
                Text(isPending ?
                    (lang == "es"
                        ? "Ya solicitaste acceso. Espera la aprobación del organizador."
                        : "You've already requested access. Please wait for approval.") :
                    (lang == "es"
                        ? "El organizador ha denegado tu acceso a este evento."
                        : "The organizer denied your access to this event.")
                )
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)

                // Button to dismiss
                Button(action: {
                    dismissWaitlistSheet()
                }) {
                    Text(lang == "es" ? "Cerrar" : "Close")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isDenied ? Color.red : Color.gold)
                        )
                        .foregroundColor(.black)
                }
                .padding(.top, 6)
            }
            .padding(.vertical, 30)
            .padding(.horizontal, 28)
            .background(
                BlurView(style: .systemUltraThinMaterialDark)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 10)
            )
            .frame(maxWidth: 380)
            .padding(.bottom, 24)
            .offset(y: waitlistShouldHide ? 600 : waitlistDragOffset) // <--- Key for animating out
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.height > 0 {
                            waitlistDragOffset = value.translation.height
                        }
                    }
                    .onEnded { value in
                        if value.translation.height > 100 {
                            dismissWaitlistSheet()
                        } else {
                            withAnimation(.spring()) {
                                waitlistDragOffset = 0
                            }
                        }
                    }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.7, dampingFraction: 0.82, blendDuration: 0.25), value: waitlistShouldHide)
        }
        .ignoresSafeArea()
    }

    private func dismissWaitlistSheet() {
        // First animate sheet down
        withAnimation(.spring(response: 0.7, dampingFraction: 0.82, blendDuration: 0.25)) {
            waitlistShouldHide = true
        }
        // After animation, hide the whole sheet
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            waitlistShouldHide = false
            showWaitlistStatusSheet = false
            waitlistDragOffset = 0
        }
    }
    

    @ViewBuilder
    private func paymentDetailsView() -> some View {
        switch selectedPaymentMethod {
        case "zelle":
            VStack(spacing: 4) {
                if let email = event.zelleEmail, !email.isEmpty {
                    HStack {
                        Image(systemName: "envelope")
                        Text(email)
                    }.foregroundColor(.white)
                }
                if let phone = event.zellePhone, !phone.isEmpty {
                    HStack {
                        Image(systemName: "phone")
                        Text(phone)
                    }.foregroundColor(.white)
                }
                Text(lang == "es"
                     ? "Después de pagar por Zelle, toca Pagar abajo para notificar al organizador."
                     : "After sending your Zelle payment, tap Pay below to notify the organizer.")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

        case "pagoMovil":
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

        case "cash":
            if let note = event.cashNote {
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

        default:
            EmptyView()
        }
    }
    
    private func showWaitlistSheet(type: String) {
        waitlistSheetType = type
        withAnimation(.spring(response: 0.7, dampingFraction: 0.80, blendDuration: 0.32)) {
            showWaitlistStatusSheet = true
        }
        // Vibration every time
        if type == "pending" {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        } else if type == "denied" {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        // Cancel previous auto-dismiss, if any
        autoDismissWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            dismissWaitlistSheet()
        }
        autoDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: workItem)
    }

    
    func checkWaitlistStatus() {
        guard event.listOnly ?? false else { return }
        guard let token = TokenManager.shared.getAccessToken() else {
            print("❌ No token found in TokenManager!")
            return
        }
        let url = URL(string: "https://backendevent-etce.onrender.com/events/\(event.id)/waitlist/status")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data else { return }

            // Check for empty/null response (no entry for this user)
            if let raw = String(data: data, encoding: .utf8), raw == "null" || raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                DispatchQueue.main.async {
                    self.showWaitlistPopup = true // Let them request access
                }
                return
            }

            do {
                let entry = try JSONDecoder().decode(WaitlistEntry.self, from: data)
                DispatchQueue.main.async {
                    self.waitlistStatus = entry.status.lowercased()
                    // If approved, allow selecting a ticket; if pending/denied, show appropriate UI
                }
            } catch {
                print("❌ Failed to decode waitlist entry: \(error)")
                print("✅ RAW waitlist status data:", String(data: data, encoding: .utf8) ?? "nil")
                DispatchQueue.main.async {
                    self.showWaitlistPopup = true
                }
            }
        }.resume()
    }


    private func startCheckout() {
        paymentSheet = nil
        isPaymentSheetPresented = false
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
                        self.fetchUpdatedEventData() // 👈 reload event data after free ticket
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
                    self.fetchUpdatedEventData() // 👈 always reload event data after manual payment
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
    
    private func fetchUpdatedEventData() {
        guard let token = TokenManager.shared.getAccessToken() else { return }
        isRefreshingEvent = true
        let url = URL(string: "https://backendevent-etce.onrender.com/events/\(event.id)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                isRefreshingEvent = false
                if let data = data,
                   let updatedEvent = try? JSONDecoder().decode(Event.self, from: data) {
                    self.event = updatedEvent
                }
            }
        }.resume()
    }


    func sendWaitlistRequest() {
        guard let token = TokenManager.shared.getAccessToken() else { return }
        waitlistLoading = true

        var request = URLRequest(url: URL(string: "https://backendevent-etce.onrender.com/events/\(event.id)/waitlist/request")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let fullName = userSession.fullName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "AnonymousUser"
        let body = "fullName=\(fullName)"
        request.httpBody = body.data(using: String.Encoding.utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: request) { data, response, _ in
            DispatchQueue.main.async {
                waitlistLoading = false
                waitlistStatus = "pending"
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
                        fetchUpdatedEventData() // ✅ add this
                    case .canceled:
                        message = "❌ Payment canceled."
                        fetchUpdatedEventData()
                    case .failed(let error):
                        message = "❌ Payment failed: \(error.localizedDescription)"
                        fetchUpdatedEventData()

                    }
                }
            } else {
                message = "❌ Couldn't find view controller"
            }
        }
    }

    private func topViewController(controller: UIViewController? = nil) -> UIViewController? {
        let controller = controller ?? UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?.rootViewController

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
            fetchUpdatedEventData() // ✅ optional but safer
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
                    self.selectedTierId = nil
                    self.quantity = 1
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


struct BlurView: UIViewRepresentable {
    var style: UIBlurEffect.Style
    func makeUIView(context: Context) -> UIVisualEffectView {
        return UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}


private struct NoTicketsView: View {
    let lang: String
    var body: some View {
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
    }
}

