import SwiftUI

struct EventPromoterDashboardView: View {
    @AppStorage("selectedLanguage") var lang: String = "en"
    @EnvironmentObject var userSession: UserSession
    let event: Event
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedTab = 0 // 0 = Promoters, 1 = Zelle Payments


    @State private var promoters: [PromoterEvent] = []
    @State private var buyersByPromoter: [Int: [ReferredBuyerDTO]] = [:]
    @State private var expandedPromoterId: Int? = nil

    @State private var userIdInput = ""
    @State private var message = ""
    @State private var isLoading = true
    @State private var copiedMessage: String?
    @State private var dashboardTickets: [TicketDTO] = []
    
    @State private var isUpdatingStatus = false


    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    // Header
                    HStack {
                        Button(lang == "es" ? "Cerrar" : "Close") {
                            dismiss()
                        }
                        .foregroundColor(.white)
                        .font(.headline)
                        
                        Spacer()
                        
                        HStack(spacing: 0) {
                            Button {
                                selectedTab = 0
                            } label: {
                                Text(lang == "es" ? "Promotores" : "Promoters")
                                    .font(.headline)
                                    .foregroundColor(selectedTab == 0 ? .white : .gray)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                    .background(selectedTab == 0 ? Color.gold.opacity(0.1) : .clear)
                                    .cornerRadius(10)
                            }
                            
                            Button {
                                selectedTab = 1
                            } label: {
                                Text(lang == "es" ? "Pagos" : "Payments")
                                    .font(.headline)
                                    .foregroundColor(selectedTab == 1 ? .white : .gray)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                    .background(selectedTab == 1 ? Color.gold.opacity(0.1) : .clear)
                                    .cornerRadius(10)
                            }
                        }
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(12)
                        
                        
                        Spacer().frame(width: 64)
                    }
                    .padding(.horizontal)
                    .padding(.top, 16)
                    
