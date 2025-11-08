//
//  PromoterSelfView.swift
//  WKND
//

import SwiftUI
import UIKit

struct PromoterSelfView: View {
    @AppStorage("selectedLanguage") var lang: String = "en"
    @Environment(\.dismiss) private var dismiss
    let eventId: Int

    // Data
    @State private var me: PromoterMeDTO? = nil
    @State private var promoterRow: PromoterEventView? = nil
    @State private var buyers: [ReferredBuyerDTO] = []

    // UI
    @State private var isLoading = true
    @State private var isPromoterForEvent = false
    @State private var errorText: String? = nil
    @State private var showShareSheet = false
    @State private var shareURL: URL? = nil
    @State private var showScanner = false

    private var referralCode: String { (me?.referralCode) ?? (me?.user.username) ?? "" }
    private var ticketsSold: Int { promoterRow?.ticketsSold ?? 0 }
    
    private var referralLink: String {
        guard !referralCode.isEmpty else { return "" }
        return "https://wkndevent.com/#/events/\(eventId)?ref=\(referralCode)"
    }
    
    private var grossFromBuyers: Double {
        buyers.reduce(0) { $0 + Double($1.quantity ?? 1) * ($1.unitPrice ?? 0) }
    }
    private var grossText: String { String(format: "$%.2f", grossFromBuyers) }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        HeaderBar(
                            title: lang == "es" ? "Panel de Promotor" : "Promoter Panel",
                            subtitle: (lang == "es" ? "Evento #" : "Event #") + String(eventId),
                            onBack: { dismiss() },
                            onScan: { showScanner = true }
                        )

                        if let errorText, !isLoading {
                            ErrorText(text: errorText)
                                .padding(.horizontal)
                        }

                        // Stats
                        StatsRow(
                            soldLabel: lang == "es" ? "Vendidas" : "Sold",
                            soldValue: "\(ticketsSold)",
                            refLabel: "Ref",
                            refValue: referralCode.isEmpty ? "—" : referralCode,
                            grossLabel: lang == "es" ? "Bruto" : "Gross",
                            grossValue: grossText
                        )
                        .padding(.horizontal)

                        // Referral
                        ReferralCard(
                            title: lang == "es" ? "Tu enlace de referencia" : "Your referral link",
                            code: referralLink,                      // show the full link in the badge
                            isLoading: isLoading,
                            onCopy: {
                                guard !referralLink.isEmpty else { return }
                                UIPasteboard.general.string = referralLink   // copy the full link
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            },
                            onShare: {
                                guard !referralLink.isEmpty else { return }
                                shareURL = URL(string: referralLink)        // share the full link
                                showShareSheet = true
                            },
                            lang: lang
                        )
                        .padding(.horizontal)


                        // Buyers
                        BuyersSection(
                            buyers: buyers,
                            isLoading: isLoading,
                            title: lang == "es" ? "Compradores referidos" : "Referred buyers",
                            emptyText: isPromoterForEvent
                                ? (lang == "es" ? "Aún no tienes compras." : "You don’t have purchases yet.")
                                : (lang == "es" ? "No eres promotor para este evento." : "You’re not a promoter for this event."),
                            lang: lang
                        )
                        .padding(.horizontal)

