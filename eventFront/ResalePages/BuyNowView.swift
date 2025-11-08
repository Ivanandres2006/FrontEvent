import SwiftUI
import Stripe
import StripePaymentSheet
import UIKit



struct PaymentOptions: Codable {
    let country: String?
    let currency: String?
    let allowed: [String]
    let zelleEmail: String?
    let pagoMovilPhone: String?
    let pagoMovilCi: String?
    let pagoMovilBank: String?
    let cashNote: String?
}

// New (checkout-style) response
struct ClientSecretResponse: Codable {
    let clientSecret: String
}

// Legacy shape (kept for back-compat if your server ever returns it)
struct PaymentIntentResponse: Codable {
    let clientSecret: String
    let ephemeralKey: String
    let customerId: String
}

struct BuyNowView: View {
    @AppStorage("selectedLanguage") var lang: String = "en"

        let resalePost: ResalePostDTO
        @Binding var event: Event
        let userEmail: String
        let accepted: AcceptedOffer?          // ← no default here
        var onComplete: () -> Void

        @Environment(\.dismiss) var dismiss

        @State private var isLoading = false
        @State private var paymentSheet: PaymentSheet?
        @State private var isPaymentSheetPresented = false

        @State private var showError = false
        @State private var errorMessage = ""
        @State private var showSuccess = false

        @State private var isEventLoaded = true
        @State private var options: PaymentOptions?
        @State private var selectedMethod: String = "card"
        @State private var manualOrderId: Int?

        private var priceToCharge: Double { accepted?.amount ?? resalePost.price }
        private var currencyToShow: String { accepted?.currency ?? "USD" }

        init(
            resalePost: ResalePostDTO,
            event: Binding<Event>,
            userEmail: String,
            accepted: AcceptedOffer? = nil,    // ← callers can pass one, or omit
            onComplete: @escaping () -> Void
        ) {
            self.resalePost = resalePost
            self._event = event
            self.userEmail = userEmail
            self.accepted = accepted           // ← initialized exactly once
            self.onComplete = onComplete
        }

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            if isEventLoaded {
                VStack(spacing: 24) {
                    header
                    amount
                    methodSelector
                    methodBody
                    Spacer()
                }
                .padding()
                .onAppear { fetchOptions() }
            } else {
                ProgressView(lang == "es" ? "Cargando Evento..." : "Loading Event...")
                    .foregroundColor(.white)
            }

