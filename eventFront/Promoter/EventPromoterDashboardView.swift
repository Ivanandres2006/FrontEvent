import SwiftUI
import UIKit

// MARK: - EventPromoterDashboardView (with defensive networking)
struct EventPromoterDashboardView: View {
    @AppStorage("selectedLanguage") var lang: String = "en"
    @EnvironmentObject var userSession: UserSession
    let event: Event
    @Environment(\.dismiss) var dismiss

    enum Tab: Int, CaseIterable { case promoters, payments, waitlist }
    @State private var tab: Tab = .promoters

    // Data
    @State private var promoters: [PromoterEvent] = []
    @State private var buyersByPromoter: [Int: [ReferredBuyerDTO]] = [:]
    @State private var expandedPromoterId: Int? = nil

    @State private var dashboardTickets: [TicketDTO] = []
    @State private var waitlistEntries: [WaitlistEntry] = []

    // UI
    @State private var isLoading = true
    @State private var isRefreshing = false
    @State private var isUpdatingStatus = false

    @State private var isBootLoading = false

    
    // Assign promoter
    @State private var userIdInput = ""
    @State private var assigning = false
    @State private var suggestions: [UserSearchResult] = []
    @State private var showSuggestions = false
    @State private var isSearchingUsers = false
    @State private var searchWorkItem: DispatchWorkItem?

    @State private var toast: (String, Color, String)? = nil  // (message, tint, SF Symbol)
    @State private var selectedWaitlist: Set<Int> = []
    @State private var isBulkWorking = false
    @State private var showAssignBanner = false
    @State private var assignBannerMsg = ""
    @State private var assignBannerTint: Color = .green
    
    @State private var creatingGroup = false
    @State private var createdRoomId: Int? = nil
    @State private var groupError: String? = nil
    
    @AppStorage("currencyCode") private var currencyCode: String = "USD"   // "USD" or "VES"
    @AppStorage("vesPerUSD")     private var vesPerUSD: Double  = 179.43    // BCV rate you already store
    @State private var showVESRateSheet = false

    enum PaymentFilter: String, CaseIterable, Identifiable { case all, paid, pending, card, zelle, pagomovil, cash
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "All"
            case .paid: return "Paid"
            case .pending: return "Pending"
            case .card: return "Card"
            case .zelle: return "Zelle"
            case .pagomovil: return "Pago Móvil"
            case .cash: return "Cash"
            }
        }
    }
    @State private var filterPayment: PaymentFilter = .all
    @State private var paymentQuery: String = ""

    var totalPromoters: Int { promoters.count }
    var totalBuyers: Int { dashboardTickets.count }
    var paidCount: Int { dashboardTickets.filter { $0.paid }.count }
    var pendingCount: Int { dashboardTickets.filter { !$0.paid }.count }
    var waitlistPending: Int { waitlistEntries.filter { $0.status == "PENDING" }.count }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        header
                        overview
                        tabSwitcher
                        tabContent
                        Spacer(minLength: 24)
                    }
                    .padding(.vertical, 16)
                }
                .refreshable { await refreshAll() }

                if let (msg, color, icon) = toast { ToastView(message: msg, tint: color, systemImage: icon) }
            }
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                ChatAPI.shared.setTokenProvider { TokenManager.shared.getAccessToken() }
                loadAll()
                let appearance = UINavigationBarAppearance()
                appearance.configureWithTransparentBackground()
                appearance.backgroundColor = .clear
                appearance.shadowColor = .clear
                UINavigationBar.appearance().standardAppearance = appearance
                UINavigationBar.appearance().scrollEdgeAppearance = appearance
            }
        }
    }
}

// MARK: - Header
private extension EventPromoterDashboardView {
    var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Circle().fill(Color.white.opacity(0.06)).frame(width: 42, height: 42)
                    .overlay(Image(systemName: "megaphone.fill").font(.title3).foregroundStyle(Color.gold))
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title).font(.title2.bold()).foregroundStyle(.white).lineLimit(2)
                    Text(lang == "es" ? "Administrar Evento" : "Manage Event")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
                        .padding(10).background(.white.opacity(0.06), in: Circle())
                }
                .accessibilityLabel(lang == "es" ? "Cerrar" : "Close")
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Overview cards
private extension EventPromoterDashboardView {
    var overview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(lang == "es" ? "Resumen" : "Overview")
                    .font(.headline).foregroundStyle(.white.opacity(0.9))
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        currencyCode = (currencyCode == "USD") ? "VES" : "USD"
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: currencyCode == "USD" ? "dollarsign.circle" : "coloncurrencysign.circle")
                        Text(currencyCode == "USD" ? "USD" : "Bs.")
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .foregroundStyle(.white)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))
                }
                .contextMenu {
                    Button(currencyCode == "USD" ? "Cambiar a Bolívares (VES)" : "Switch to USD") {
                        currencyCode = (currencyCode == "USD") ? "VES" : "USD"
                    }
                    Button("Set USD → VES rate…") { showVESRateSheet = true }
                }
            }
            .padding(.horizontal)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCard(title: lang == "es" ? "Promotores" : "Promoters", value: "\(totalPromoters)", icon: "person.3.fill")
                StatCard(title: lang == "es" ? "Compradores" : "Buyers", value: "\(totalBuyers)", icon: "cart.fill")
                StatCard(title: lang == "es" ? "Pagados" : "Paid", value: "\(paidCount)", icon: "checkmark.seal.fill", accent: .green)
                StatCard(title: lang == "es" ? "Pendientes" : "Pending", value: "\(pendingCount)", icon: "hourglass", accent: .orange)
                StatCard(title: lang == "es" ? "Espera" : "Waitlist", value: "\(waitlistPending)", icon: "clock.badge.questionmark", accent: .yellow)

                StatCard(
                    title: lang == "es" ? "Ingresos" : "Revenue",
                    value: formatMoney(usd: totalRevenueUSD),
                    icon: "dollarsign.circle.fill",
                    accent: .gold
                )
            }
            .padding(.horizontal)
        }
        .sheet(isPresented: $showVESRateSheet) {
            if #available(iOS 16.0, *) {
                if #available(iOS 16.4, *) {
                    VESRateSheet(rate: $vesPerUSD)
                        .presentationDetents([.height(220)])
                } else {
                    VESRateSheet(rate: $vesPerUSD)
                        .presentationDetents([.medium])
                }
            } else {
                VESRateSheet(rate: $vesPerUSD)
            }
        }
    }
}

