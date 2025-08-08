import SwiftUI
import UIKit

// MARK: - EventPromoterDashboardView (Modern Redesign + Revenue + Bulk Waitlist + Payment Search)
struct EventPromoterDashboardView: View {
    @AppStorage("selectedLanguage") var lang: String = "en"
    @EnvironmentObject var userSession: UserSession
    let event: Event
    @Environment(\.dismiss) var dismiss

    // Tabs
    enum Tab: Int, CaseIterable { case promoters, payments, waitlist }
    @State private var tab: Tab = .promoters

    // Data
    @State private var promoters: [PromoterEvent] = []
    @State private var buyersByPromoter: [Int: [ReferredBuyerDTO]] = [:]
    @State private var expandedPromoterId: Int? = nil

    @State private var dashboardTickets: [TicketDTO] = []
    @State private var waitlistEntries: [WaitlistEntry] = []

    // UI state
    @State private var isLoading = true
    @State private var isRefreshing = false
    @State private var isUpdatingStatus = false
    @State private var userIdInput = ""
    @State private var toast: (String, Color)? = nil

    // Payments
    enum PaymentFilter: String, CaseIterable, Identifiable { case all, paid, pending, card, zelle, pagomovil, cash
        var id: String { rawValue }
        var label: String { switch self { case .all: return "All"; case .paid: return "Paid"; case .pending: return "Pending"; case .card: return "Card"; case .zelle: return "Zelle"; case .pagomovil: return "Pago Móvil"; case .cash: return "Cash" } }
    }
    @State private var filterPayment: PaymentFilter = .all
    @State private var paymentQuery: String = ""

    // Waitlist bulk actions
    @State private var selectedWaitlist: Set<Int> = [] // entry.id
    @State private var isBulkWorking = false

    // MARK: - Derived overview metrics
    var totalPromoters: Int { promoters.count }
    var totalBuyers: Int { dashboardTickets.count }
    var paidCount: Int { dashboardTickets.filter { $0.paid }.count }
    var pendingCount: Int { dashboardTickets.filter { !$0.paid }.count }
    var waitlistPending: Int { waitlistEntries.filter { $0.status == "PENDING" }.count }

    // Revenue (requires `price: Double?` on TicketDTO)
    var totalRevenue: Double {
        dashboardTickets.filter { $0.paid }
            .reduce(0) { sum, ticket in
                sum + (priceForTicket(ticket, in: event) ?? 0)
            }
    }
    
    func priceForTicket(_ ticket: TicketDTO, in event: Event) -> Double? {
        event.ticketTiers.first(where: { $0.name == ticket.tierName })?.price
    }

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