                        Spacer(minLength: 24)
                    }
                    .padding(.bottom, 16)
                }
                .refreshable { loadAll() }

                if isLoading {
                    ProgressView().tint(.gold)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = shareURL {
                    PromoterShareSheet(activityItems: [url])
                }
            }
            .sheet(isPresented: $showScanner) {
                TicketValidationViewForScanner(eventId: eventId)
            }
            .onAppear { loadAll() }
            .navigationBarHidden(true)
        }
    }

    
    // MARK: - Orchestration
    private func loadAll() {
        isLoading = true
        errorText = nil
        isPromoterForEvent = false
        buyers = []
        promoterRow = nil

        guard let token = TokenManager.shared.getAccessToken() else {
            self.isLoading = false
            self.errorText = lang == "es" ? "No autenticado" : "Not authenticated"
            return
        }

        fetchPromoterMe(token: token) { meResult in
            switch meResult {
            case .failure(let err):
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorText = (self.lang == "es" ? "No eres promotor." : "You are not a promoter.") + " (\(err.localizedDescription))"
                }
            case .success(let me):
                self.me = me
                self.fetchDashboard(eventId: self.eventId, token: token) { dashResult in
                    switch dashResult {
                    case .failure(let err):
                        DispatchQueue.main.async {
                            self.isLoading = false
                            self.errorText = (self.lang == "es" ? "No se pudo cargar el panel." : "Failed to load dashboard.") + " (\(err.localizedDescription))"
                        }
                    case .success(let rows):
                        let myRow = rows.first(where: { $0.promoter.id == me.id })
                        DispatchQueue.main.async {
                            self.promoterRow = myRow
                            self.isPromoterForEvent = (myRow != nil)
                        }

                        if let myRow {
                            self.fetchBuyers(eventId: self.eventId, promoterId: myRow.promoter.id, token: token) { buyersResult in
                                DispatchQueue.main.async {
                                    self.isLoading = false
                                    switch buyersResult {
                                    case .failure(let err):
                                        self.errorText = (self.lang == "es" ? "No se pudo cargar compradores." : "Failed to load buyers.") + " (\(err.localizedDescription))"
                                    case .success(let list):
                                        self.buyers = list
                                    }
                                }
                            }
                        } else {
                            DispatchQueue.main.async {
                                self.isLoading = false
                                self.buyers = []
                                self.errorText = self.lang == "es" ? "No eres promotor para este evento." : "You’re not a promoter for this event."
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Networking (defensive)
    private func fetchPromoterMe(token: String, completion: @escaping (Result<PromoterMeDTO,Error>) -> Void) {
        guard let url = URL(string: "https://backendevent-etce.onrender.com/api/promoters/me") else {
            completion(.failure(SimpleError("Bad URL /me"))); return
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err = err { completion(.failure(err)); return }
            guard let http = resp as? HTTPURLResponse else {
                completion(.failure(SimpleError("No HTTP response"))); return
            }
            if http.statusCode != 200 { completion(.failure(SimpleError("Status \(http.statusCode)"))); return }
            guard let data = data, data.count > 0 else { completion(.failure(SimpleError("Empty body"))); return }
            if let ctype = http.value(forHTTPHeaderField: "Content-Type"), !ctype.lowercased().contains("application/json") {
                completion(.failure(SimpleError("Non-JSON /me response"))); return
            }
            do { completion(.success(try JSONDecoder().decode(PromoterMeDTO.self, from: data))) }
            catch { completion(.failure(error)) }
        }.resume()
    }

    private func fetchDashboard(eventId: Int, token: String, completion: @escaping (Result<[PromoterEventView],Error>) -> Void) {
        guard let url = URL(string: "https://backendevent-etce.onrender.com/api/promoters/event/\(eventId)/dashboard") else {
            completion(.failure(SimpleError("Bad URL /dashboard"))); return
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err = err { completion(.failure(err)); return }
            guard let http = resp as? HTTPURLResponse else {
                completion(.failure(SimpleError("No HTTP response"))); return
            }
            if http.statusCode == 204 || (data?.isEmpty ?? true) { completion(.success([])); return }
            if http.statusCode != 200 { completion(.failure(SimpleError("Status \(http.statusCode)"))); return }
            guard let data = data, data.count > 0 else { completion(.success([])); return }
            if let ctype = http.value(forHTTPHeaderField: "Content-Type"), !ctype.lowercased().contains("application/json") {
                completion(.failure(SimpleError("Non-JSON dashboard response"))); return
            }
            do { completion(.success(try JSONDecoder().decode([PromoterEventView].self, from: data))) }
            catch { completion(.failure(error)) }
        }.resume()
    }

    private func fetchBuyers(eventId: Int, promoterId: Int, token: String, completion: @escaping (Result<[ReferredBuyerDTO],Error>) -> Void) {
        guard let url = URL(string: "https://backendevent-etce.onrender.com/api/promoters/event/\(eventId)/promoter/\(promoterId)/buyers") else {
            completion(.failure(SimpleError("Bad URL /buyers"))); return
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err = err { completion(.failure(err)); return }
            guard let http = resp as? HTTPURLResponse else {
                completion(.failure(SimpleError("No HTTP response"))); return
            }
            if http.statusCode == 204 || (data?.isEmpty ?? true) { completion(.success([])); return }
            if http.statusCode != 200 { completion(.failure(SimpleError("Status \(http.statusCode)"))); return }
            guard let data = data, data.count > 0 else { completion(.success([])); return }
            if let ctype = http.value(forHTTPHeaderField: "Content-Type"), !ctype.lowercased().contains("application/json") {
                completion(.failure(SimpleError("Non-JSON buyers response"))); return
            }
            do { completion(.success(try JSONDecoder().decode([ReferredBuyerDTO].self, from: data))) }
            catch { completion(.failure(error)) }
        }.resume()
    }

    private func buildShareURL() {
        guard !referralCode.isEmpty else { return }
        shareURL = URL(string: "https://wkndevent.com/#/events/\(eventId)?ref=\(referralCode)")
    }
}

// MARK: - DTOs

struct PromoterMeDTO: Decodable {
    let id: Int
    let referralCode: String?
    let user: PromoterMeUser

    struct PromoterMeUser: Decodable {
        let id: Int
        let username: String?
        let email: String?
        let fullName: String?
    }
}

// MARK: - UI Pieces

private struct HeaderBar: View {
    let title: String
    let subtitle: String
    let onBack: () -> Void
    let onScan: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button(action: onBack) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left").font(.headline)
                        Text("Back")
                            .font(.headline.weight(.semibold))
                    }
                    .foregroundColor(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.06), in: Capsule())
                }
                Spacer()
                Button(action: onScan) {
                    Image(systemName: "qrcode.viewfinder")
                        .foregroundColor(.yellow)
                        .padding(10)
                        .background(Color.white.opacity(0.10), in: Circle())
                }
                .accessibilityLabel("Scan tickets")
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)
                Text(subtitle)
                    .foregroundColor(.white.opacity(0.65))
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

private struct ErrorText: View {
    let text: String
    var body: some View {
        Text(text)
            .foregroundColor(.red)
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StatsRow: View {
    let soldLabel: String
    let soldValue: String
    let refLabel: String
    let refValue: String
    let grossLabel: String
    let grossValue: String

    var body: some View {
        HStack(spacing: 12) {
            StatPill(title: soldLabel,  value: soldValue,  icon: "ticket.fill")
            StatPill(title: refLabel,   value: refValue,   icon: "at")
            StatPill(title: grossLabel, value: grossValue, icon: "dollarsign.circle.fill")
            Spacer(minLength: 0)
        }
    }
}


private struct StatPill: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundColor(.gold)
                Text(title).font(.caption).foregroundColor(.white.opacity(0.7))
            }
            Text(value)
                .font(.title3.bold())
                .foregroundColor(.gold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.06)))
    }
}