private struct VESRateSheet: View {
    @Binding var rate: Double
    @Environment(\.dismiss) private var dismiss

    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 4
        f.minimumFractionDigits = 2
        return f
    }()

    var body: some View {
        VStack(spacing: 16) {
            Text("USD → VES Rate").font(.headline)

            HStack(spacing: 8) {
                Text("1 USD =")
                TextField("Rate", value: $rate, formatter: Self.formatter)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .padding(10)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") { dismiss() }
                        }
                    }
                Text("VES")
            }
            .font(.body)

            Button("Done") { dismiss() }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.gold, in: RoundedRectangle(cornerRadius: 12))
                .foregroundColor(.black)
        }
        .padding()
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Tab switcher
private extension EventPromoterDashboardView {
    var tabSwitcher: some View {
        HStack(spacing: 6) {
            TabPill(title: lang == "es" ? "Promotores" : "Promoters", icon: "person.2.fill", isActive: tab == .promoters) { tab = .promoters }
            TabPill(title: lang == "es" ? "Pagos" : "Payments", icon: "creditcard.fill", isActive: tab == .payments) { tab = .payments }
            TabPill(title: lang == "es" ? "Espera" : "Waitlist", icon: "list.bullet.rectangle.portrait.fill", isActive: tab == .waitlist) { tab = .waitlist }
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }
}

// MARK: - Tab content
private extension EventPromoterDashboardView {
    @ViewBuilder var tabContent: some View {
        switch tab {
        case .promoters: promotersTab
        case .payments: paymentsTab
        case .waitlist: waitlistTab
        }
    }