                if let (msg, color) = toast { ToastView(message: msg, tint: color) }
            }
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
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
                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 42, height: 42)
                    .overlay(Image(systemName: "megaphone.fill").font(.title3).foregroundStyle(Color.gold))
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(lang == "es" ? "Administrar Evento" : "Manage Event")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
                        .padding(10)
                        .background(.white.opacity(0.06), in: Circle())
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
            Text(lang == "es" ? "Resumen" : "Overview")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCard(title: lang == "es" ? "Promotores" : "Promoters", value: "\(totalPromoters)", icon: "person.3.fill")
                StatCard(title: lang == "es" ? "Compradores" : "Buyers", value: "\(totalBuyers)", icon: "cart.fill")
                StatCard(title: lang == "es" ? "Pagados" : "Paid", value: "\(paidCount)", icon: "checkmark.seal.fill", accent: .green)
                StatCard(title: lang == "es" ? "Pendientes" : "Pending", value: "\(pendingCount)", icon: "hourglass", accent: .orange)
                StatCard(title: lang == "es" ? "Espera" : "Waitlist", value: "\(waitlistPending)", icon: "clock.badge.questionmark", accent: .yellow)
                StatCard(title: lang == "es" ? "Ingresos" : "Revenue", value: "\(totalRevenue)", icon: "dollarsign.circle.fill", accent: .gold)
            }
            .padding(.horizontal)
        }
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
                PromoterCard(pe: pe,
                             eventId: event.id,
                             expandedPromoterId: $expandedPromoterId,
                             buyersByPromoter: $buyersByPromoter,
                             onCopy: { text in showToast(text, .green) },
                             fetchBuyers: fetchBuyers)
            }

            // Add promoter
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.plus").foregroundStyle(Color.gold)
                    TextField(lang == "es" ? "Usuario para agregar" : "Username to add", text: $userIdInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding()
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)

                Button(action: assignPromoter) {
                    HStack { Spacer(); Text(lang == "es" ? "Asignar promotor" : "Assign promoter").bold(); Spacer() }
                }
                .padding(.vertical, 12)
                .background(Color.gold, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.black)
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.top, 6)
        }
    }

    var paymentsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Search + filters
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.gold)
                TextField(lang == "es" ? "Buscar por nombre, correo o método" : "Search name, email, or method", text: $paymentQuery)
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
                        TicketRow(ticket: ticket,
                                  isOwner: isEventOwner(),
                                  isManual: isManual(ticket: ticket),
                                  isUpdating: isUpdatingStatus,
                                  togglePaid: { togglePaidStatus(for: ticket) },
                                  event: event)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    var waitlistTab: some View {
        VStack(spacing: 12) {
            // Bulk actions header
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
                        WaitlistRowSelectable(entry: entry,
                                              isSelected: selectedWaitlist.contains(entry.id),
                                              toggle: { toggleWaitlistSelection(entry.id) },
                                              approve: { updateWaitlistStatus(entryId: entry.id, status: "APPROVED") },
                                              deny: { updateWaitlistStatus(entryId: entry.id, status: "DENIED") },
                                              statusText: statusText,
                                              colorForStatus: colorForStatus)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Filtering helpers (kept small to avoid type-checker pain)
private extension EventPromoterDashboardView {
    func ticketMatchesFilter(_ t: TicketDTO) -> Bool {
        switch filterPayment {
        case .all: return true
        case .paid: return t.paid
        case .pending: return !t.paid
        case .card:
            let m = t.paymentMethod.lowercased()
            return m == "card" || m == "stripe"
        case .zelle: return t.paymentMethod.lowercased() == "zelle"
        case .pagomovil: return t.paymentMethod.lowercased() == "pagomovil"
        case .cash: return t.paymentMethod.lowercased() == "cash"
        }
    }

    func ticketMatchesQuery(_ t: TicketDTO) -> Bool {
        let q = paymentQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return true }
        let name = "\(t.buyerFirstName) \(t.buyerLastName)".lowercased()
        let email = t.buyerEmail.lowercased()
        let method = t.paymentMethod.lowercased()
        return name.contains(q) || email.contains(q) || method.contains(q)
    }

    func filteredTickets() -> [TicketDTO] {
        dashboardTickets.filter { ticketMatchesFilter($0) && ticketMatchesQuery($0) }
    }
}

// MARK: - Subviews
private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    var accent: Color = .gold

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
    let title: String
    let icon: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
            }
            .foregroundStyle(isActive ? .black : .white.opacity(0.8))
            .padding(.vertical, 8).padding(.horizontal, 12)
            .background(isActive ? Color.gold : Color.white.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct LoadingRow: View { let text: String
    var body: some View { HStack { Spacer(); ProgressView(text).tint(.gold); Spacer() }.padding(.vertical, 24) }
}

private struct EmptyRow: View { let text: String
    var body: some View {
        Text(text).foregroundStyle(.white.opacity(0.6)).padding(.vertical, 28)
            .frame(maxWidth: .infinity)
            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
    }
}

private struct FilterChip: View {
    let title: String
    let isActive: Bool
    let onTap: () -> Void
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
    let ticket: TicketDTO
    let isOwner: Bool
    let isManual: Bool
    let isUpdating: Bool
    let togglePaid: () -> Void
    
    let event: Event

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(ticket.buyerFirstName) \(ticket.buyerLastName)").font(.headline).foregroundStyle(.white)
                Spacer()
                StatusBadge(paid: ticket.paid, isOwner: isOwner, isManual: isManual, isUpdating: isUpdating, toggle: togglePaid)
            }
            Text(ticket.buyerEmail).font(.footnote).foregroundStyle(.white.opacity(0.7))
            HStack(spacing: 6) {
                Text("Method:").foregroundStyle(.white.opacity(0.6)).font(.caption)
                Text(ticket.paymentMethod.capitalized).foregroundStyle(Color.gold).font(.caption)
                Spacer()
                if let price = priceForTicket(ticket, in: event) {
                    Text("\(price)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .padding(14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.06)))
    }
    
    func priceForTicket(_ ticket: TicketDTO, in event: Event) -> Double? {
        event.ticketTiers.first(where: { $0.name == ticket.tierName })?.price
    }
    
    func currency(_ value: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? "$0.00"
    }
    
}

private struct StatusBadge: View {
    let paid: Bool
    let isOwner: Bool
    let isManual: Bool
    let isUpdating: Bool
    let toggle: () -> Void
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
            }
            .buttonStyle(.plain)

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

    // MARK: - Small helpers
    private var promoterId: Int? { pe.promoter?.id }
    private var fullName: String { pe.promoter?.user.fullName ?? "Promoter" }
    private var username: String? { pe.promoter?.user.username }
    private var referralLink: String? {
        guard let u = username else { return nil }
        return "https://wkndevent.com/events/\(eventId)?ref=\(u)"
    }
    private var isExpanded: Bool { expandedPromoterId == promoterId }
    private var buyers: [ReferredBuyerDTO] {
        guard let id = promoterId else { return [] }
        return buyersByPromoter[id] ?? []
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

    // MARK: - Pieces
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text(fullName)
                    .font(.headline)
                    .foregroundStyle(.white)

                if let u = username {
                    Text("@\(u)")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                }

                HStack(spacing: 6) {
                    Image(systemName: "ticket.fill")
                    Text("\(pe.ticketsSold) sold")
                }
                .font(.caption)
                .foregroundStyle(Color.gold)
            }

            Spacer()

            Button(action: toggleExpanded) {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.white.opacity(0.06), in: Circle())
            }
        }
    }

    @ViewBuilder
    private var referralRow: some View {
        if let link = referralLink {
            HStack(spacing: 8) {
                Button {
                    UIPasteboard.general.string = link
                    onCopy(lang == "es" ? "¡Enlace copiado!" : "Link copied")
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                        Text(lang == "es" ? "Copiar enlace" : "Copy Referral Link")
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.gold)
                .buttonStyle(.plain)

                Text(link)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    @ViewBuilder
    private var buyersSection: some View {
        if isExpanded {
            VStack(alignment: .leading, spacing: 8) {
                Divider().overlay(Color.white.opacity(0.1))
                // If ReferredBuyerDTO already conforms to Identifiable, use `ForEach(buyers)`
                ForEach(buyers, id: \.id) { buyer in
                    BuyerRow(buyer: buyer)
                    Divider().overlay(Color.white.opacity(0.06))
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func toggleExpanded() {
        if isExpanded {
            expandedPromoterId = nil
        } else {
            fetchBuyers(pe) // sets expandedPromoterId when loaded
        }
    }
}

// Pull the row out to reduce body complexity further
private struct BuyerRow: View {
    let buyer: ReferredBuyerDTO
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(buyer.username)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text(buyer.email)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
            Text(formatTimestamp(buyer.timestamp))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.vertical, 4)
    }
}





// MARK: - Networking & Helpers (reusing your endpoints)
private extension EventPromoterDashboardView {
    func loadAll() {
        isLoading = true
        fetchPromoters()
        fetchDashboardTickets()
        fetchWaitlist()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { isLoading = false }
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

    func fetchPromoters() {
        guard let token = TokenManager.shared.getAccessToken() else { return }
        var request = URLRequest(url: URL(string: "https://backendevent-etce.onrender.com/api/promoters/event/\(event.id)/dashboard")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data else { return }
            if let decoded = try? JSONDecoder().decode([PromoterEvent].self, from: data) {
                DispatchQueue.main.async { self.promoters = decoded }
            }
        }.resume()
    }

    func fetchWaitlist() {
        guard let token = TokenManager.shared.getAccessToken(), let url = URL(string: "https://backendevent-etce.onrender.com/events/\(event.id)/waitlist") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data else { return }
            if let decoded = try? JSONDecoder().decode([WaitlistEntry].self, from: data) {
                DispatchQueue.main.async { self.waitlistEntries = decoded }
            }
        }.resume()
    }

    func fetchDashboardTickets() {
        guard let token = TokenManager.shared.getAccessToken(), let url = URL(string: "https://backendevent-etce.onrender.com/api/tickets/event/\(event.id)/dashboard") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data else { return }
            if let decoded = try? JSONDecoder().decode([TicketDTO].self, from: data) {
                DispatchQueue.main.async { self.dashboardTickets = decoded }
            }
        }.resume()
    }

    func togglePaidStatus(for ticket: TicketDTO) {
        guard let url = URL(string: "https://backendevent-etce.onrender.com/api/tickets/\(ticket.id)/toggle-paid") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        guard let token = TokenManager.shared.getAccessToken() else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        isUpdatingStatus = true
        URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async { self.isUpdatingStatus = false }
            guard let data = data, let result = try? JSONDecoder().decode([String: Bool].self, from: data), let newPaid = result["paid"] else { return }
            DispatchQueue.main.async {
                if let i = dashboardTickets.firstIndex(where: { $0.id == ticket.id }) { dashboardTickets[i].paid = newPaid }
            }
        }.resume()
    }

    func fetchBuyers(for promoter: PromoterEvent) {
        guard let promoterId = promoter.promoter?.id else { return }
        guard let token = TokenManager.shared.getAccessToken() else { return }
        let url = URL(string: "https://backendevent-etce.onrender.com/api/promoters/event/\(event.id)/promoter/\(promoterId)/buyers")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data else { return }
            if let decoded = try? JSONDecoder().decode([ReferredBuyerDTO].self, from: data) {
                DispatchQueue.main.async {
                    buyersByPromoter[promoterId] = decoded
                    expandedPromoterId = promoterId
                }
            }
        }.resume()
    }

    func assignPromoter() {
        guard let token = TokenManager.shared.getAccessToken(), let url = URL(string: "https://backendevent-etce.onrender.com/api/promoters/\(event.id)/assign"), !userIdInput.isEmpty else { showToast("Invalid username", .orange); return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["username": userIdInput]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                DispatchQueue.main.async {
                    showToast("✅ Promoter assigned!", .green)
                    userIdInput = ""
                    createPromoterGroupChat()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { fetchPromoters() }
                }
            } else { DispatchQueue.main.async { showToast("❌ Failed to assign promoter.", .red) } }
        }.resume()
    }

    func isManual(ticket: TicketDTO) -> Bool { ["zelle", "pagomovil", "cash"].contains(ticket.paymentMethod.lowercased()) }
    func isEventOwner() -> Bool { guard let ownerId = event.createdBy?.id else { return false }; return userSession.userId == ownerId }

    func createPromoterGroupChat() {
        guard let token = TokenManager.shared.getAccessToken(), let url = URL(string: "https://backendevent-etce.onrender.com/chat/promoter-group/\(event.id)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }

    func statusText(_ status: String) -> String {
        switch status { case "APPROVED": return lang == "es" ? "Aprobado" : "Approved"; case "DENIED": return lang == "es" ? "Denegado" : "Denied"; default: return lang == "es" ? "Pendiente" : "Pending" }
    }

    func colorForStatus(_ status: String) -> Color { switch status { case "APPROVED": return .green; case "DENIED": return .red; default: return .orange } }

    func updateWaitlistStatus(entryId: Int, status: String) {
        guard let token = TokenManager.shared.getAccessToken(), let url = URL(string: "https://backendevent-etce.onrender.com/events/\(event.id)/waitlist/\(entryId)/status?status=\(status)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request) { _, _, _ in fetchWaitlist() }.resume()
    }

    func selectAllWaitlist() { selectedWaitlist = Set(waitlistEntries.filter{ $0.status == "PENDING" }.map{ $0.id }) }
    func toggleWaitlistSelection(_ id: Int) { if selectedWaitlist.contains(id) { selectedWaitlist.remove(id) } else { selectedWaitlist.insert(id) } }

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
            showToast(status == "APPROVED" ? (lang == "es" ? "Aprobados" : "Approved") : (lang == "es" ? "Denegados" : "Denied"), .green)
        }
    }

    func showToast(_ text: String, _ color: Color) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { toast = (text, color) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { withAnimation { toast = nil } }
    }

    func eventDateString(_ iso: String?) -> String {
        guard let iso = iso else { return "-" }
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: iso) {
            let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f.string(from: date)
        }
        return "-"
    }

    func currency(_ value: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? "$0.00"
    }
}

// MARK: - Small helpers
private func formatTimestamp(_ timestamp: String) -> String {
    let isoFormatter = ISO8601DateFormatter()
    if let date = isoFormatter.date(from: timestamp) {
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short; return formatter.string(from: date)
    }
    return timestamp
}

// MARK: - Toast
private struct ToastView: View {
    let message: String
    let tint: Color
    var body: some View {
        VStack { Spacer(minLength: 0) }
            .overlay(alignment: .top) {
                Text(message)
                    .font(.subheadline.weight(.semibold))
                    .padding(.vertical, 10).padding(.horizontal, 16)
                    .background(tint.opacity(0.95), in: Capsule())
                    .foregroundStyle(.black)
                    .padding(.top, 10)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}