                    if selectedTab == 0 {
                        ScrollView {
                            VStack(spacing: 24) {
                                if isLoading {
                                    ProgressView(lang == "es" ? "Cargando..." : "Loading...")
                                        .tint(.gold)
                                        .padding(.top, 40)
                                } else if promoters.isEmpty {
                                    
                                    Text(
                                        lang == "es"
                                        ? "No hay promotores asignados a este evento."
                                        : "No promoters assigned to this event."
                                    )
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                                    .padding(.top, 60)
                                } else {
                                    VStack(spacing: 16) {
                                        ForEach(promoters) { pe in
                                            VStack(alignment: .leading, spacing: 8) {
                                                Text(pe.promoter?.user.fullName ?? (lang == "es" ? "Promotor" : "Promoter"))
                                                    .font(.headline)
                                                    .foregroundColor(.white)
                                                
                                                Text(
                                                    lang == "es"
                                                    ? "Usuario: \(pe.promoter?.user.username ?? "-")"
                                                    : "Username: \(pe.promoter?.user.username ?? "-")"
                                                )
                                                .font(.subheadline)
                                                .foregroundColor(.gray)
                                                
                                                
                                                Text(
                                                    lang == "es"
                                                    ? "Entradas Vendidas: \(pe.ticketsSold)"
                                                    : "Tickets Sold: \(pe.ticketsSold)"
                                                )
                                                .font(.footnote)
                                                .foregroundColor(.gold)
                                                
                                                if let username = pe.promoter?.user.username {
                                                    let link = "http://localhost:3000/events/\(event.id)?ref=\(pe.promoter?.user.username ?? "")"
                                                    
                                                    Button {
                                                        UIPasteboard.general.string = link
                                                        copiedMessage = lang == "es" ? "¡Enlace copiado!" : "Link copied!"
                                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                                            copiedMessage = nil
                                                        }
                                                    } label: {
                                                        HStack(spacing: 6) {
                                                            Image(systemName: "link")
                                                                .foregroundColor(.gold)
                                                            Text(lang == "es" ? "Copiar Enlace de Referencia" : "Copy Referral Link")
                                                                .foregroundColor(.gold)
                                                                .font(.caption)
                                                        }
                                                    }
                                                    
                                                    Text(link)
                                                        .font(.caption2)
                                                        .foregroundColor(.gray)
                                                        .lineLimit(1)
                                                        .truncationMode(.middle)
                                                }
                                                
                                                if copiedMessage != nil {
                                                    Text(copiedMessage!)
                                                        .font(.caption)
                                                        .foregroundColor(.green)
                                                }
                                                
                                                Button(action: {
                                                    if expandedPromoterId == pe.promoter?.id {
                                                        expandedPromoterId = nil
                                                    } else {
                                                        fetchBuyers(for: pe)
                                                    }
                                                }) {
                                                    Text(
                                                        expandedPromoterId == pe.promoter?.id
                                                        ? (lang == "es" ? "Ocultar Compradores" : "Hide Buyers")
                                                        : (lang == "es" ? "Ver Compradores" : "View Buyers")
                                                    )
                                                    .font(.caption)
                                                    .foregroundColor(.gold)
                                                }
                                                
                                                if expandedPromoterId == pe.promoter?.id,
                                                   let buyers = buyersByPromoter[pe.promoter!.id] {
                                                    VStack(alignment: .leading, spacing: 8) {
                                                        ForEach(buyers) { buyer in
                                                            VStack(alignment: .leading, spacing: 2) {
                                                                Text(buyer.username)
                                                                    .font(.subheadline.bold())
                                                                    .foregroundColor(.white)
                                                                Text(buyer.email)
                                                                    .font(.footnote)
                                                                    .foregroundColor(.gray)
                                                                Text(formatTimestamp(buyer.timestamp))
                                                                    .font(.caption)
                                                                    .foregroundColor(.gray)
                                                            }
                                                            .padding(.vertical, 6)
                                                            Divider().background(Color.white.opacity(0.1))
                                                        }
                                                    }
                                                    .padding(.top, 8)
                                                }
                                            }
                                            .padding()
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(Color.white.opacity(0.05))
                                            .cornerRadius(12)
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                                
                                // Add promoter
                                VStack(spacing: 12) {
                                    TextField(
                                        lang == "es" ? "Ingresa Usuario para Agregar" : "Enter Username to Add",
                                        text: $userIdInput
                                    )
                                    .keyboardType(.numberPad)
                                    .padding()
                                    .background(Color.white.opacity(0.08))
                                    .cornerRadius(10)
                                    .foregroundColor(.white)
                                    .padding(.horizontal)
                                    
                                    
                                    Button(lang == "es" ? "Asignar Promotor" : "Assign Promoter") {                                    assignPromoter()
                                    }
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color.gold)
                                    .foregroundColor(.black)
                                    .cornerRadius(12)
                                    .padding(.horizontal)
                                    
                                    if !message.isEmpty {
                                        Text(message)
                                            .foregroundColor(.white)
                                            .font(.footnote)
                                            .padding(.horizontal)
                                            .multilineTextAlignment(.center)
                                    }
                                }
                                .padding(.bottom, 40)
                            }
                            .padding(.top)
                        }
                    } else{
                        ScrollView {
                            VStack(spacing: 24) {
                                
                                Spacer()
                                
                                if dashboardTickets.isEmpty {
                                    Text(lang == "es" ? "Aún no hay compradores." : "No buyers yet.")
                                        .foregroundColor(.gray)
                                } else {
                                    ForEach(dashboardTickets) { ticket in
                                        VStack(alignment: .leading, spacing: 6) {
                                            // 👤 Buyer Info
                                            Text("\(ticket.buyerFirstName) \(ticket.buyerLastName)")
                                                .font(.headline)
                                                .foregroundColor(.white)
                                            Text(ticket.buyerEmail)
                                                .font(.subheadline)
                                                .foregroundColor(.gray)

                                            // 💳 Payment + Status Row
                                            HStack {
                                                Text(lang == "es" ? "Método:" : "Method:")
                                                    .foregroundColor(.gray)
                                                Text(ticket.paymentMethod.capitalized)
                                                    .foregroundColor(.gold)

                                                Spacer()
                                                
                                                if isEventOwner() && isManual(ticket: ticket) {
                                                    Menu {
                                                        Button(lang == "es" ? "Pendiente" : "Pending") {
                                                            if ticket.paid {
                                                                togglePaidStatus(for: ticket)
                                                            }
                                                        }
                                                        Button(lang == "es" ? "Pagado" : "Paid") {
                                                            if !ticket.paid {
                                                                togglePaidStatus(for: ticket)
                                                            }
                                                        }
                                                    } label: {
                                                        HStack(spacing: 6) {
                                                            if isUpdatingStatus {
                                                                ProgressView()
                                                                    .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                                                    .scaleEffect(0.7)
                                                            } else {
                                                                Text(ticket.paid
                                                                    ? (lang == "es" ? "Pagado" : "Paid")
                                                                    : (lang == "es" ? "Pendiente" : "Pending"))
                                                                    .foregroundColor(.black)
                                                                    .font(.caption)
                                                                Image(systemName: "chevron.down")
                                                                    .font(.system(size: 10, weight: .medium))
                                                                    .foregroundColor(.black)
                                                            }
                                                        }
                                                        .padding(.horizontal, 10)
                                                        .padding(.vertical, 6)
                                                        .background(ticket.paid ? Color.green : Color.orange)
                                                        .cornerRadius(8)
                                                    }
                                                    .disabled(isUpdatingStatus)
                                                } else {
                                                    Text(ticket.paid
                                                        ? (lang == "es" ? "Pagado" : "Paid")
                                                        : (lang == "es" ? "Pendiente" : "Pending"))
                                                        .foregroundColor(ticket.paid ? .green : .orange)
                                                        .font(.caption)
                                                }
                                            }
                                        }
                                        .padding()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.white.opacity(0.05))
                                        .cornerRadius(12)
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 40)
                        }
                    }
                }
            }
            .onAppear {
                fetchPromoters()
                fetchDashboardTickets()
            }
        }
    }

    func fetchPromoters() {
        guard let token = TokenManager.shared.getAccessToken() else { return }

        var request = URLRequest(url: URL(string: "https://backendevent-etce.onrender.com/api/promoters/event/\(event.id)/dashboard")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data else {
                DispatchQueue.main.async { isLoading = false }
                return
            }

            do {
                let decoded = try JSONDecoder().decode([PromoterEvent].self, from: data)
                DispatchQueue.main.async {
                    self.promoters = decoded
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.promoters = []
                }
            }
        }.resume()
    }
    
    func fetchDashboardTickets() {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/api/tickets/event/\(event.id)/dashboard") else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data else {
                print("❌ No dashboard ticket data: \(error?.localizedDescription ?? "unknown error")")
                return
            }

            do {
                let decoded = try JSONDecoder().decode([TicketDTO].self, from: data)
                DispatchQueue.main.async {
                    self.dashboardTickets = decoded
                }
            } catch {
                print("❌ Failed to decode dashboard tickets: \(error)")
            }
        }.resume()
    }

    
    func togglePaidStatus(for ticket: TicketDTO) {
        guard let url = URL(string: "https://backendevent-etce.onrender.com/api/tickets/\(ticket.id)/toggle-paid") else { return }

        isUpdatingStatus = true

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        guard let token = TokenManager.shared.getAccessToken() else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, response, error in
            isUpdatingStatus = false

            guard let data = data else { return }
            if let result = try? JSONDecoder().decode([String: Bool].self, from: data),
               let newPaid = result["paid"] {
                DispatchQueue.main.async {
                    if let index = dashboardTickets.firstIndex(where: { $0.id == ticket.id }) {
                        dashboardTickets[index].paid = newPaid
                    }
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

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data else { return }

            do {
                let decoded = try JSONDecoder().decode([ReferredBuyerDTO].self, from: data)
                DispatchQueue.main.async {
                    buyersByPromoter[promoterId] = decoded
                    expandedPromoterId = promoterId
                }
            } catch {
                print("❌ Failed to decode buyers: \(error.localizedDescription)")
            }
        }.resume()
    }

    func assignPromoter() {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/api/promoters/\(event.id)/assign"),
              !userIdInput.isEmpty else {
            message = "Invalid username"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["username": userIdInput]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                DispatchQueue.main.async {
                    message = "✅ Promoter assigned!"
                    userIdInput = ""
                    createPromoterGroupChat() // 👈 Create chat right after assigning
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        fetchPromoters()
                    }
                }
            } else {
                DispatchQueue.main.async {
                    message = "❌ Failed to assign promoter."
                }
            }
        }.resume()
    }
    
    func isManual(ticket: TicketDTO) -> Bool {
        ["zelle", "pagomovil", "cash"].contains(ticket.paymentMethod.lowercased())
    }

    func isEventOwner() -> Bool {
        guard let ownerId = event.createdBy?.id else { return false }
        return userSession.userId == ownerId
    }



    func createPromoterGroupChat() {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/chat/promoter-group/\(event.id)") else {
            print("❌ Invalid promoter group chat URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data = data, let str = String(data: data, encoding: .utf8) {
                print("✅ Promoter group chat created or fetched:\n\(str)")
            } else {
                print("❌ Failed to create promoter group chat")
            }
        }.resume()
    }


    func formatTimestamp(_ timestamp: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: timestamp) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        return timestamp
    }
}