    var promotersTab: some View {
        VStack(spacing: 16) {
            if isLoading { LoadingRow(text: lang == "es" ? "Cargando…" : "Loading…") }
            if !isLoading && promoters.isEmpty { EmptyRow(text: lang == "es" ? "Sin promotores aún." : "No promoters yet.") }

            ForEach(promoters) { pe in
                PromoterCard(
                    pe: pe,
                    eventId: event.id,
                    expandedPromoterId: $expandedPromoterId,
                    buyersByPromoter: $buyersByPromoter,
                    onCopy: { text in showToast(text, .green) },
                    fetchBuyers: fetchBuyers
                )
            }

            // Add promoter area
            VStack(spacing: 10) {
                ZStack(alignment: .topLeading) {
                    TypeaheadField(
                        placeholder: lang == "es" ? "Usuario para agregar" : "Username to add",
                        text: $userIdInput,
                        isSearching: isSearchingUsers,
                        iconSystemName: "person.crop.circle.badge.plus",
                        onChange: { newValue in handleDebouncedUserSearch(newValue) },
                        onSubmit: { if let first = suggestions.first { userIdInput = first.username }; hideSuggestions() }
                    )
                    if showSuggestions && !suggestions.isEmpty {
                        SuggestionsList(items: suggestions) { item in
                            userIdInput = item.username
                            hideSuggestions()
                        }
                        .offset(y: 52)
                    }
                }
                Button(action: assignPromoter) {
                    HStack {
                        Spacer()
                        if assigning { ProgressView().tint(.black) }
                        Text(lang == "es" ? "Asignar promotor" : "Assign promoter").bold()
                        Spacer()
                    }
                }
                .padding(.vertical, 12)
                .background(Color.gold, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.black)
                .buttonStyle(.plain)
                .disabled(assigning || userIdInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal)
            .padding(.top, 6)
            
            // Owner-only: create the promoter chat explicitly
            if isEventOwner() {
                VStack(alignment: .leading, spacing: 8) {
                    Button(action: createPromoterGroup) {
                        HStack(spacing: 10) {
                            if creatingGroup { ProgressView().tint(.black) }
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                            Text(lang == "es" ? "Crear chat de promotores" : "Create promoter chat")
                                .font(.subheadline.bold())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.gold, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.black)
                    }
                    .buttonStyle(.plain)
                    .disabled(creatingGroup || promoterGroupMemberIds().count < 2)

                    if let rid = createdRoomId {
                        Text((lang == "es" ? "Chat creado. ID: " : "Chat created. ID: ") + "\(rid)")
                            .font(.footnote).foregroundColor(.white.opacity(0.75))
                    }
                    if let groupError {
                        Text(groupError)
                            .font(.footnote).foregroundColor(.red)
                    }
                }
                .padding(.horizontal)
            }

        }
        .onTapGesture { hideSuggestions() }
    }

    var paymentsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.gold)
                TextField(lang == "es" ? "Buscar por nombre, correo o método" : "Search name, email, or method",
                          text: $paymentQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(10)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.white)
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PaymentFilter.allCases) { f in
                        FilterChip(title: f.label, isActive: filterPayment == f) { filterPayment = f }
                    }
                }
                .padding(.horizontal)
            }

            if dashboardTickets.isEmpty {
                EmptyRow(text: lang == "es" ? "Sin compras todavía." : "No buyers yet.")
            } else {
                let filtered = filteredTickets()
                VStack(spacing: 12) {
                    ForEach(filtered) { ticket in
                        let priceUSD = event.ticketTiers.first(where: { $0.name == ticket.tierName })?.price
                        let priceText = priceUSD.map { formatMoney(usd: $0) } ?? "—"

                        TicketRow(
                            ticket: ticket,
                            isOwner: isEventOwner(),
                            isManual: isManual(ticket: ticket),
                            isUpdating: isUpdatingStatus,
                            togglePaid: { togglePaidStatus(for: ticket) },
                            event: event,
                            priceText: priceText
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    var waitlistTab: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: selectAllWaitlist) {
                    Label(lang == "es" ? "Seleccionar Todo" : "Select All", systemImage: "checkmark.circle")
                }.buttonStyle(.bordered).tint(.gold)

                Button(action: { selectedWaitlist.removeAll() }) {
                    Label(lang == "es" ? "Limpiar" : "Clear", systemImage: "xmark.circle")
                }.buttonStyle(.bordered).tint(.gray)

                Spacer()

                Menu {
                    Button(role: .none) { bulkUpdateWaitlist(to: "APPROVED") } label: {
                        Label(lang == "es" ? "Aprobar seleccionados" : "Approve selected", systemImage: "checkmark")
                    }
                    Button(role: .destructive) { bulkUpdateWaitlist(to: "DENIED") } label: {
                        Label(lang == "es" ? "Denegar seleccionados" : "Deny selected", systemImage: "xmark")
                    }
                } label: {
                    HStack {
                        if isBulkWorking { ProgressView().scaleEffect(0.8) }
                        Text(lang == "es" ? "Acciones" : "Actions")
                        Image(systemName: "chevron.down")
                    }
                    .padding(.vertical, 8).padding(.horizontal, 12)
                    .background(Color.white.opacity(0.08), in: Capsule())
                    .foregroundStyle(.white)
                }
                .disabled(selectedWaitlist.isEmpty || isBulkWorking)
            }
            .padding(.horizontal)

            if waitlistEntries.isEmpty {
                EmptyRow(text: lang == "es" ? "No hay solicitudes." : "No waitlist requests.")
            } else {
                VStack(spacing: 12) {
                    ForEach(waitlistEntries) { entry in
                        WaitlistRowSelectable(
                            entry: entry,
                            isSelected: selectedWaitlist.contains(entry.id),
                            toggle: { toggleWaitlistSelection(entry.id) },
                            approve: { updateWaitlistStatus(entryId: entry.id, status: "APPROVED") },
                            deny: { updateWaitlistStatus(entryId: entry.id, status: "DENIED") },
                            statusText: statusText,
                            colorForStatus: colorForStatus
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Filtering helpers
private extension EventPromoterDashboardView {
    func normalized(_ s: String?) -> String {
        guard let s = s, !s.isEmpty else { return "" }
        return s.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
    }
    func ticketMatchesFilter(_ t: TicketDTO) -> Bool {
        let method = normalized(t.paymentMethod)
        switch filterPayment {
        case .all: return true
        case .paid: return t.paid
        case .pending: return !t.paid
        case .card: return method == "card" || method == "stripe" || method == "applepay"
        case .zelle: return method == "zelle"
        case .pagomovil: return method == "pagomovil"
        case .cash: return method == "cash" || method == "efectivo"
        }
    }
    

    
    func promoterGroupMemberIds() -> [Int] {
        var ids = Set<Int>()
        if let ownerId = event.createdBy?.id { ids.insert(ownerId) }
        for pe in promoters {
            if let uid = pe.promoter?.user.id { ids.insert(uid) }
        }
        return Array(ids)
    }

    func createPromoterGroup() {
        guard isEventOwner() else {
            showToast(lang == "es" ? "Solo el organizador puede crear el chat" : "Only the organizer can create this chat", .orange)
            return
        }

        let members = promoterGroupMemberIds()
        guard members.count >= 2 else {
            showToast(lang == "es" ? "Agrega al menos un promotor" : "Add at least one promoter first", .orange)
            return
        }

        creatingGroup = true
        groupError = nil

        ChatAPI.shared.setTokenProvider { TokenManager.shared.getAccessToken() }

        Task {
            do {
                let roomId = try await ChatAPI.shared.promoterGroup(eventId: event.id, promoterUserIds: members)
                await MainActor.run {
                    self.creatingGroup = false
                    self.createdRoomId = roomId
                    self.showToast(lang == "es" ? "Chat de promotores listo" : "Promoter chat created", .green)
                    NotificationCenter.default.post(name: .chatListNeedsRefresh, object: nil)
                }
            } catch {
                await MainActor.run {
                    self.creatingGroup = false
                    if let e = error as? ChatAPI.ChatErr {
                        switch e {
                        case .notAuthorized:
                            self.groupError = lang == "es" ? "No autorizado. Verifica tu sesión." : "Not authorized. Check your session."
                        case .server(let code):
                            self.groupError = "Server \(code)"
                        case .badResponse:
                            self.groupError = "Bad response"
                        case .badPayload:
                            self.groupError = "Bad payload"
                        }
                    } else {
                        self.groupError = error.localizedDescription
                    }
                    self.showToast(lang == "es" ? "No se pudo crear el chat" : "Failed to create promoter chat", .red)
                }
            }
        }
    }

    func ticketMatchesQuery(_ t: TicketDTO) -> Bool {
        let q = normalized(paymentQuery)
        if q.isEmpty { return true }
        let first = normalized(t.buyerFirstName)
        let last  = normalized(t.buyerLastName)
        let name  = first + last
        let email = normalized(t.buyerEmail)
        let method = normalized(t.paymentMethod)
        return name.contains(q) || email.contains(q) || method.contains(q)
    }
    func filteredTickets() -> [TicketDTO] {
        dashboardTickets.filter { ticketMatchesFilter($0) && ticketMatchesQuery($0) }
    }
}

// MARK: - Subviews (cards, chips, etc.)
private struct StatCard: View {
    let title: String; let value: String; let icon: String; var accent: Color = .gold
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Image(systemName: icon).foregroundStyle(accent); Spacer() }
            Text(value).font(.title2.bold()).foregroundStyle(.white)
            Text(title).font(.footnote).foregroundStyle(.white.opacity(0.6))
        }
        .padding(14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.gold.opacity(0.12), lineWidth: 1))
    }
}

private struct TabPill: View {
    let title: String; let icon: String; let isActive: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) { Image(systemName: icon); Text(title).font(.subheadline.weight(.semibold)).lineLimit(1) }
                .foregroundStyle(isActive ? .black : .white.opacity(0.8))
                .padding(.vertical, 8).padding(.horizontal, 12)
                .background(isActive ? Color.gold : Color.white.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct LoadingRow: View {
    let text: String
    var body: some View {
        HStack { Spacer(); ProgressView(text).tint(.gold); Spacer() }
            .padding(.vertical, 24)
    }
}

private struct EmptyRow: View {
    let text: String
    var body: some View {
        Text(text).foregroundStyle(.white.opacity(0.6)).padding(.vertical, 28)
            .frame(maxWidth: .infinity)
            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
    }
}

private struct FilterChip: View {
    let title: String; let isActive: Bool; let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            Text(title).font(.caption.weight(.semibold))
                .padding(.vertical, 8).padding(.horizontal, 12)
                .background(isActive ? Color.gold : Color.white.opacity(0.08), in: Capsule())
                .foregroundStyle(isActive ? .black : .white)
        }
        .buttonStyle(.plain)
    }
}




private struct TicketRow: View {
    @AppStorage("selectedLanguage") var lang: String = "en"
    let ticket: TicketDTO
    let isOwner: Bool
    let isManual: Bool
    let isUpdating: Bool
    let togglePaid: () -> Void
    let event: Event
    let priceText: String
    @State private var dashboardTickets: [TicketDTO] = []
    @State private var toast: (String, Color, String)? = nil  // (message, tint, SF Symbol)


    // Drop-in for TicketRow.resolvedProofURL(_:)
    private func resolvedProofURL(_ raw: String?) -> URL? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) // strip stray quotes
        if let u = URL(string: s), u.scheme == "http" || u.scheme == "https" { return u }
        if !s.hasPrefix("/") { s = "/" + s }
        return URL(string: "https://backendevent-etce.onrender.com" + s)
    }
    
    func presentImagePicker(ticketId: Int) {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.allowsEditing = true

        UIApplication.shared.windows.first?.rootViewController?.present(picker, animated: true)

        picker.delegate = ImagePickerDelegateWrapper { image in
            guard let imgData = image.jpegData(compressionQuality: 0.85),
                  let token = TokenManager.shared.getAccessToken(),
                  let url = URL(string: "https://backendevent-etce.onrender.com/api/tickets/\(ticketId)/proof") else { return }

            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            // Multipart form data
            let boundary = UUID().uuidString
            req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            var body = Data()
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"receipt.jpg\"\r\n")
            body.append("Content-Type: image/jpeg\r\n\r\n")
            body.append(imgData)
            body.append("\r\n--\(boundary)--\r\n")
            req.httpBody = body

            URLSession.shared.dataTask(with: req) { data, resp, _ in
                if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                    DispatchQueue.main.async {
                        showToaster("Receipt uploaded", Color.green)
                        fetchDashboardTicketse()
                    }
                }
            }.resume()
        }
    }
    
    private func fetchDashboardTicketse() {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/api/tickets/event/\(event.id)/dashboard") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request) { data, resp, _ in
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let data = data, !data.isEmpty else { return }

            let dec = JSONDecoder()
            dec.keyDecodingStrategy = .convertFromSnakeCase
            if let decoded = try? dec.decode([TicketDTO].self, from: data) {
                DispatchQueue.main.async { self.dashboardTickets = decoded }
            }
        }.resume()
    }
    
    func showToaster(_ text: String, _ color: Color, icon: String? = nil) {
       let chosenIcon = icon ?? (color == .green ? "checkmark.circle.fill"
                                 : color == .red   ? "xmark.octagon.fill"
                                                   : "exclamationmark.circle.fill")
       let haptic: UINotificationFeedbackGenerator.FeedbackType =
           (color == .green) ? .success : (color == .red ? .error : .warning)
       UINotificationFeedbackGenerator().notificationOccurred(haptic)

       withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
           toast = (text, color, chosenIcon)
       }
       DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
           withAnimation { toast = nil }
       }
   }

    final class ImagePickerDelegateWrapper: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let completion: (UIImage) -> Void
        init(completion: @escaping (UIImage) -> Void) { self.completion = completion }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let img = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage {
                completion(img)
            }
            picker.dismiss(animated: true)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
    
    

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top row: name + status badge
            HStack(alignment: .firstTextBaseline) {
                let first = ticket.buyerFirstName ?? ""
                let last  = ticket.buyerLastName ?? ""
                Text("\(first) \(last)".trimmingCharacters(in: .whitespaces))
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                StatusBadge(
                    paid: ticket.paid,
                    isOwner: isOwner,
                    isManual: isManual,
                    isUpdating: isUpdating,
                    toggle: togglePaid
                )
            }

            // Email
            if let email = ticket.buyerEmail, !email.isEmpty {
                Text(email)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
            }

            // Receipt dropdown + full image preview
            if let url = resolvedProofURL(ticket.proofUrl) {
                ReceiptDropdownView(receiptURL: url)
            } else if isOwner && isManual {
                HStack(spacing: 6) {
                    Text(lang == "es" ? "No recivo" : "No Receipt")
                        .foregroundStyle(.white)
                }
            }


            // Method + price line
            HStack(spacing: 6) {
                Text(lang == "es" ? "Método:" : "Method:")
                    .foregroundStyle(.white.opacity(0.6))
                    .font(.caption)

                Text((ticket.paymentMethod ?? "—")
                        .replacingOccurrences(of: "_", with: " ")
                        .capitalized)
                    .foregroundStyle(Color.gold)
                    .font(.caption)

                Spacer()

                Text(priceText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.06)))
    }
}