private struct ReferralCard: View {
    let title: String
    let code: String
    let isLoading: Bool
    let onCopy: () -> Void
    let onShare: () -> Void
    let lang: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).foregroundColor(.white)

            HStack(spacing: 10) {
                CodeBadge(code: code)

                Spacer(minLength: 8)

                Button {
                    onCopy()
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { copied = false }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? (lang == "es" ? "Copiado" : "Copied")
                                    : (lang == "es" ? "Copiar" : "Copy"))
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundColor(.white)
                }

                Button(action: onShare) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                        Text(lang == "es" ? "Compartir" : "Share")
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(Color.gold, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundColor(.black)
                }
                .disabled(code.isEmpty)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .redacted(reason: isLoading ? .placeholder : [])
    }
}

private struct CodeBadge: View {
    let code: String
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(code.isEmpty ? "—" : code)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundColor(.gold)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .lineLimit(1)
                .truncationMode(.middle)          // ⟵ key for links
                .minimumScaleFactor(0.85)
        }
        .frame(height: 36)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}


private struct BuyersSection: View {
    let buyers: [ReferredBuyerDTO]
    let isLoading: Bool
    let title: String
    let emptyText: String
    let lang: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.headline).foregroundColor(.white)
                Spacer()
                CountBadge(count: buyers.count)
            }

            if isLoading {
                ForEach(0..<3, id: \.self) { _ in BuyerSkeletonRow() }
            } else if buyers.isEmpty {
                Text(emptyText)
                    .foregroundColor(.white.opacity(0.7))
                    .font(.subheadline)
                    .padding(.top, 4)
            } else {
                ForEach(buyers, id: \.id) { b in BuyerRow(buyer: b, lang: lang) }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }
}

private struct CountBadge: View {
    let count: Int
    var body: some View {
        Text("\(count)")
            .font(.subheadline)
            .foregroundColor(.white.opacity(0.7))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.08), in: Capsule())
    }
}

private struct BuyerRow: View {
    let buyer: ReferredBuyerDTO
    let lang: String

    // Safe computed props (no `self` in stored inits)
    private var qty: Int { buyer.quantity ?? 1 }
    private var unitPrice: Double { buyer.unitPrice ?? 0 }
    private var priceText: String { String(format: "$%.2f", unitPrice) }

    private var displayName: String {
        let u = (buyer.username ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let e = (buyer.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !u.isEmpty { return u }
        if !e.isEmpty { return e }
        return lang == "es" ? "Desconocido" : "Unknown"
    }

    private var timeText: String {
        relativeTime(from: buyer.timestamp)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 42, height: 42)
                .overlay(Image(systemName: "person.fill").foregroundColor(.gold))

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .foregroundColor(.white)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                    .truncationMode(.tail)

                if !timeText.isEmpty {
                    Text(timeText) // e.g., "2h ago"
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            Spacer(minLength: 0)

            // qty × price chip
            Text("x\(qty) • \(priceText)")
                .font(.caption.weight(.semibold))
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Color.white.opacity(0.08), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
                .foregroundStyle(Color.gold)
        }
        .padding(10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.05), lineWidth: 1))
    }
}

// MARK: - Time helpers (short, human-readable)
fileprivate func relativeTime(from iso: String?) -> String {
    guard let iso, let date = parseISO(iso) else { return "" }
    let fmt = RelativeDateTimeFormatter()
    fmt.unitsStyle = .abbreviated   // "2h ago", "5m ago"
    return fmt.localizedString(for: date, relativeTo: Date())
}

fileprivate func parseISO(_ s: String) -> Date? {
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


private struct BuyerSkeletonRow: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 21)
                .fill(Color.white.opacity(0.08))
                .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 160, height: 12)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.07))
                    .frame(width: 200, height: 10)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .redacted(reason: .placeholder)
    }
}

private struct PromoterShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct SimpleError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

private extension Optional where Wrapped == String {
    var nilIfBlank: String? {
        guard let s = self, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return s
    }
}
