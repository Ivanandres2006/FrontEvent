import SwiftUI

struct PostCreationView: View {
    @AppStorage("selectedLanguage") var lang: String = "en"
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var userSession: UserSession

    @ObservedObject var viewModel: PostCreationViewModel
    var onPostCreated: () -> Void

    // Selection is by ticket ID (fixes "invalid tag" warnings)
    @State private var selectedTicketId: Int? = nil

    // Form state
    @State private var title = ""
    @State private var priceValue: Double? = nil   // NumberFormatter-backed
    @State private var priceDirty = false
    @State private var isLoading = false
    @State private var errorMessage = ""

    @FocusState private var focusedField: Field?
    private enum Field { case title, price }

    // Seller payout (optional at creation)
    @State private var zelleEmail = ""
    @State private var pmPhone = ""
    @State private var pmCi = ""
    @State private var pmBank = ""
    @State private var cashNote = ""
    @State private var showPayout = false

    // Formatter for the price field (auto 2 decimals)
    private let priceFormatter: NumberFormatter = {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.minimumFractionDigits = 2
        nf.maximumFractionDigits = 2
        nf.usesGroupingSeparator = false
        return nf
    }()

    // MARK: - Eligibility (timezone-safe, 6h grace)
    var availableTickets: [TicketDTO] {
        viewModel.tickets
            .filter { t in
                guard t.resold == false else { return false }
                guard t.used == false else { return false }
                let st = t.status.uppercased()
                guard st == "PAID" || st == "VALID" else { return false }
                let futureLocal = isFuture(t.eventDateTime, graceSeconds: 6 * 3600)
                if let flag = t.resellEligible, flag == false, !futureLocal { return false }
                return futureLocal
            }
            .sorted {
                (parseISODate($0.eventDateTime) ?? .distantFuture) <
                (parseISODate($1.eventDateTime) ?? .distantFuture)
            }
    }

    // Form validity
    var canPost: Bool {
        guard !isLoading,
              selectedTicketId != nil,
              let p = priceValue, p > 0,
              title.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
        else { return false }
        return true
    }

    var body: some View {
        ZStack {
            backgroundView
            ScrollView {
                VStack(spacing: 18) {
                    headerView

                    if viewModel.tickets.isEmpty {
                        emptyState(lang == "es"
                                   ? "No tienes entradas para eventos activos en este momento."
                                   : "You don't have any tickets for active events right now.")
                    } else if availableTickets.isEmpty {
                        emptyState(lang == "es"
                                   ? "Todas tus entradas ya no son elegibles para reventa (evento pasado o ya listadas)."
                                   : "None of your tickets are eligible for resale anymore (past event or already listed).")
                    } else {
                        countBadge

                        ticketPickerCard
                        formCard

                        // Optional payout details included at creation
                        DisclosureGroup(isExpanded: $showPayout) {
                            VStack(spacing: 10) {
                                Text("Zelle")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.white.opacity(0.8))
                                TextField("Zelle email", text: $zelleEmail)
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.emailAddress)
                                    .paddedField()
                                Divider().background(Color.white.opacity(0.08))
                                Text("Pago Móvil")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.white.opacity(0.8))
                                TextField("Teléfono", text: $pmPhone)
                                    .keyboardType(.numberPad)
                                    .paddedField()
                                TextField("CI", text: $pmCi)
                                    .keyboardType(.numberPad)
                                    .paddedField()
                                TextField("Banco", text: $pmBank)
                                    .paddedField()
                                Divider().background(Color.white.opacity(0.08))
                                Text("Cash")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.white.opacity(0.8))
                                TextField("Cash note / instructions", text: $cashNote)
                                    .paddedField()
                            }
                            .padding(.top, 8)
                        } label: {
                            HStack {
                                Image(systemName: "creditcard.fill")
                                Text(lang == "es" ? "Pagos para ti (opcional)" : "Payments to you (optional)")
                            }
                            .foregroundColor(.white)
                        }
                        .padding(14)
                        .background(.white.opacity(0.05))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(.white.opacity(0.06), lineWidth: 1)
                        )