private struct ReceiptDropdownView: View {
    let receiptURL: URL
    @State private var isExpanded = false
    @State private var showFullImage = false
    @State private var image: UIImage? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
                if image == nil {
                    Task {
                        await loadImage()
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.magnifyingglass")
                    Text(isExpanded ? "Hide receipt" : "View receipt")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(Color.gold)
            }
            .buttonStyle(.plain)

            if isExpanded, let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 160)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.2)))
                    .onTapGesture { showFullImage = true }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .sheet(isPresented: $showFullImage) {
            if let image {
                ZStack {
                    Color.black.ignoresSafeArea()
                    
                    GeometryReader { geo in
                        ScrollView([.horizontal, .vertical]) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)   // ✅ ensures no weird stretching
                                .frame(
                                    width: geo.size.width,
                                    height: geo.size.height,
                                    alignment: .center
                                )
                                .clipped()
                        }
                        .ignoresSafeArea()
                    }
                    
                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                showFullImage = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.white)
                                    .padding()
                            }
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    private func loadImage() async {
        do {
            let (data, _) = try await URLSession.shared.data(from: receiptURL)
            if let img = UIImage(data: data) {
                await MainActor.run { image = img }
            }
        } catch {
            print("⚠️ Failed to load receipt image:", error)
        }
    }
}


