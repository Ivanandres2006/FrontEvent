import SwiftUI
import Combine
import AVFoundation

struct TicketValidationViewForScanner: View {
    @AppStorage("selectedLanguage") var lang: String = "en"

    // State
    @State private var attendees: [TicketDTO] = []
    @State private var isLoadingAttendees = false
    let eventId: Int

    // Scanner state
    @State private var scannedCode: String?
    @State private var isLoadingScan = false
    @State private var shouldRestartScanner = false   // now used with .id() instead of Notification

    // Result banner
    @State private var resultColor: Color = .gray
    @State private var resultText: String = "Scan a QR code"

    // Attendees
    @State private var searchText = ""
    @State private var attendeeFilter: AttendeeFilter = .all

    // Optimistic overrides for "used"
    @State private var usedOverride: [Int: Bool] = [:]

    // Haptics
    private let successFeedback = UINotificationFeedbackGenerator()
    private let errorFeedback = UINotificationFeedbackGenerator()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    scannerCard
                    resultBanner
                    attendeeTools
                    attendeeList
                }
                .padding()
            }
            .background(
                LinearGradient(
                    colors: [Color.black, Color(red: 0.07, green: 0.09, blue: 0.18)],
                    startPoint: .top,
                    endPoint: .bottom
                ).ignoresSafeArea()
            )
            .navigationTitle(titleText("Scanner"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { fetchAttendees() } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(isLoadingAttendees)
                }
            }
            .refreshable { fetchAttendees() }
            .onAppear { fetchAttendees() }
        }
    }

    // MARK: - Components

    private var headerCard: some View {
        let total = attendees.count
        let usedCount = attendees.filter { usedOverride[$0.id] ?? $0.used }.count
        let unusedCount = total - usedCount

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("WKND").font(.title2.bold()).foregroundColor(Color.gold)
                Spacer()
                HStack(spacing: 8) {
                    pill(label: titleText("Total"), value: "\(total)", color: .white.opacity(0.85))
                    pill(label: titleText("Used"), value: "\(usedCount)", color: .green.opacity(0.9))
                    pill(label: titleText("Unused"), value: "\(unusedCount)", color: .yellow.opacity(0.9))
                }
            }
            Text(titleText("Validate tickets for your event"))
                .font(.callout)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func pill(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption2).opacity(0.8)
            Text(value).font(.caption.bold())
        }
        .padding(.vertical, 6).padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 20).fill(color.opacity(0.15)))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(color.opacity(0.4), lineWidth: 1))
        .foregroundColor(.white)
    }

    private var scannerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "qrcode.viewfinder")
                Text(titleText("Scan Ticket")).font(.headline)
                Spacer()
                Button { shouldRestartScanner.toggle() } label: {
                    Label(titleText("Restart"), systemImage: "arrow.counterclockwise").labelStyle(.iconOnly)
                }.tint(.white.opacity(0.8))
            }
            .foregroundColor(.white)

            // NOTE: restart by recreating the controller with a new id
            QRScannerView { code in handleScan(code) }
                .id(shouldRestartScanner) // <— replaces Notification-based restart
                .frame(height: 320)
                .background(Color.black.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 1))

            if let scanned = scannedCode {
                Text("\(titleText("Last scan")): \(scanned)")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private var resultBanner: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle().fill(resultColor).frame(width: 10, height: 10)
            Text(resultText).font(.subheadline.weight(.semibold)).foregroundColor(.white)
            Spacer()
            if isLoadingScan { ProgressView().progressViewStyle(.circular) }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private var attendeeTools: some View {
        VStack(spacing: 10) {
            HStack {
                ForEach(AttendeeFilter.allCases, id: \.self) { f in
                    Button { attendeeFilter = f } label: {
                        Text(titleText(f.title(lang))).font(.caption.bold())
                            .padding(.vertical, 6).padding(.horizontal, 10)
                            .background(RoundedRectangle(cornerRadius: 20).fill(attendeeFilter == f ? Color.white.opacity(0.18) : Color.white.opacity(0.06)))
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(attendeeFilter == f ? 0.35 : 0.15), lineWidth: 1))
                    }
                    .foregroundColor(.white)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                TextField(titleText("Search by name or email"), text: $searchText)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
            .foregroundColor(.white)
        }
    }

    private var attendeeList: some View {
        let filtered = attendees
            .filter { t in
                let usedNow = usedOverride[t.id] ?? t.used
                switch attendeeFilter {
                case .all: return true
                case .used: return usedNow
                case .unused: return !usedNow
                }
            }
            .filter { t in
                let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                if q.isEmpty { return true }
                let name = "\(t.buyerFirstName) \(t.buyerLastName)"
                let email = t.buyerEmail
                let tier = t.tierName ?? ""
                return name.localizedCaseInsensitiveContains(q)
                    || (email?.localizedCaseInsensitiveContains(q) ?? false)
                    || (tier.localizedCaseInsensitiveContains(q) ?? false)
            }

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(titleText("Attendees")).font(.headline).foregroundColor(.white)
                Spacer()
                if isLoadingAttendees { ProgressView() }
            }

            if filtered.isEmpty {
                Text(titleText("No attendees found"))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.vertical, 12)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filtered) { item in
                        let isUsedNow = usedOverride[item.id] ?? item.used

                        AttendeeRow(
                            t: item,
                            isUsedNow: isUsedNow,
                            markUsed: {
                                guard !isUsedNow else { return }
                                // optimistic
                                usedOverride[item.id] = true
                                markTicketAsUsed(ticketId: item.id, tier: item.tierName ?? "-") { ok in
                                    if !ok { usedOverride[item.id] = nil } // revert to server state
                                }
                            },
                            markUnused: {
                                guard isUsedNow else { return }
                                usedOverride[item.id] = false
                                markTicketAsUnused(ticketId: item.id) { ok in
                                    if !ok { usedOverride[item.id] = nil }
                                }
                            }
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: - Scan flow

    private func parseTicketId(from code: String) -> Int? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = Int(trimmed) { return id }      // plain "123"
        let parts = trimmed.split(separator: ":")
        if parts.count >= 2, parts[0].uppercased() == "TICKET",
           let id = Int(parts[1]) { return id }     // "TICKET:123:email"
        return nil
    }

    private func handleScan(_ code: String) {
        scannedCode = code
        isLoadingScan = true

        guard let ticketId = parseTicketId(from: code) else {
            errorFeedback.notificationOccurred(.error)
            resultColor = .red
            resultText = lang == "es" ? "QR inválido" : "Invalid QR"
            autoResetBanner()
            return
        }
        validateTicket(ticketId)
    }

    private func validateTicket(_ ticketId: Int) {
        guard
            let url = URL(string: "https://backendevent-etce.onrender.com/api/tickets/validate/\(ticketId)"),
            let token = TokenManager.shared.getAccessToken()
        else {
            errorFeedback.notificationOccurred(.error)
            resultColor = .red
            resultText = lang == "es" ? "Sesión inválida" : "Invalid session"
            autoResetBanner()
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, response, _ in
            DispatchQueue.main.async {
                self.isLoadingScan = false

                guard let http = response as? HTTPURLResponse else {
                    self.errorFeedback.notificationOccurred(.error)
                    self.resultColor = .red
                    self.resultText = "Network error"
                    self.autoResetBanner()
                    return
                }

                switch http.statusCode {
                case 200:
                    guard let data = data,
                          let json = try? JSONDecoder().decode(ValidatedTicket.self, from: data) else {
                        self.errorFeedback.notificationOccurred(.error)
                        self.resultColor = .red
                        self.resultText = "Bad response"
                        self.autoResetBanner()
                        return
                    }

                    if json.used {
                        self.errorFeedback.notificationOccurred(.warning)
                        self.resultColor = .red
                        self.resultText = self.lang == "es"
                            ? "❌ Ya utilizada\nNivel: \(json.tier)"
                            : "❌ Already used\nTier: \(json.tier)"
                        self.autoResetBanner()
                    } else {
                        // optimistic-used
                        self.usedOverride[json.ticketId] = true
                        self.markTicketAsUsed(ticketId: json.ticketId, tier: json.tier) { ok in
                            if !ok { self.usedOverride[json.ticketId] = nil }
                        }
                    }

                case 403:
                    self.errorFeedback.notificationOccurred(.error)
                    self.resultColor = .red
                    self.resultText = self.lang == "es"
                        ? "🚫 No autorizado (no eres dueño del evento)"
                        : "🚫 Unauthorized (not event owner)"
                    self.autoResetBanner()

                case 404:
                    self.errorFeedback.notificationOccurred(.error)
                    self.resultColor = .red
                    self.resultText = self.lang == "es" ? "🚫 Ticket no encontrado" : "🚫 Ticket not found"
                    self.autoResetBanner()

                case 409:
                    self.errorFeedback.notificationOccurred(.error)
                    self.resultColor = .red
                    self.resultText = self.lang == "es" ? "🚫 Ticket impago" : "🚫 Ticket unpaid"
                    self.autoResetBanner()

                default:
                    self.errorFeedback.notificationOccurred(.error)
                    self.resultColor = .red
                    self.resultText = "Server error (\(http.statusCode))"
                    self.autoResetBanner()
                }
            }
        }.resume()
    }

    // MARK: - Network (relaxed success check)

    private func markTicketAsUsed(ticketId: Int, tier: String, overrideSuccessText: String? = nil, onDone: ((Bool) -> Void)? = nil) {
        guard
            let url = URL(string: "https://backendevent-etce.onrender.com/api/tickets/validate/\(ticketId)/mark-used"),
            let token = TokenManager.shared.getAccessToken()
        else {
            onDone?(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { _, response, _ in
            DispatchQueue.main.async {
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    successFeedback.notificationOccurred(.success)
                    resultColor = .green
                    let line2 = overrideSuccessText ?? tier
                    resultText = lang == "es" ? "✅ Entrada escaneada\n\(line2)" : "✅ Ticket scanned\n\(line2)"
                    onDone?(true)
                } else if let http = response as? HTTPURLResponse, http.statusCode == 400 {
                    errorFeedback.notificationOccurred(.warning)
                    resultColor = .red
                    resultText = lang == "es" ? "❌ Ya marcada como usada" : "❌ Already marked as used"
                    onDone?(false)
                } else {
                    errorFeedback.notificationOccurred(.error)
                    resultColor = .red
                    resultText = lang == "es" ? "❌ No se pudo marcar como utilizada" : "❌ Failed to mark as used"
                    onDone?(false)
                }
                // light auto-sync
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { fetchAttendees() }
                autoResetBanner()
            }
        }.resume()
    }

    private func markTicketAsUnused(ticketId: Int, overrideSuccessText: String? = nil, onDone: ((Bool) -> Void)? = nil) {
        guard
            let url = URL(string: "https://backendevent-etce.onrender.com/api/tickets/validate/\(ticketId)/mark-unused"),
            let token = TokenManager.shared.getAccessToken()
        else {
            onDone?(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { _, response, _ in
            DispatchQueue.main.async {
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    successFeedback.notificationOccurred(.success)
                    resultColor = .green
                    resultText = lang == "es" ? "🔄 Marcado como SIN USAR" : "🔄 Marked as UNUSED"
                    onDone?(true)
                } else {
                    errorFeedback.notificationOccurred(.error)
                    resultColor = .red
                    resultText = lang == "es" ? "❌ No se pudo marcar como sin usar" : "❌ Failed to mark unused"
                    onDone?(false)
                }
                // light auto-sync
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { fetchAttendees() }
                autoResetBanner()
            }
        }.resume()
    }

    private func autoResetBanner() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            resultText = titleText("Scan a QR code")
            resultColor = .gray
            shouldRestartScanner.toggle()
        }
    }
    
    // Put these helpers near your view (file-private or private)
    private func normalizedName(_ t: TicketDTO) -> String {
        let first = (t.buyerFirstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last  = (t.buyerLastName  ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // Accent-insensitive, case-insensitive, space-trimmed
        return (first + " " + last)
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
    }

    private func attendeeSort(usedOverride: [Int: Bool]) -> (TicketDTO, TicketDTO) -> Bool {
        return { a, b in
            // If TicketDTO.used is optional in your model, the `?? false` covers it.
            let au: Bool = usedOverride[a.id] ?? (a.used ?? false)
            let bu: Bool = usedOverride[b.id] ?? (b.used ?? false)

            // Unused first → au=false before true. Use tuple keys for stable, cheap sorting.
            let keyA = (au ? 1 : 0, normalizedName(a))
            let keyB = (bu ? 1 : 0, normalizedName(b))
            return keyA < keyB
        }
    }


    // MARK: - Fetch attendees

    private func fetchAttendees() {
        guard let token = TokenManager.shared.getAccessToken() else {
            resultText = lang == "es" ? "Sesión inválida" : "Invalid session"
            resultColor = .red
            return
        }
        guard let url = URL(string: "https://backendevent-etce.onrender.com/api/tickets/event/\(eventId)/dashboard") else { return }

        isLoadingAttendees = true
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                isLoadingAttendees = false

                guard err == nil,
                      let http = resp as? HTTPURLResponse, http.statusCode == 200,
                      let data = data
                else { return }

                do {
                    var items = try JSONDecoder().decode([TicketDTO].self, from: data)
                    items.sort(by: attendeeSort(usedOverride: usedOverride))
                    attendees = items
                } catch {
                    // optional: log decode error
                    // print("Decode error:", error)
                }
            }
        }.resume()
    }

    // MARK: - Helpers

    private func titleText(_ en: String) -> String {
        if lang == "es" {
            switch en {
            case "Scanner": return "Escáner"
            case "Validate tickets for your event": return "Valida entradas para tu evento"
            case "Total": return "Total"
            case "Used": return "Usadas"
            case "Unused": return "Sin usar"
            case "Scan Ticket": return "Escanear entrada"
            case "Restart": return "Reiniciar"
            case "Last scan": return "Último escaneo"
            case "Scan a QR code": return "Escanea un código QR"
            case "Attendees": return "Asistentes"
            case "No attendees found": return "No se encontraron asistentes"
            case "Search by name or email": return "Buscar por nombre o email"
            default: return en
            }
        }
        return en
    }

    enum AttendeeFilter: CaseIterable {
        case all, used, unused
        func title(_ lang: String) -> String {
            switch (self, lang) {
            case (.all, "es"): return "Todos"
            case (.used, "es"): return "Usadas"
            case (.unused, "es"): return "Sin usar"
            case (.all, _): return "All"
            case (.used, _): return "Used"
            case (.unused, _): return "Unused"
            }
        }
    }
}