                        postButton
                            .padding(.top, 8)

                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(.red)
                                .padding(.top, 6)
                                .transition(.opacity)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .onAppear { ensureDefaultSelection() }
        .onChange(of: availableTickets.map(\.id)) { _, _ in
            ensureDefaultSelection()
        }
        .onChange(of: selectedTicketId) { _, newValue in
            if let id = newValue,
               title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let t = availableTickets.first(where: { $0.id == id }) {
                let e = t.eventTitle ?? (lang == "es" ? "Evento Sin Título" : "Untitled Event")
                let n = t.tierName ?? (lang == "es" ? "Nivel Sin Nombre" : "Unnamed Tier")
                title = "\(e) — \(n)"
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(lang == "es" ? "Listo" : "Done") {
                    focusedField = nil
                    if let p = priceValue { priceValue = p }
                }
            }
        }
    }

    // MARK: - UI

    var backgroundView: some View {
        LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }

    var headerView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(lang == "es" ? "Crear Publicación de Reventa" : "Create Resale Post")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)
            Text(lang == "es" ? "Vende un ticket que no usarás" : "Sell a ticket you won’t use")
                .foregroundColor(.white.opacity(0.6))
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
    }

    var countBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "ticket.fill")
            Text(
                lang == "es"
                ? "Entradas Disponibles: \(availableTickets.count)"
                : "Available Tickets: \(availableTickets.count)"
            ).fontWeight(.semibold)
        }
        .foregroundColor(.black)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.gold)
        .clipShape(Capsule())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var ticketPickerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(lang == "es" ? "Selecciona tu ticket" : "Select your ticket")
                .foregroundColor(.white.opacity(0.9))

            Picker("", selection: $selectedTicketId) {
                Text(lang == "es" ? "Elige un ticket" : "Choose a ticket")
                    .italic()
                    .foregroundColor(.secondary)
                    .tag(nil as Int?)

                ForEach(availableTickets) { t in
                    Text(label(t)).tag(Optional(t.id))
                }
            }
            .pickerStyle(.menu)
            .tint(.gold)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.08))
            .cornerRadius(12)

            if let id = selectedTicketId,
               let t = availableTickets.first(where: { $0.id == id }) {
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.clock")
                    Text(niceDate(t.eventDateTime, lang: lang))
                    Spacer()
                    Image(systemName: "number")
                    Text("\(t.id)")
                }
                .font(.footnote)
                .foregroundColor(.white.opacity(0.75))
                .padding(.horizontal, 6)
            }
        }
        .padding(14)
        .background(.white.opacity(0.05))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        )
    }

    var formCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "text.cursor")
                    .foregroundColor(.white.opacity(0.7))
                TextField(lang == "es" ? "Título del anuncio" : "Listing title", text: $title)
                    .textInputAutocapitalization(.sentences)
                    .focused($focusedField, equals: .title)
                    .foregroundColor(.white)
            }
            .padding(12)
            .background(Color.white.opacity(0.08))
            .cornerRadius(12)

            if title.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 && !title.isEmpty {
                helperRow(lang == "es" ? "Mínimo 3 caracteres" : "At least 3 characters")
            }

            HStack(spacing: 8) {
                Image(systemName: "dollarsign.circle")
                    .foregroundColor(.white.opacity(0.7))
                TextField(lang == "es" ? "Precio (USD)" : "Price (USD)",
                          value: $priceValue,
                          formatter: priceFormatter)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .price)
                    .onChange(of: priceValue) { _, _ in priceDirty = true }
                    .foregroundColor(.white)
                    .overlay(alignment: .trailing) {
                        Text("USD")
                            .font(.caption.bold())
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.trailing, 8)
                    }
            }
            .padding(12)
            .background(Color.white.opacity(0.08))
            .cornerRadius(12)

            if priceDirty, let p = priceValue, p <= 0 {
                helperRow(lang == "es" ? "El precio debe ser mayor a 0" : "Price must be greater than 0")
            } else if priceDirty, priceValue == nil {
                helperRow(lang == "es" ? "Ingresa un precio" : "Enter a price")
            }
        }
        .padding(14)
        .background(.white.opacity(0.05))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        )
    }

    func helperRow(_ s: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").font(.caption2)
            Text(s).font(.caption)
        }
        .foregroundColor(.yellow)
        .padding(.leading, 4)
    }

    var postButton: some View {
        Button(action: createPost) {
            HStack {
                if isLoading { ProgressView().tint(.black) }
                Text(lang == "es" ? "Publicar" : "Post")
                    .fontWeight(.bold)
                    .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(canPost ? Color.gold : Color.gold.opacity(0.35))
            .foregroundColor(.black)
            .cornerRadius(14)
        }
        .disabled(!canPost)
        .animation(.easeInOut(duration: 0.15), value: canPost)
    }

    // MARK: - Helpers

    func label(_ t: TicketDTO) -> String {
        let e = t.eventTitle ?? (lang == "es" ? "Evento Sin Título" : "Untitled Event")
        let n = t.tierName ?? (lang == "es" ? "Nivel Sin Nombre" : "Unnamed Tier")
        let when = niceDate(t.eventDateTime, lang: lang)
        return "\(e) — \(n) • \(when)"
    }

    private func emptyState(_ s: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "ticket")
                .resizable().scaledToFit()
                .frame(width: 60, height: 60)
                .foregroundColor(.white.opacity(0.5))
            Text(s)
                .foregroundColor(.white.opacity(0.8))
                .font(.title3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private func ensureDefaultSelection() {
        let ids = availableTickets.map(\.id)
        guard !ids.isEmpty else {
            selectedTicketId = nil
            return
        }

        if let current = selectedTicketId {
            if !ids.contains(current) {
                selectedTicketId = ids.first
            }
        } else {
            selectedTicketId = ids.first
        }

        if let id = selectedTicketId,
           title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let t = availableTickets.first(where: { $0.id == id }) {
            let e = t.eventTitle ?? (lang == "es" ? "Evento Sin Título" : "Untitled Event")
            let n = t.tierName ?? (lang == "es" ? "Nivel Sin Nombre" : "Unnamed Tier")
            title = "\(e) — \(n)"
        }
    }

    // MARK: - Date helpers
    private func parseISODate(_ s: String?) -> Date? {
        guard let s = s, !s.isEmpty else { return nil }
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFrac.date(from: s) { return d }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.date(from: s)
    }

    private func niceDate(_ s: String?, lang: String) -> String {
        guard let d = parseISODate(s) else { return lang == "es" ? "Sin fecha" : "No date" }
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }

    private func isFuture(_ s: String?, graceSeconds: TimeInterval = 3600) -> Bool {
        guard let d = parseISODate(s) else { return false }
        return d >= Date().addingTimeInterval(-graceSeconds)
    }

    // MARK: - Network
    func createPost() {
        guard let token = TokenManager.shared.getAccessToken(),
              let ticketId = selectedTicketId,
              let url = URL(string: "https://backendevent-etce.onrender.com/resale/create"),
              let priceValue = priceValue, priceValue > 0
        else {
            withAnimation { errorMessage = lang == "es" ? "Completa el formulario" : "Please complete the form" }
            return
        }

        isLoading = true
        errorMessage = ""

        var payload: [String: Any] = [
            "ticketId": ticketId,
            "price": priceValue,
            "title": title
        ]
        // include optional payout fields when provided
        if !zelleEmail.trimmingCharacters(in: .whitespaces).isEmpty {
            payload["sellerZelleEmail"] = zelleEmail.trimmingCharacters(in: .whitespaces)
        }
        if !pmPhone.trimmingCharacters(in: .whitespaces).isEmpty {
            payload["sellerPagoMovilPhone"] = pmPhone.trimmingCharacters(in: .whitespaces)
        }
        if !pmCi.trimmingCharacters(in: .whitespaces).isEmpty {
            payload["sellerPagoMovilCi"] = pmCi.trimmingCharacters(in: .whitespaces)
        }
        if !pmBank.trimmingCharacters(in: .whitespaces).isEmpty {
            payload["sellerPagoMovilBank"] = pmBank.trimmingCharacters(in: .whitespaces)
        }
        if !cashNote.trimmingCharacters(in: .whitespaces).isEmpty {
            payload["sellerCashNote"] = cashNote.trimmingCharacters(in: .whitespaces)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: request) { data, response, _ in
            DispatchQueue.main.async { isLoading = false }

            guard let http = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    errorMessage = lang == "es" ? "Sin respuesta del servidor" : "No response from server"
                }
                return
            }

            if http.statusCode == 200 {
                DispatchQueue.main.async {
                    onPostCreated()
                    dismiss()
                }
            } else {
                let serverText = data.flatMap { String(data: $0, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines)
                DispatchQueue.main.async {
                    errorMessage = (serverText?.isEmpty == false)
                        ? serverText!
                        : (lang == "es" ? "No se pudo crear la publicación" : "Failed to create post")
                }
            }
        }.resume()
    }
}