private struct StatusBadge: View {
    let paid: Bool; let isOwner: Bool; let isManual: Bool; let isUpdating: Bool; let toggle: () -> Void
    var body: some View {
        if isOwner && isManual {
            Menu {
                Button(paid ? "Mark Pending" : "Mark Paid", action: toggle)
            } label: {
                HStack(spacing: 6) {
                    if isUpdating { ProgressView().scaleEffect(0.8) }
                    Text(paid ? "Paid" : "Pending").font(.caption.weight(.semibold))
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(paid ? Color.green : Color.orange, in: Capsule())
                .foregroundStyle(.black)
            }
        } else {
            Text(paid ? "Paid" : "Pending")
                .font(.caption.weight(.semibold))
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(paid ? Color.green.opacity(0.9) : Color.orange.opacity(0.9), in: Capsule())
                .foregroundStyle(.black)
        }
    }
}

private struct WaitlistRowSelectable: View {
    let entry: WaitlistEntry
    let isSelected: Bool
    let toggle: () -> Void
    let approve: () -> Void
    let deny: () -> Void
    let statusText: (String) -> String
    let colorForStatus: (String) -> Color
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: toggle) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.gold : .white.opacity(0.6))
                    .font(.title3)
            }.buttonStyle(.plain)
            Circle().fill(Color.white.opacity(0.08)).frame(width: 42, height: 42)
                .overlay(Image(systemName: "person.fill").foregroundStyle(Color.gold))
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.fullName).foregroundStyle(.white).font(.subheadline.weight(.semibold))
                Text("@\(entry.username)").foregroundStyle(.white.opacity(0.6)).font(.caption)
                Text(statusText(entry.status))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(colorForStatus(entry.status))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.white.opacity(0.06), in: Capsule())
            }
            Spacer()
            if entry.status == "PENDING" {
                HStack(spacing: 8) {
                    Button(action: approve) { Text("") }
                        .buttonStyle(.borderedProminent).tint(.green).labelStyle(.titleOnly)
                        .overlay(Label("Approve", systemImage: "checkmark").labelStyle(.iconOnly).foregroundStyle(.white))
                    Button(action: deny) { Text("") }
                        .buttonStyle(.borderedProminent).tint(.red).labelStyle(.titleOnly)
                        .overlay(Label("Deny", systemImage: "xmark").labelStyle(.iconOnly).foregroundStyle(.white))
                }
            }
        }
        .padding(14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.06)))
    }
}

private struct PromoterCard: View {
    @AppStorage("selectedLanguage") var lang: String = "en"
    let pe: PromoterEvent
    let eventId: Int
    @Binding var expandedPromoterId: Int?
    @Binding var buyersByPromoter: [Int: [ReferredBuyerDTO]]
    let onCopy: (String) -> Void
    let fetchBuyers: (PromoterEvent) -> Void