            if showError { toastError }
            if showSuccess { toastSuccess }
        }
        .onChange(of: isPaymentSheetPresented) { _ in
            // no-op
        }
    }

    // MARK: - UI
    var header: some View {
        VStack(spacing: 6) {
            Text(lang == "es" ? "Comprar Entrada" : "Buy Ticket")
                .font(.largeTitle.bold())
                .foregroundColor(.white)
            Text(resalePost.title)
                .foregroundColor(.white.opacity(0.8))
            Text((lang == "es" ? "De " : "From ") + resalePost.sellerName)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))
        }
    }

    var amount: some View {
        Text("\(currencyToShow) \(String(format: "%.2f", priceToCharge))")
            .font(.system(size: 48, weight: .black))
            .foregroundColor(.gold)
    }


    var methodSelector: some View {
        let allowed = options?.allowed ?? ["card"]
        return HStack(spacing: 10) {
            ForEach(allowed, id: \.self) { m in
                Button {
                    selectedMethod = m
                } label: {
                    Text(label(for: m))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(selectedMethod == m ? Color.gold : Color.white.opacity(0.08))
                        .foregroundColor(selectedMethod == m ? .black : .white)
                        .cornerRadius(20)
                }
            }
        }
    }

    var methodBody: some View {
        Group {
            if selectedMethod == "card" {
                VStack(spacing: 12) {
                    Text(lang == "es" ? "Paga con tarjeta internacional (Stripe)" : "Pay with international card (Stripe)")
                        .foregroundColor(.white.opacity(0.9))
                    Button {
                        startStripeFlow()
                    } label: {
                        HStack {
                            if isLoading { ProgressView().tint(.black) }
                            Text(lang == "es" ? "Pagar Ahora" : "Pay Now")
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gold)
                        .foregroundColor(.black)
                        .cornerRadius(14)
                    }
                }
            } else {
                manualBlock
            }
        }
        .sheet(isPresented: $isPaymentSheetPresented) {
            if let sheet = paymentSheet {
                PaymentSheet.PaymentButton(
                    paymentSheet: sheet,
                    onCompletion: handlePaymentResult
                ) {
                    Text("Pay now")
                        .font(.headline)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                }
                .padding()
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Preparing payment…")
                }
                .padding()
            }
        }
    }

    var manualBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            if selectedMethod == "pagoMovil" {
                infoLine("Pago Móvil", value: nil)
                copyLine(title: "Teléfono", value: options?.pagoMovilPhone)
                copyLine(title: "CI",       value: options?.pagoMovilCi)
                copyLine(title: "Banco",    value: options?.pagoMovilBank)
            } else if selectedMethod == "zelle" {
                infoLine("Zelle", value: nil)
                copyLine(title: "Email", value: options?.zelleEmail)
            } else if selectedMethod == "cash" {
                infoLine("Efectivo / Cash", value: nil)
                copyLine(title: lang == "es" ? "Nota" : "Note", value: options?.cashNote)
            }

            Button {
                requestManualConfirmation()
            } label: {
                HStack {
                    if isLoading { ProgressView().tint(.black) }
                    Text(lang == "es" ? "Ya pagué • Solicitar confirmación" : "I paid • Request confirmation")
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.gold)
                .foregroundColor(.black)
                .cornerRadius(14)
            }

            if manualOrderId != nil {
                Text(lang == "es"
                     ? "Esperando confirmación del vendedor…"
                     : "Waiting for seller confirmation…")
                .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    func infoLine(_ title: String, value: String?) -> some View {
        HStack {
            Text(title).bold().foregroundColor(.white)
            Spacer()
            if let value = value {
                Text(value).foregroundColor(.white.opacity(0.9))
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.06))
        .cornerRadius(12)
    }

    func copyLine(title: String, value: String?) -> some View {
        HStack {
            Text(title).bold().foregroundColor(.white)
            Spacer()
            Text(value ?? "—").foregroundColor(.white.opacity(0.9))
            Button {
                UIPasteboard.general.string = value ?? ""
            } label: {
                Image(systemName: "doc.on.doc")
                    .foregroundColor(.gold)
                    .padding(.leading, 8)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.06))
        .cornerRadius(12)
    }

    var toastError: some View {
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

    var toastSuccess: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .resizable().scaledToFit().frame(width: 80, height: 80)
                .foregroundColor(.green)
            Text(lang == "es" ? "Compra exitosa" : "Purchase successful")
                .foregroundColor(.white).font(.title3.bold())
            Button {
                dismiss()
                onComplete()
            } label: {
                Text(lang == "es" ? "Cerrar" : "Close")
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(10)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Network
    func fetchOptions() {
        guard let token = TokenManager.shared.normalizedAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/api/resale/options/\(resalePost.id)")
        else { return }

        var r = URLRequest(url: url)
        r.httpMethod = "GET"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: r) { data, _, _ in
            if let data = data, let opts = try? JSONDecoder().decode(PaymentOptions.self, from: data) {
                DispatchQueue.main.async {
                    self.options = opts
                    self.selectedMethod = opts.allowed.first ?? "card"
                }
            }
        }.resume()
    }

    func startStripeFlow() {
        let urlString: String = {
            if let accepted { return "https://backendevent-etce.onrender.com/api/resale/pay/offer/\(accepted.messageId)" }
            return "https://backendevent-etce.onrender.com/api/resale/pay/\(resalePost.id)"
        }()

        isLoading = true
        authedPOST(urlString: urlString, json: [:], retryOnceOn401: true) { data, http, error in
            DispatchQueue.main.async { self.isLoading = false }

            if let error = error { show(error.localizedDescription); return }
            guard let data = data else { show("Empty server response"); return }

            if let secret = extractClientSecret(from: data, response: http) {
                var config = PaymentSheet.Configuration()
                config.merchantDisplayName = "WKND Events"
                config.primaryButtonColor = UIColor(Color.gold)
                DispatchQueue.main.async {
                    self.paymentSheet = PaymentSheet(paymentIntentClientSecret: secret, configuration: config)
                    self.presentPaymentSheet()
                }
                return
            }

            // bubble up server message (will show "HTTP 401: <body>" if unauthorized)
            let serverMsg = extractServerError(from: data, response: http)
            show(serverMsg ?? (String(data: data, encoding: .utf8).map { "Unexpected response: \($0)" } ?? "Unexpected response"))
        }
    }

    func presentPaymentSheet() {
        isPaymentSheetPresented = true
    }

    func handlePaymentResult(_ result: PaymentSheetResult) {
        switch result {
        case .completed:
            confirmTransfer()
        case .canceled:
            break
        case .failed(let error):
            show(error.localizedDescription)
        }
    }
    
    private func extractClientSecret(from data: Data, response: URLResponse?) -> String? {
        // 1) Try your v1 shape
        if let simple = try? JSONDecoder().decode(ClientSecretResponse.self, from: data) {
            return simple.clientSecret
        }
        // 2) Try your legacy shape
        if let legacy = try? JSONDecoder().decode(PaymentIntentResponse.self, from: data) {
            return legacy.clientSecret
        }
        // 3) Try generic JSON dictionaries
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // common variants
            if let s = obj["client_secret"] as? String { return s }
            if let s = obj["payment_intent_client_secret"] as? String { return s }
            if let s = obj["paymentIntentClientSecret"] as? String { return s }
            if let pi = obj["paymentIntent"] as? [String: Any],
               let s = pi["client_secret"] as? String { return s }
            if let dataDict = obj["data"] as? [String: Any],              // sometimes wrapped
               let s = dataDict["client_secret"] as? String { return s }
        }
        // 4) Try plaintext body
        if let raw = String(data: data, encoding: .utf8) {
            // Stripe client secret contains "_secret_"
            if raw.contains("_secret_") { return raw.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        // 5) If server returned 204/empty or non-JSON error
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            // let caller show the server error; return nil here
            return nil
        }
        return nil
    }

    private func extractServerError(from data: Data, response: URLResponse?) -> String? {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // typical error fields
            if let e = obj["error"] as? String { return e }
            if let m = obj["message"] as? String { return m }
            if let err = obj["errors"] as? [String], let first = err.first { return first }
        }
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let raw = String(data: data, encoding: .utf8) ?? "<no body>"
            return "HTTP \(http.statusCode): \(raw)"
        }
        return nil
    }

    func confirmTransfer() {
        guard let token = TokenManager.shared.normalizedAccessToken() else { return }

        let urlString: String
        if let accepted {
            // confirm the transfer for this accepted offer
            urlString = "https://backendevent-etce.onrender.com/api/resale/confirm-transfer/offer/\(accepted.messageId)"
        } else {
            urlString = "https://backendevent-etce.onrender.com/api/resale/confirm-transfer/\(resalePost.id)"
        }
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { _, _, _ in
            DispatchQueue.main.async { self.showSuccess = true }
        }.resume()
    }
    
    // MARK: - Auth POST helper with 401 surface + optional retry

    /// Adjust this to your TokenManager. If you have a real refresh flow, call it here.
    private func getValidAccessToken() async throws -> String {
        if let t = TokenManager.shared.getAccessToken() { return t }
        struct NoToken: Error {}
        throw NoToken()
    }

    private func authedPOST(urlString: String,
                            json: [String: Any]? = [:],
                            retryOnceOn401: Bool = true,
                            completion: @escaping (_ data: Data?, _ response: HTTPURLResponse?, _ error: Error?) -> Void) {

        func makeRequest(with token: String, allowRetry: Bool) {
            guard let url = URL(string: urlString) else {
                completion(nil, nil, URLError(.badURL)); return
            }
            var r = URLRequest(url: url)
            r.httpMethod = "POST"
            r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.setValue("application/json", forHTTPHeaderField: "Accept")
            r.timeoutInterval = 15    // ⏱️ ensure we don’t hang forever
            r.httpBody = (json != nil) ? (try? JSONSerialization.data(withJSONObject: json!)) : Data("{}".utf8)

            URLSession.shared.dataTask(with: r) { data, resp, err in
                let http = resp as? HTTPURLResponse
                // Retry once on 401
                if retryOnceOn401, allowRetry, http?.statusCode == 401 {
                    print("🟡 \(urlString) returned 401, attempting refresh…")
                    // Add a safety timeout around refresh, so we *always* complete
                    var finished = false
                    let finish: (Bool) -> Void = { ok in
                        guard !finished else { return }
                        finished = true
                        if ok, let newToken = TokenManager.shared.normalizedAccessToken() {
                            makeRequest(with: newToken, allowRetry: false)
                        } else {
                            completion(data, http, err)
                        }
                    }
                    TokenManager.shared.refreshIfNeeded(completion: finish)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 16) { finish(false) } // ⏱️ fallback
                    return
                }
                completion(data, http, err)
            }.resume()
        }

        if let token = TokenManager.shared.normalizedAccessToken() {
            makeRequest(with: token, allowRetry: true)
        } else {
            completion(nil, nil, URLError(.userAuthenticationRequired))
        }
    }


    func requestManualConfirmation() {
        guard let token = TokenManager.shared.normalizedAccessToken() else { return }
        let urlString: String
        if let accepted {
            // create a manual order for the accepted offer amount
            urlString = "https://backendevent-etce.onrender.com/api/resale/manual/offer/\(accepted.messageId)"
        } else {
            urlString = "https://backendevent-etce.onrender.com/api/resale/manual/\(resalePost.id)"
        }
        guard let url = URL(string: urlString) else { return }

        isLoading = true
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["method": selectedMethod, "reference": ""]
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: r) { data, _, _ in
            DispatchQueue.main.async { isLoading = false }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                show("No response"); return
            }
            if let error = json["error"] as? String {
                show(error); return
            }
            if let id = json["orderId"] as? Int {
                DispatchQueue.main.async { self.manualOrderId = id }
            }
        }.resume()
    }

    func show(_ msg: String) {
        DispatchQueue.main.async {
            self.errorMessage = msg
            self.showError = true
        }
    }

    // MARK: - Helpers
    func label(for method: String) -> String {
        switch method {
        case "card":      return lang == "es" ? "Tarjeta" : "Card"
        case "pagoMovil": return "Pago Móvil"
        case "zelle":     return "Zelle"
        case "cash":      return lang == "es" ? "Efectivo" : "Cash"
        default:          return method
        }
    }
}