// MARK: - Shared helpers used above

private extension View {
    func paddedField() -> some View {
        self.padding(12)
            .background(Color.white.opacity(0.08))
            .cornerRadius(12)
            .foregroundColor(.white)
    }
}

// Sheet to edit payout methods on an existing post
private struct PaymentMethodsSheet: View {
    let postId: Int
    @Environment(\.dismiss) var dismiss

    @State private var zelle = ""
    @State private var pmPhone = ""
    @State private var pmCi = ""
    @State private var pmBank = ""
    @State private var cash = ""
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Zelle") { TextField("Email", text: $zelle).keyboardType(.emailAddress) }
                Section("Pago Móvil") {
                    TextField("Teléfono", text: $pmPhone).keyboardType(.numberPad)
                    TextField("CI", text: $pmCi).keyboardType(.numberPad)
                    TextField("Banco", text: $pmBank)
                }
                Section("Cash") { TextField("Note", text: $cash) }
            }
            .navigationTitle("Payment methods")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { save() }.disabled(isSaving)
                }
            }
            .alert("Error", isPresented: .constant(error != nil), actions: {
                Button("OK"){ error = nil }
            }, message: { Text(error ?? "") })
            .onAppear { prefillFromOptions() }
        }
    }

    // Prefill with current seller payout from options endpoint
    private func prefillFromOptions() {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/api/resale/options/\(postId)")
        else { return }

        var r = URLRequest(url: url)
        r.httpMethod = "GET"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: r) { data, _, _ in
            if let data = data,
               let opts = try? JSONDecoder().decode(PaymentOptions.self, from: data) {
                DispatchQueue.main.async {
                    self.zelle  = opts.zelleEmail ?? ""
                    self.pmPhone = opts.pagoMovilPhone ?? ""
                    self.pmCi    = opts.pagoMovilCi ?? ""
                    self.pmBank  = opts.pagoMovilBank ?? ""
                    self.cash    = opts.cashNote ?? ""
                }
            }
        }.resume()
    }

    private func save() {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/api/resale/\(postId)/payout")
        else { return }
        isSaving = true
        var r = URLRequest(url: url)
        r.httpMethod = "PATCH"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "sellerZelleEmail": zelle,
            "sellerPagoMovilPhone": pmPhone,
            "sellerPagoMovilCi": pmCi,
            "sellerPagoMovilBank": pmBank,
            "sellerCashNote": cash
        ]
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: r) { _, resp, _ in
            DispatchQueue.main.async {
                isSaving = false
                if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                    dismiss()
                } else {
                    error = "Could not save payment methods."
                }
            }
        }.resume()
    }
}

// Seller menu that requires a postId to open the payout sheet
private struct SellerMenu: View {
    let postId: Int
    let isPaused: Bool
    let onEditPrice: () -> Void
    let onTogglePause: () -> Void
    let onShare: () -> Void
    @State private var showPayout = false
    @AppStorage("selectedLanguage") var lang: String = "en"

    var body: some View {
        Menu {
            Button(lang == "es" ? "Editar precio" : "Edit price", action: onEditPrice)
            Button(
                isPaused ? (lang == "es" ? "Reanudar" : "Resume")
                         : (lang == "es" ? "Pausar" : "Pause"),
                action: onTogglePause
            )
            Button(lang == "es" ? "Compartir enlace" : "Share link", action: onShare)
            Button(lang == "es" ? "Métodos de pago" : "Payment methods") { showPayout = true }
        } label: {
            Image(systemName: "ellipsis").foregroundColor(.white).padding(8)
        }
        .sheet(isPresented: $showPayout) {
            PaymentMethodsSheet(postId: postId)
        }
    }
}