    private var promoterId: Int? { pe.promoter?.id }
    private var fullName: String { pe.promoter?.user.fullName ?? "Promoter" }
    private var username: String? { pe.promoter?.user.username }
    private var referralLink: String? {
        guard let u = username,
              let enc = u.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return nil }
        return "https://wkndevent.com/#/events/\(eventId)?ref=\(enc)"
    }
    private var isExpanded: Bool { expandedPromoterId == promoterId }
    private var buyers: [ReferredBuyerDTO] {
        guard let id = promoterId else { return [] }
        return buyersByPromoter[id] ?? []
    }
    
    private var grossFromBuyers: Double {
        buyers.reduce(0) { sum, b in
            let q = Double(b.quantity ?? 1)
            let p = b.unitPrice ?? 0
            return sum + q * p
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            referralRow
            buyersSection
        }
        .padding(14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.06)))
        .padding(.horizontal)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text(fullName).font(.headline).foregroundStyle(.white)
                if let u = username { Text("@\(u)").font(.footnote).foregroundStyle(.white.opacity(0.7)) }
                HStack(spacing: 6) { Image(systemName: "ticket.fill"); Text("\(pe.ticketsSold) sold") }
                    .font(.caption).foregroundStyle(Color.gold)
            }
            Spacer()
            Button(action: toggleExpanded) {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.white.opacity(0.06), in: Circle())
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                let gross = pe.grossRevenue ?? grossFromBuyers
                if gross > 0 {
                    Text("Gross $\(gross, specifier: "%.2f")")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var referralRow: some View {
        if let link = referralLink, let url = URL(string: link) {
            HStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = link
                    onCopy(lang == "es" ? "¡Enlace copiado!" : "Link copied")
                } label: {
                    Label(lang == "es" ? "Copiar" : "Copy", systemImage: "link")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.gold)

                ShareLink(item: url) {
                    Label(lang == "es" ? "Compartir" : "Share", systemImage: "square.and.arrow.up")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(Color.gold)

                Link(lang == "es" ? "Abrir" : "Open", destination: url)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.gold)

                Spacer(minLength: 0)
                Text(link)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    @ViewBuilder private var buyersSection: some View {
        if isExpanded {
            VStack(alignment: .leading, spacing: 8) {
                Divider().overlay(Color.white.opacity(0.1))
                ForEach(buyers, id: \.id) { buyer in
                    BuyerRow(buyer: buyer)
                    Divider().overlay(Color.white.opacity(0.06))
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func toggleExpanded() {
        if isExpanded { expandedPromoterId = nil } else { fetchBuyers(pe) }
    }
}

private struct BuyerRow: View {
    let buyer: ReferredBuyerDTO

    private var qty: Int { buyer.quantity ?? 1 }
    private var price: Double { buyer.unitPrice ?? 0 }
    private var priceText: String { String(format: "$%.2f", price) }
    private var usernameText: String { buyer.username ?? "Buyer" }
    private var emailText: String { buyer.email ?? "" }
    private var timeText: String { relativeTime(from: buyer.timestamp) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(usernameText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                if !emailText.isEmpty {
                    Text(emailText)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if !timeText.isEmpty {
                    Text(timeText)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Spacer(minLength: 0)

            Text("x\(qty) • \(priceText)")
                .font(.caption.weight(.semibold))
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Color.white.opacity(0.08), in: Capsule())
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
                .foregroundStyle(Color.gold)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Time helpers
private func relativeTime(from iso: String?) -> String {
    guard let iso, let date = parseISO(iso) else { return "" }
    let rel = RelativeDateTimeFormatter()
    rel.unitsStyle = .abbreviated
    return rel.localizedString(for: date, relativeTo: Date())
}

private func parseISO(_ s: String) -> Date? {
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = iso.date(from: s) { return d }

    let f1 = DateFormatter()
    f1.locale = Locale(identifier: "en_US_POSIX")
    f1.timeZone = TimeZone(secondsFromGMT: 0)
    f1.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    if let d = f1.date(from: s) { return d }

    let f2 = DateFormatter()
    f2.locale = Locale(identifier: "en_US_POSIX")
    f2.timeZone = TimeZone(secondsFromGMT: 0)
    f2.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
    return f2.date(from: s)
}

// MARK: - Networking & Helpers
private extension EventPromoterDashboardView {
    func loadAll() {
        guard !isBootLoading else { return }
        isBootLoading = true
        isLoading = true
        fetchPromoters()
        fetchDashboardTickets()
        fetchWaitlist()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            isLoading = false
            isBootLoading = false
        }
    }

    // MARK: - Currency helpers
    private func formatMoney(usd amount: Double) -> String {
        let useVES = currencyCode.uppercased() == "VES"
        let value  = useVES ? (amount * max(vesPerUSD, 0)) : amount

        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 2
        if useVES {
            f.currencyCode = "VES"
            f.locale = Locale(identifier: "es_VE")
            return f.string(from: NSNumber(value: value)) ?? String(format: "Bs. %.2f", value)
        } else {
            f.currencyCode = "USD"
            f.locale = Locale(identifier: "en_US")
            return f.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
        }
    }

    private var totalRevenueUSD: Double {
        dashboardTickets
            .filter { $0.paid }
            .reduce(0.0) { acc, t in
                let price = t.unitPrice
                    ?? event.ticketTiers.first(where: { $0.name == t.tierName })?.price
                    ?? 0.0
                return acc + (price * Double(max(1, t.quantity)))
            }
    }

    func refreshAll() async {
        isRefreshing = true
        await withTaskGroup(of: Void.self) { group in
            group.addTask { fetchPromoters() }
            group.addTask { fetchDashboardTickets() }
            group.addTask { fetchWaitlist() }
        }
        isRefreshing = false
    }
    
    private func upsertPromoterGroupMembers() {
        ChatAPI.shared.setTokenProvider { TokenManager.shared.getAccessToken() }

        var ids = Set<Int>()
        if let ownerId = event.createdBy?.id { ids.insert(ownerId) }
        for pe in promoters {
            if let uid = pe.promoter?.user.id { ids.insert(uid) }
        }
        guard !ids.isEmpty else { return }

        Task {
            do {
                _ = try await ChatAPI.shared.promoterGroup(
                    eventId: event.id,
                    promoterUserIds: Array(ids)
                )
                NotificationCenter.default.post(name: .chatListNeedsRefresh, object: nil)
            } catch {
                print("❌ promoterGroup upsert failed:", error.localizedDescription)
            }
        }
    }

    func fetchPromoters() {
        guard let token = TokenManager.shared.getAccessToken() else { return }
        var request = URLRequest(url: URL(string: "https://backendevent-etce.onrender.com/api/promoters/event/\(event.id)/dashboard")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, resp, _ in
            guard let http = resp as? HTTPURLResponse else { return }
            let ctype = http.value(forHTTPHeaderField: "Content-Type") ?? "nil"
            let bodyStr = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            print("ℹ️ dashboard(status=\(http.statusCode), ctype=\(ctype), len=\(data?.count ?? 0))")
            guard http.statusCode == 200 else {
                print("⚠️ Non-200 dashboard: \(bodyStr)")
                DispatchQueue.main.async { self.promoters = [] }
                return
            }
            guard let data, !data.isEmpty else {
                DispatchQueue.main.async { self.promoters = [] }
                return
            }
            guard ctype.lowercased().contains("application/json") else {
                print("⚠️ Non-JSON dashboard body: \(bodyStr)")
                DispatchQueue.main.async { self.promoters = [] }
                return
            }
            do {
                let decoded = try JSONDecoder().decode([PromoterEventView].self, from: data)
                let mapped: [PromoterEvent] = decoded.map { v in
                    let username = v.promoter.user.username ?? ""
                    let (first, last) = splitFullName(v.promoter.user.fullName)
                    let userDTO = UserDTO(id: v.promoter.user.id, firstName: first, lastName: last, username: username)
                    let promoterDTO = PromoterDTO(id: v.promoter.id, referralCode: username, user: userDTO)
                    return PromoterEvent(id: v.id, ticketsSold: v.ticketsSold, event: nil, promoter: promoterDTO, grossRevenue: v.grossRevenue )
                }
                DispatchQueue.main.async {
                    self.promoters = mapped
                }
            } catch {
                print("❌ Decode failed: \(error)")
                if let s = String(data: data, encoding: .utf8) { print("Raw: \(s)") }
                DispatchQueue.main.async { self.promoters = [] }
            }
        }.resume()
    }

    private func splitFullName(_ fullName: String) -> (String, String) {
        let parts = fullName.split(separator: " ")
        guard let first = parts.first else { return ("", "") }
        let last = parts.dropFirst().joined(separator: " ")
        return (String(first), last)
    }

    func fetchWaitlist() {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/events/\(event.id)/waitlist") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request) { data, resp, _ in
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200, let data = data, !data.isEmpty else { return }
            if let decoded = try? JSONDecoder().decode([WaitlistEntry].self, from: data) {
                DispatchQueue.main.async { self.waitlistEntries = decoded }
            }
        }.resume()
    }

    private func fetchDashboardTickets() {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/api/tickets/event/\(event.id)/dashboard") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request) { data, resp, _ in
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let data = data, !data.isEmpty else { return }

            let dec = JSONDecoder()
            dec.keyDecodingStrategy = .convertFromSnakeCase
            if let decoded = try? dec.decode([TicketDTO].self, from: data) {
                DispatchQueue.main.async { self.dashboardTickets = decoded }
            }
        }.resume()
    }

    func togglePaidStatus(for ticket: TicketDTO) {
        // Require proof for manual → PAID
        if isManual(ticket: ticket),
           ticket.paid == false,
           (ticket.proofUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            showToast(lang == "es" ? "Adjunta el recibo antes de marcar como pagado"
                                   : "Attach receipt before marking as paid",
                      .orange, icon: "exclamationmark.triangle.fill")
            return
        }

        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/api/tickets/\(ticket.id)/toggle-paid") else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        isUpdatingStatus = true
        URLSession.shared.dataTask(with: req) { data, _, _ in
            DispatchQueue.main.async { self.isUpdatingStatus = false }

            guard let data,
                  let result = try? JSONDecoder().decode([String: Bool].self, from: data),
                  let newPaid = result["paid"] else { return }

            DispatchQueue.main.async {
                if let idx = self.dashboardTickets.firstIndex(where: { $0.id == ticket.id }) {
                    self.dashboardTickets[idx].paid = newPaid
                }
            }
        }.resume()
    }


    func fetchBuyers(for promoter: PromoterEvent) {
        guard let promoterId = promoter.promoter?.id else { return }
        guard let token = TokenManager.shared.getAccessToken() else { return }
        let url = URL(string: "https://backendevent-etce.onrender.com/api/promoters/event/\(event.id)/promoter/\(promoterId)/buyers")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request) { data, resp, _ in
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200, let data = data, !data.isEmpty else { return }
            let dec = JSONDecoder()
            dec.keyDecodingStrategy = .convertFromSnakeCase
            if let decoded = try? dec.decode([ReferredBuyerDTO].self, from: data) {
                DispatchQueue.main.async {
                    buyersByPromoter[promoterId] = decoded
                    expandedPromoterId = promoterId
                }
            }
        }.resume()
    }

    // --- Typeahead search ---
    func handleDebouncedUserSearch(_ newValue: String) {
        searchWorkItem?.cancel()
        let work = DispatchWorkItem { self.searchUsers(newValue) }
        searchWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    func searchUsers(_ q: String) {
        let term = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 1 else {
            withAnimation { self.suggestions = []; self.showSuggestions = false }
            return
        }
        guard let token = TokenManager.shared.getAccessToken() else { return }

        isSearchingUsers = true

        var comps = URLComponents(string: "https://backendevent-etce.onrender.com/api/promoters/search")!
        comps.queryItems = [URLQueryItem(name: "q", value: term)]
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: req) { data, resp, _ in
            DispatchQueue.main.async {
                self.isSearchingUsers = false
                guard let http = resp as? HTTPURLResponse, http.statusCode == 200, let data = data, !data.isEmpty,
                      let decoded = try? JSONDecoder().decode([UserSearchResult].self, from: data) else {
                    self.suggestions = []
                    self.showSuggestions = false
                    return
                }
                withAnimation {
                    self.suggestions = decoded
                    self.showSuggestions = !decoded.isEmpty
                }
            }
        }.resume()
    }

    func hideSuggestions() { withAnimation { showSuggestions = false } }

    func assignPromoter() {
        let username = userIdInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty else {
            showToast(lang == "es" ? "Usuario inválido" : "Invalid username", .orange)
            return
        }
        guard let token = TokenManager.shared.getAccessToken() else { return }

        assigning = true
        var comps = URLComponents(string: "https://backendevent-etce.onrender.com/api/promoters/\(event.id)/assign")!
        comps.queryItems = [URLQueryItem(name: "username", value: username)]
        var request = URLRequest(url: comps.url!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, response, _ in
            DispatchQueue.main.async { assigning = false }

            guard let http = response as? HTTPURLResponse else {
                DispatchQueue.main.async { showToast("Network error", .red) }
                return
            }

            if (200...299).contains(http.statusCode) {
                DispatchQueue.main.async {
                    showToast(lang == "es" ? "Promotor asignado" : "Promoter assigned",
                              .green, icon: "checkmark.circle.fill")
                    userIdInput = ""
                    suggestions.removeAll()
                    showSuggestions = false
                    fetchPromoters()
                }
                return
            }

            let serverMessage = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""

            let msg: String
            switch http.statusCode {
            case 404:
                msg = lang == "es" ? "Usuario no encontrado" : "User not found"
            case 409:
                msg = lang == "es" ? "Ya es promotor de este evento" : "Already a promoter for this event"
            case 401, 403:
                msg = lang == "es" ? "No autorizado" : "Not authorized"
            default:
                msg = serverMessage.isEmpty
                    ? (lang == "es" ? "No se pudo asignar" : "Failed to assign")
                    : serverMessage
            }

            DispatchQueue.main.async {
                showToast(msg, .red, icon: "xmark.octagon.fill")
            }
        }.resume()
    }

    func isManual(ticket: TicketDTO) -> Bool {
        guard let method = ticket.paymentMethod?.lowercased() else { return false }
        return ["zelle", "pagomovil", "cash"].contains(method)
    }
    func isEventOwner() -> Bool {
        if userSession.role == "ADMIN" { return true }
        guard let ownerId = event.createdBy?.id else { return false }
        return userSession.userId == ownerId
    }

    func statusText(_ status: String) -> String {
        switch status {
        case "APPROVED": return lang == "es" ? "Aprobado" : "Approved"
        case "DENIED": return lang == "es" ? "Denegado" : "Denied"
        default: return lang == "es" ? "Pendiente" : "Pending"
        }
    }
    func colorForStatus(_ status: String) -> Color {
        switch status { case "APPROVED": return .green; case "DENIED": return .red; default: return .orange }
    }
    func updateWaitlistStatus(entryId: Int, status: String) {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/events/\(event.id)/waitlist/\(entryId)/status?status=\(status)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request) { _, _, _ in fetchWaitlist() }.resume()
    }
    func selectAllWaitlist() { selectedWaitlist = Set(waitlistEntries.filter{ $0.status == "PENDING" }.map{ $0.id }) }
    func toggleWaitlistSelection(_ id: Int) {
        if selectedWaitlist.contains(id) { selectedWaitlist.remove(id) } else { selectedWaitlist.insert(id) }
    }
    func bulkUpdateWaitlist(to status: String) {
        guard !selectedWaitlist.isEmpty else { return }
        isBulkWorking = true
        let ids = Array(selectedWaitlist)
        let group = DispatchGroup()
        ids.forEach { id in
            group.enter()
            DispatchQueue.global().async { updateWaitlistStatus(entryId: id, status: status); group.leave() }
        }
        group.notify(queue: .main) {
            isBulkWorking = false
            selectedWaitlist.removeAll()
            fetchWaitlist()
            let msg = status == "APPROVED" ? (lang == "es" ? "Aprobados" : "Approved")
                                           : (lang == "es" ? "Denegados" : "Denied")
            showToast(msg, .green)
        }
    }

     func showToast(_ text: String, _ color: Color, icon: String? = nil) {
        let chosenIcon = icon ?? (color == .green ? "checkmark.circle.fill"
                                  : color == .red   ? "xmark.octagon.fill"
                                                    : "exclamationmark.circle.fill")
        let haptic: UINotificationFeedbackGenerator.FeedbackType =
            (color == .green) ? .success : (color == .red ? .error : .warning)
        UINotificationFeedbackGenerator().notificationOccurred(haptic)

        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            toast = (text, color, chosenIcon)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { toast = nil }
        }
    }

    func eventDateString(_ iso: String?) -> String {
        guard let iso = iso else { return "-" }
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: iso) {
            let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
            return f.string(from: date)
        }
        return "-"
    }
    func currency(_ value: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? "$0.00"
    }
}

// MARK: - Typeahead models
private struct UserSearchResult: Identifiable, Decodable {
    let id: Int
    let username: String
    let displayName: String
}

// MARK: - Small helpers
private func formatTimestamp(_ timestamp: String) -> String {
    let isoFormatter = ISO8601DateFormatter()
    if let date = isoFormatter.date(from: timestamp) {
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    return timestamp
}

private struct ToastView: View {
    let message: String
    let tint: Color
    var systemImage: String = "info.circle.fill"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.headline)
                Text(message)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(tint.opacity(0.97))
            .foregroundStyle(.black)
            Divider().overlay(Color.black.opacity(0.15))
            Spacer(minLength: 0)
        }
        .ignoresSafeArea(edges: .top)                // ← full width, under notch
        .transition(.move(edge: .top).combined(with: .opacity))
        .zIndex(999)                                  // ← always visible above content
    }
}