// MARK: - Row (stateless)
private struct AttendeeRow: View {
    let t: TicketDTO
    let isUsedNow: Bool
    let markUsed: () -> Void
    let markUnused: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text("\(t.buyerFirstName) \(t.buyerLastName)")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()

                // Paid/Pending pill
                Text(t.paid ? "Paid" : "Pending")
                    .font(.caption.weight(.semibold))
                    .padding(.vertical, 4).padding(.horizontal, 8)
                    .background(t.paid ? Color.green : Color.orange, in: Capsule())
                    .foregroundStyle(.black)

                // Used/Unused capsule menu (stateless, renders from isUsedNow)
                Menu {
                    Button {
                        markUnused()
                    } label: {
                        Label("Unused", systemImage: "circle")
                    }
                    .disabled(!isUsedNow)

                    Button {
                        markUsed()
                    } label: {
                        Label("Used", systemImage: "checkmark.circle.fill")
                    }
                    .disabled(isUsedNow)
                } label: {
                    Text(isUsedNow ? "Used" : "Unused")
                        .font(.caption.weight(.semibold))
                        .padding(.vertical, 4).padding(.horizontal, 8)
                        .background(isUsedNow ? Color.green : Color.yellow, in: Capsule())
                        .foregroundStyle(.black)
                }
            }

            Text(t.buyerEmail ?? "-")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))

            HStack(spacing: 8) {
                Label(t.tierName ?? "-", systemImage: "ticket.fill")
                    .font(.caption)
                    .foregroundStyle(Color.gold)
                Text("x\(t.quantity)").font(.caption).foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text((t.paymentMethod ?? "—").replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(12)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.06)))
    }
}

// MARK: - API DTOs
struct ValidatedTicket: Decodable {
    let ticketId: Int
    let event: String
    let tier: String
    let quantity: Int
    let status: String
    let email: String
    let used: Bool
}

struct MarkUsedResponse: Decodable { let status: String }