struct AcceptedOffer {
    let messageId: Int
    let amount: Double
    let currency: String
}

struct BuyFromOfferContext: Identifiable, Hashable {
    let id = UUID()
    let resalePostId: Int?      // <- make optional
    let offerMessageId: Int
    let amount: Double
    let currency: String
}


struct QuickOfferPayView: View {
    @AppStorage("selectedLanguage") var lang: String = "en"

    let accepted: AcceptedOffer
    let resalePostId: Int?            // ← NEW: so we can fetch payment options
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var isLoading = false
    @State private var paymentSheet: PaymentSheet?
    @State private var isPresented = false
    @State private var errorText: String?

    // Mirror BuyNowView
    @State private var options: PaymentOptions?
    @State private var selectedMethod: String = "card"
    @State private var manualOrderId: Int?

    private var amountText: String {
        "\(accepted.currency) \(String(format: "%.2f", accepted.amount))"
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Header (same vibe as BuyNowView)
                VStack(spacing: 6) {
                    Text(lang == "es" ? "Comprar Entrada" : "Buy Ticket")
                        .font(.largeTitle.bold())
                        .foregroundColor(.white)
                    Text(lang == "es" ? "Oferta aceptada" : "Accepted offer")
                        .foregroundColor(.white.opacity(0.8))
                        .font(.subheadline)
                }

                // Amount
                Text(amountText)
                    .font(.system(size: 48, weight: .black))
                    .foregroundColor(.gold)

                // Method selector (same as BuyNowView, falls back to card-only when no post/options)
                methodSelector

                // Body per method (Stripe vs manual)
                methodBody

                if let t = errorText {
                    Text(t).foregroundColor(.red).padding(.top, 8)
                }

                Spacer()
            }
            .padding()
        }
        .onAppear { fetchOptionsIfPossible() }
        .sheet(isPresented: $isPresented) {
            if let sheet = paymentSheet {
                PaymentSheet.PaymentButton(
                    paymentSheet: sheet,
                    onCompletion: { result in
                        switch result {
                        case .completed:
                            confirmTransfer()
                        case .failed(let e):
                            errorText = e.localizedDescription
                        case .canceled:
                            break
                        }
                    }
                ) {
                    Text(lang == "es" ? "Pagar ahora" : "Pay now")
                        .font(.headline)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                }
                .padding()
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                    Text(lang == "es" ? "Preparando pago…" : "Preparing payment…")
                }
                .padding()
            }
        }
    }

    // MARK: - UI bits copied from BuyNowView (trimmed, same behavior)

    private var methodSelector: some View {
        let allowed = options?.allowed ?? ["card"] // default card-only if no post/options
        return HStack(spacing: 10) {
            ForEach(allowed, id: \.self) { m in
                Button {
                    selectedMethod = m
                } label: {
                    Text(label(for: m))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(selectedMethod == m ? Color.gold : Color.white.opacity(0.08))
                        .foregroundColor(selectedMethod == m ? .black : .white)
                        .cornerRadius(20)
                }
            }
        }
    }

    @ViewBuilder
    private var methodBody: some View {
        if selectedMethod == "card" {
            VStack(spacing: 12) {
                Text(lang == "es" ? "Paga con tarjeta internacional (Stripe)" : "Pay with international card (Stripe)")
                    .foregroundColor(.white.opacity(0.9))
                Button {
                    startStripe()
                } label: {
                    HStack {
                        if isLoading { ProgressView().tint(.black) }
                        Text(lang == "es" ? "Pagar Ahora" : "Pay Now")
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gold)
                    .foregroundColor(.black)
                    .cornerRadius(14)
                }
            }
        } else {
            manualBlock
        }
    }

    private var manualBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            if selectedMethod == "pagoMovil" {
                infoLine("Pago Móvil", value: nil)
                copyLine(title: "Teléfono", value: options?.pagoMovilPhone)
                copyLine(title: "CI",       value: options?.pagoMovilCi)
                copyLine(title: "Banco",    value: options?.pagoMovilBank)
            } else if selectedMethod == "zelle" {
                infoLine("Zelle", value: nil)
                copyLine(title: "Email", value: options?.zelleEmail)
            } else if selectedMethod == "cash" {
                infoLine("Efectivo / Cash", value: nil)
                copyLine(title: lang == "es" ? "Nota" : "Note", value: options?.cashNote)
            }

            Button {
                createManualOrder()
            } label: {
                HStack {
                    if isLoading { ProgressView().tint(.black) }
                    Text(lang == "es" ? "Ya pagué • Solicitar confirmación" : "I paid • Request confirmation")
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.gold)
                .foregroundColor(.black)
                .cornerRadius(14)
            }

            if manualOrderId != nil {
                Text(lang == "es"
                     ? "Esperando confirmación del vendedor…"
                     : "Waiting for seller confirmation…")
                .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    // MARK: - Shared little UI helpers (copied)
    private func infoLine(_ title: String, value: String?) -> some View {
        HStack {
            Text(title).bold().foregroundColor(.white)
            Spacer()
            if let value = value {
                Text(value).foregroundColor(.white.opacity(0.9))
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.06))
        .cornerRadius(12)
    }
    private func copyLine(title: String, value: String?) -> some View {
        HStack {
            Text(title).bold().foregroundColor(.white)
            Spacer()
            Text(value ?? "—").foregroundColor(.white.opacity(0.9))
            Button {
                UIPasteboard.general.string = value ?? ""
            } label: {
                Image(systemName: "doc.on.doc")
                    .foregroundColor(.gold)
                    .padding(.leading, 8)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.06))
        .cornerRadius(12)
    }

    // MARK: - Options (copy of BuyNowView.fetchOptions but for offer context)
    private func fetchOptionsIfPossible() {
        // If we know the resalePostId, reuse the SAME options endpoint as BuyNowView.
        guard let postId = resalePostId else { return }
        guard let token = TokenManager.shared.normalizedAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/api/resale/options/\(postId)")
        else { return }

        var r = URLRequest(url: url)
        r.httpMethod = "GET"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: r) { data, _, _ in
            if let data = data, let opts = try? JSONDecoder().decode(PaymentOptions.self, from: data) {
                DispatchQueue.main.async {
                    self.options = opts
                    self.selectedMethod = opts.allowed.first ?? "card"
                }
            }
        }.resume()
    }

    // MARK: - Stripe (offer endpoint)
    private func startStripe() {
        isLoading = true
        let urlString = "https://backendevent-etce.onrender.com/api/resale/pay/offer/\(accepted.messageId)"

        authedPOST(urlString: urlString, json: [:], retryOnceOn401: true) { data, http, err in
            DispatchQueue.main.async { isLoading = false }

            if let err = err { errorText = err.localizedDescription; return }
            guard let data = data else { errorText = "Empty server response"; return }

            if let secret = extractClientSecret(from: data, response: http) {
                var cfg = PaymentSheet.Configuration()
                cfg.merchantDisplayName = "WKND Events"
                cfg.primaryButtonColor = UIColor(Color.gold)
                DispatchQueue.main.async {
                    paymentSheet = PaymentSheet(paymentIntentClientSecret: secret, configuration: cfg)
                    isPresented = true
                }
                return
            }

            errorText = extractServerError(from: data, response: http)
            ?? (String(data: data, encoding: .utf8).map { "Unexpected response: \($0)" } ?? "Unexpected response")
        }
    }

    // MARK: - Manual rails for offer
    private func createManualOrder() {
        guard let token = TokenManager.shared.normalizedAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/api/resale/manual/offer/\(accepted.messageId)")
        else { return }

        isLoading = true
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["method": selectedMethod, "reference": ""]
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: r) { data, _, _ in
            DispatchQueue.main.async { isLoading = false }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                errorText = "No response"; return
            }
            if let error = json["error"] as? String { errorText = error; return }
            if let id = json["orderId"] as? Int {
                DispatchQueue.main.async { self.manualOrderId = id }
            }
        }.resume()
    }

    // MARK: - Confirm transfer (offer endpoint)
    private func confirmTransfer() {
        guard let token = TokenManager.shared.normalizedAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/api/resale/confirm-transfer/offer/\(accepted.messageId)")
        else { return }

        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: r) { _, _, _ in
            DispatchQueue.main.async {
                dismiss()
                onDone()
            }
        }.resume()
    }

    // MARK: - Parsers + helpers (same as your existing)
    private func extractClientSecret(from data: Data, response: URLResponse?) -> String? {
        if let simple = try? JSONDecoder().decode(ClientSecretResponse.self, from: data) {
            return simple.clientSecret
        }
        if let legacy = try? JSONDecoder().decode(PaymentIntentResponse.self, from: data) {
            return legacy.clientSecret
        }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let s = obj["client_secret"] as? String { return s }
            if let s = obj["payment_intent_client_secret"] as? String { return s }
            if let s = obj["paymentIntentClientSecret"] as? String { return s }
            if let pi = obj["paymentIntent"] as? [String: Any],
               let s = pi["client_secret"] as? String { return s }
            if let dataDict = obj["data"] as? [String: Any],
               let s = dataDict["client_secret"] as? String { return s }
        }
        if let raw = String(data: data, encoding: .utf8),
           raw.contains("_secret_") {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 { return nil }
        return nil
    }

    private func extractServerError(from data: Data, response: URLResponse?) -> String? {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let e = obj["error"] as? String { return e }
            if let m = obj["message"] as? String { return m }
            if let arr = obj["errors"] as? [String], let first = arr.first { return first }
        }
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let raw = String(data: data, encoding: .utf8) ?? "<no body>"
            return "HTTP \(http.statusCode): \(raw)"
        }
        return nil
    }

    private func authedPOST(
        urlString: String,
        json: [String: Any]? = [:],
        retryOnceOn401: Bool = true,
        completion: @escaping (_ data: Data?, _ response: HTTPURLResponse?, _ error: Error?) -> Void
    ) {
        func makeRequest(with token: String, allowRetry: Bool) {
            guard let url = URL(string: urlString) else {
                completion(nil, nil, URLError(.badURL)); return
            }
            var r = URLRequest(url: url)
            r.httpMethod = "POST"
            r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.setValue("application/json", forHTTPHeaderField: "Accept")
            r.timeoutInterval = 15
            r.httpBody = (json != nil) ? (try? JSONSerialization.data(withJSONObject: json!)) : Data("{}".utf8)

            URLSession.shared.dataTask(with: r) { data, resp, err in
                let http = resp as? HTTPURLResponse
                if retryOnceOn401, allowRetry, http?.statusCode == 401 {
                    print("🟡 \(urlString) returned 401, attempting refresh…")
                    var finished = false
                    let finish: (Bool) -> Void = { ok in
                        guard !finished else { return }
                        finished = true
                        if ok, let newToken = TokenManager.shared.normalizedAccessToken() {
                            makeRequest(with: newToken, allowRetry: false)
                        } else {
                            completion(data, http, err)
                        }
                    }
                    TokenManager.shared.refreshIfNeeded(completion: finish)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 16) { finish(false) }
                    return
                }
                completion(data, http, err)
            }.resume()
        }

        if let token = TokenManager.shared.normalizedAccessToken() {
            makeRequest(with: token, allowRetry: true)
        } else {
            completion(nil, nil, URLError(.userAuthenticationRequired))
        }
    }

    private func label(for method: String) -> String {
        switch method {
        case "card":      return lang == "es" ? "Tarjeta" : "Card"
        case "pagoMovil": return "Pago Móvil"
        case "zelle":     return "Zelle"
        case "cash":      return lang == "es" ? "Efectivo" : "Cash"
        default:          return method
        }
    }
}