private struct TypeaheadField: View {
    let placeholder: String
    @Binding var text: String
    let isSearching: Bool
    let iconSystemName: String
    let onChange: (String) -> Void
    let onSubmit: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconSystemName).foregroundColor(.gold.opacity(0.9))
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .foregroundColor(.white)
                .onChange(of: text, perform: onChange)
                .onSubmit(onSubmit)
            if isSearching { ProgressView().tint(.gold) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

private struct SuggestionsList: View {
    let items: [UserSearchResult]
    let onSelect: (UserSearchResult) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                Button { onSelect(item) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.displayName).foregroundColor(.white).font(.subheadline.bold()).lineLimit(1)
                            Text("@\(item.username)").foregroundColor(.white.opacity(0.7)).font(.caption).lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                if item.id != items.last?.id { Divider().background(Color.white.opacity(0.08)) }
            }
        }
        .background(Color.black.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 8)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .padding(.trailing, 0)
    }
}

private struct InlineBanner: View {
    let message: String; let tint: Color
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill").font(.subheadline.weight(.bold))
            Text(message).font(.subheadline.weight(.semibold)).lineLimit(2)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(tint.opacity(0.95), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .foregroundStyle(.black)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.black.opacity(0.15), lineWidth: 1))
        .shadow(radius: 10, y: 8)
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] { Array(Set(self)) }
}
