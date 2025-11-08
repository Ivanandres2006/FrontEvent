import SwiftUI
import PhotosUI

// MARK: - Color Palette (keeps your deepNavy + adds high-contrast accents)
extension Color {
    //static let deepNavy   = Color("DeepNavy") // make sure this Color Set exists in Assets
    static let neonCyan   = Color(red: 0.07, green: 0.84, blue: 0.97)
    static let neonPurple = Color(red: 0.60, green: 0.35, blue: 0.98)
    static let neonMint   = Color(red: 0.42, green: 0.95, blue: 0.74)
    static let neonOrange = Color(red: 1.00, green: 0.62, blue: 0.22)
    static let blackGold  = Color(red: 119/255, green: 106/255, blue: 5/255) // #776A05
}

extension Notification.Name {
    static let didLogout = Notification.Name("auth.didLogout")
}

// MARK: - Analytics DTO (tolerant to differing backend keys)
struct ProfileStats: Decodable, Equatable {
    let totalTickets: Int
    let totalSpent: Double?
    let averageTicketPrice: Double?
    let avgPerEvent: Double?
    let topSellerName: String?
    let topSellerAvatar: String?
    let mostEventName: String?
    let mostEventCover: String?
    let attended: Int
    let attending: Int
    let topEventCount: Int?

    enum CodingKeys: CodingKey { case totalTickets, totalPurchased, totalSpent, spent, sumAmount,
                                 averageTicketPrice, averagePrice, avgTicketPrice,
                                 avgPerEvent, averagePerEvent,
                                 topSellerName, topSellerAvatar,
                                 mostEventName, topEventName, mostEventCover, topEventCover,
                                 attended, eventsAttended, attending, eventsAttending, topEventCount }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        func int(_ a: CodingKeys, _ b: CodingKeys? = nil) -> Int? {
            (try? c.decode(Int.self, forKey: a)) ?? (b.flatMap { try? c.decode(Int.self, forKey: $0) })
        }
        func dbl(_ a: CodingKeys, _ b: CodingKeys? = nil, _ c3: CodingKeys? = nil) -> Double? {
            (try? c.decode(Double.self, forKey: a))
            ?? (b.flatMap { try? c.decode(Double.self, forKey: $0) })
            ?? (c3.flatMap { try? c.decode(Double.self, forKey: $0) })
        }
        func str(_ a: CodingKeys, _ b: CodingKeys? = nil) -> String? {
            (try? c.decode(String.self, forKey: a)) ?? (b.flatMap { try? c.decode(String.self, forKey: $0) })
        }

        totalTickets       = int(.totalTickets, .totalPurchased) ?? 0
        totalSpent         = dbl(.totalSpent, .spent, .sumAmount)
        averageTicketPrice = dbl(.averageTicketPrice, .averagePrice, .avgTicketPrice)
        avgPerEvent        = dbl(.avgPerEvent, .averagePerEvent)
        topSellerName      = str(.topSellerName, nil)
        topSellerAvatar    = str(.topSellerAvatar, nil)
        mostEventName      = str(.mostEventName, .topEventName)
        mostEventCover     = str(.mostEventCover, .topEventCover)
        attended           = int(.attended, .eventsAttended) ?? 0
        attending          = int(.attending, .eventsAttending) ?? 0
        topEventCount      = int(.topEventCount, nil)
    }
}

// MARK: - FX (BCV) API -> updates @AppStorage("vesPerUSD")
// MARK: - FX (BCV) API -> updates @AppStorage("vesPerUSD")
enum FXAPI {
    private static let base = URL(string: "https://backendevent-etce.onrender.com")!
    private static let ttl: TimeInterval = 30 * 60 // 30 minutes
    private static let cacheKey = "fx_bcv_rate"
    private static let cacheTsKey = "fx_bcv_rate_ts"

    struct FxResponse: Decodable {
        let vesPerUsd: Double
        let source: String?          // "bcv" | "cache" | "fallback"
        let fetchedAt: String?
        let fallback: Double?
        let overrideActive: Bool?
        let overrideUntil: String?
    }

    static func shouldRefresh(now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        let ts = UserDefaults.standard.double(forKey: cacheTsKey)
        return (now - ts) > ttl
    }

    static func cachedRate() -> Double? {
        let v = UserDefaults.standard.double(forKey: cacheKey)
        return v > 0 ? v : nil
    }

    static func save(rate: Double) {
        guard rate > 0 else { return }
        UserDefaults.standard.set(rate, forKey: cacheKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: cacheTsKey)
    }

    /// Returns (rate, source) where source is "override" | "bcv"
    static func fetchVESPerUSD() async throws -> (Double, String) {
        var req = URLRequest(url: base.appendingPathComponent("/api/fx/ves-per-usd"))
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let fx = try JSONDecoder().decode(FxResponse.self, from: data)
        let src = (fx.overrideActive == true) ? "override" : (fx.source ?? "bcv")
        return (fx.vesPerUsd, src)
    }
}


// MARK: - Ancs API (safe: if it fails, UI hides)
enum ProfileAnalyticsAPI {
    private static let base = URL(string: "https://backendevent-etce.onrender.com")!
    private static func bearer() -> String? { TokenManager.shared.getAccessToken() }

    static func myStats() async throws -> ProfileStats {
        var req = URLRequest(url: base.appendingPathComponent("/api/analytics/me/profile"))
        if let t = bearer() { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(ProfileStats.self, from: data)
    }
}

// MARK: - Main View
struct ProfileView: View {
    @EnvironmentObject var userSession: UserSession
    @AppStorage("selectedLanguage") private var lang: String = "en"
    @AppStorage("isLoggedIn", store: UserDefaults.standard) private var isLoggedIn = false
    
    @Environment(\.scenePhase) private var scenePhase

    // Tabs (no Admin tab anymore — we navigate with a button)
    enum Mode: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case content  = "Content"
        case suggestions = "Suggestions"
        case settings = "Settings"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .overview:    return "person.crop.circle.fill"
            case .content:     return "square.grid.3x3.fill"
            case .suggestions: return "person.2.fill"
            case .settings:    return "gearshape.fill"
            }
        }
    }
    @State private var mode: Mode = .overview

    // Editable profile
    @State private var displayName = ""
    @State private var username = ""
    @State private var bio = ""
    @State private var avatarPreview: UIImage?
    @State private var selectedItem: PhotosPickerItem?
    @State private var avatarUploading = false

    // Social lists
    @State private var myFollowers: [UserSummary] = []
    @State private var myFollowing: [UserSummary] = []
    @State private var myFriends:   [UserSummary] = []

    // Requests + Badges
    @State private var requests: [FollowRequest] = []
    @State private var myBadges: [BadgeDTO] = []

    // Analytics
    @State private var stats: ProfileStats?
    @State private var statsLoading = false

    // Loading + state
    @State private var isFetching = true
    @State private var isSaving = false

    // Snackbar
    @State private var toast: Toast? = nil

    // Me
    @State private var myId: Int = 0

    @State private var showLogoutConfirm = false

    @AppStorage("currencyCode") private var currencyCode: String = "USD"   // "USD" or "VES"
    @AppStorage("vesPerUSD")     private var vesPerUSD: Double  = 179.43    // editable by user
    @State private var showVESRateSheet = false
    @State private var fxSource: String = "" // "bcv" | "cache" | ""

    // ProfileView state
    @State private var counts = SocialCounts(followers: 0, following: 0, friends: 0)

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom).ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 20) {
                        headerCard
                        topTabBar
                        selectedTabContent
                    }
                    .padding(.bottom, 44)
                }

                if isSaving || isFetching { ProgressView().tint(.white) }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(lang == "es" ? "Perfil" : "Profile")
                        .font(.title2.bold()).foregroundStyle(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: saveBio) {
                        if isSaving { ProgressView() }
                        else { Label(lang == "es" ? "Guardar" : "Save", systemImage: "checkmark.circle.fill") }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white.opacity(0.14))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .disabled(isSaving || isFetching)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .socialDidChange)) { note in
                guard note.object is SocialEvent else { return }
                Task { await reloadMySocial() }
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    Task { await refreshVESRateIfNeeded(force: true) }
                }
            }
            .onReceive(
                Timer.publish(every: 30*60, on: .main, in: .common).autoconnect()
            ) { _ in
                Task { await refreshVESRateIfNeeded(force: true) }
            }
            .task {
                await refreshVESRateIfNeeded(force: false)
                await loadMe()
                await loadStats()
            }
            .snackbar($toast)
        }
    }

    // MARK: - Header (now includes Admin button when role == ADMIN)
    private var headerCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .fill(LinearGradient(colors: [.white.opacity(0.06), .white.opacity(0.02)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    ZStack {
                        Circle().fill(Color.blackGold.opacity(0.16)).frame(width: 260).blur(radius: 46).offset(x: -120, y: -90)
                        Circle().fill(Color.blackGold.opacity(0.16)).frame(width: 210).blur(radius: 38).offset(x: 140, y: 30)
                    }
                )
                .overlay(.ultraThinMaterial.opacity(0.28))
                .overlay(RoundedRectangle(cornerRadius: 28).stroke(Color.white.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 30, y: 10)

            VStack(spacing: 16) {
                HStack(alignment: .center, spacing: 16) {
                    avatarPicker

                    VStack(alignment: .leading, spacing: 4) {
                        TextField(lang == "es" ? "Nombre" : "Name", text: $displayName)
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                            .textInputAutocapitalization(.words)

                        Text("@\(username)")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.78))
                    }
                    Spacer()
                }

                // Bio
                VStack(alignment: .leading, spacing: 8) {
                    Text(lang == "es" ? "Biografía" : "Bio")
                        .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $bio)
                            .frame(minHeight: 76)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .foregroundStyle(.white)
                            .background(.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.08), lineWidth: 1))
                        if bio.isEmpty {
                            Text(lang == "es" ? "Escribe una biografía…" : "Write a short bio…")
                                .foregroundStyle(.white.opacity(0.45))
                                .padding(.horizontal, 16).padding(.vertical, 7)
                        }
                    }
                }

                // Social chips
                HStack(spacing: 12) {
                    statChip(count: counts.followers, title: "Followers") { PeopleListView(mode: .followers, userId: myId) }
                    statChip(count: counts.following, title: "Following") { PeopleListView(mode: .following, userId: myId) }
                    statChip(count: counts.friends,   title: "Friends")   { PeopleListView(mode: .friends,   userId: myId) }
                }

                // Admin button (visible only for admins)
                if userSession.role == "ADMIN" {
                    NavigationLink {
                        AdminDashboardView()     // push to the console
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.shield.fill").font(.headline)
                            Text("Owner Console")
                                .font(.headline.weight(.semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(
                            LinearGradient(
                                colors: [.blackGold.opacity(0.9), .gold.opacity(0.55)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                        .padding(.top, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Analytics Overview (money, averages, events)
    @ViewBuilder
    private var analyticsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label(lang == "es" ? "Resumen" : "Overview", systemImage: "chart.bar.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)

                    Spacer()

                    // currency toggle
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
                        Button(currencyCode == "USD" ? "Switch to Bolívares (VES)" : "Switch to USD") {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                currencyCode = (currencyCode == "USD") ? "VES" : "USD"
                            }
                        }
                        Button("View USD → VES rate") {
                            showVESRateSheet = true
                        }
                    }


                    Text(Date(), style: .date)
                        .font(.caption).foregroundStyle(.white.opacity(0.5))
                }
                .sheet(isPresented: $showVESRateSheet) {
                    VESRateInfoSheet()                   // ← no editing, always shows backend value
                        .presentationDetents([.height(220)])
                }

                // Compute values with graceful fallbacks
                let s = stats
                let tickets = s?.totalTickets ?? 0
                let totalSpent: Double? = s?.totalSpent ?? {
                    guard let avg = s?.averageTicketPrice else { return nil }
                    return Double(tickets) * avg
                }()
                let avgPerEvent: Double? = s?.avgPerEvent ?? {
                    guard let total = totalSpent, let attended = s?.attended else { return nil }
                    guard attended > 0 else { return 0 }
                    return total / Double(attended)
                }()

                // KPIs (2x2 grid)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    MetricTile(title: lang == "es" ? "Gastado" : "Total Spent",
                               value: totalSpent.map(currency) ?? "—",
                               sub: lang == "es" ? "acumulado" : "lifetime",
                               gradient: Gradient(colors: [.blackGold.opacity(0.38), .blackGold.opacity(0.14)]))

                    MetricTile(title: lang == "es" ? "Entradas" : "Tickets",
                               value: "\(tickets)",
                               sub: lang == "es" ? "compradas" : "purchased",
                               gradient: Gradient(colors: [.blackGold.opacity(0.40), .blackGold.opacity(0.14)]))

                    MetricTile(title: lang == "es" ? "Prom. por evento" : "Avg / Event",
                               value: avgPerEvent.map(currency) ?? "—",
                               sub: lang == "es" ? "gasto" : "spend",
                               gradient: Gradient(colors: [.blackGold.opacity(0.40), .blackGold.opacity(0.14)]))

                    MetricTile(title: lang == "es" ? "Prom. por ticket" : "Avg / Ticket",
                               value: (s?.averageTicketPrice).map(currency) ?? "—",
                               sub: lang == "es" ? "precio" : "price",
                               gradient: Gradient(colors: [.blackGold.opacity(0.38), .blackGold.opacity(0.14)]))
                }
                .redacted(reason: statsLoading ? .placeholder : [])

                // Attendance
                AttendanceCard(
                    attended: s?.attended ?? 0,
                    upcoming: s?.attending ?? 0,
                    title: lang == "es" ? "Asistencia" : "Attendance",
                    attendedLabel: lang == "es" ? "Asistidos" : "Attended",
                    upcomingLabel: lang == "es" ? "Por asistir" : "Upcoming"
                )
                .redacted(reason: statsLoading ? .placeholder : [])

                // Top seller & Most-attended event
                if let name = s?.topSellerName, !name.isEmpty || (s?.mostEventName?.isEmpty == false) {
                    Divider().overlay(Color.white.opacity(0.08))

                    HStack(spacing: 12) {
                        if let name = s?.topSellerName, !name.isEmpty {
                            SellerTile(
                                title: lang == "es" ? "Más compras a" : "Most purchased from",
                                name: name,
                                avatarURL: s?.topSellerAvatar
                            )
                            .frame(maxWidth: .infinity)
                        }

                        if let event = s?.mostEventName, !event.isEmpty {
                            EventTile(
                                title: lang == "es" ? "Evento más asistido" : "Most attended event",
                                eventName: event,
                                coverURL: s?.mostEventCover,
                                count: s?.topEventCount
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Avatar Picker
    private var avatarPicker: some View {
        PhotosPicker(selection: $selectedItem, matching: .images) {
            ZStack {
                Group {
                    if let img = avatarPreview {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else if !userSession.avatarUrl.isEmpty, let u = URL(string: userSession.avatarUrl) {
                        AsyncImage(url: u) { img in img.resizable().scaledToFill() }
                            placeholder: { Color.white.opacity(0.1) }
                    } else {
                        Image(systemName: "person.fill").resizable().scaledToFit().padding(18)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .frame(width: 96, height: 96)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))

                HStack { Spacer(); VStack {
                    Spacer()
                    Image(systemName: "camera.fill").font(.caption2.bold())
                        .padding(6).background(.black.opacity(0.7)).clipShape(Circle())
                        .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1)).offset(x: 6, y: 6)
                }}

                if avatarUploading {
                    ProgressView().progressViewStyle(.circular).tint(.white)
                        .frame(width: 96, height: 96)
                        .background(Color.black.opacity(0.35))
                        .clipShape(Circle()).transition(.opacity)
                }
            }
        }
        .onChange(of: selectedItem) { _ in Task { await handleAvatarPicked() } }
        .buttonStyle(.plain)
    }

    private var topTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(availableModes) { m in
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) { mode = m }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: m.icon).font(.footnote.bold())
                            Text(m.rawValue).font(.footnote.weight(.semibold))
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .foregroundColor(.white)
                        .background(
                            Group {
                                if mode == m {
                                    LinearGradient(
                                        colors: [.blackGold.opacity(0.55), .gold.opacity(0.55)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    )
                                } else {
                                    Color.white.opacity(0.10)
                                }
                            }
                        )
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))
                        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    private var availableModes: [Mode] { [.overview, .content, .suggestions, .settings] }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch mode {
        case .overview:
            VStack(spacing: 16) { analyticsCard; overviewExtras }
                .transition(.opacity.combined(with: .scale))
        case .content:
            contentTab.transition(.opacity.combined(with: .move(edge: .trailing)))
        case .suggestions:
            suggestionsTab.transition(.opacity.combined(with: .move(edge: .trailing)))
        case .settings:
            settingsTab.transition(.opacity.combined(with: .move(edge: .trailing)))
        }
    }

    // Extra cards under overview
    private var overviewExtras: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !myBadges.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(lang == "es" ? "Insignias" : "Badges", systemImage: "seal.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
                        BadgeRow(badges: myBadges)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var contentTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            GlassCard { UserPhotosGridView(userId: myId) }.padding(.horizontal)
            HStack(spacing: 10) {
                Image(systemName: "lightbulb.max.fill")
                Text(lang == "es" ? "Tip: abre el evento al que vas para subir una foto desde ahí."
                                  : "Tip: open the event you’re attending to upload a photo from there.")
            }
            .font(.footnote).foregroundStyle(.white.opacity(0.7)).padding(.horizontal)
        }
    }

    private var suggestionsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            GlassCard { ContactsSyncView() }.padding(.horizontal)
        }
    }

    private var settingsTab: some View {
        VStack(spacing: 18) {
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle(lang == "es" ? "Recordatorios de eventos" : "Event reminders", isOn: .constant(true))
                    Toggle(lang == "es" ? "Alertas de reventa" : "Resale alerts", isOn: .constant(true))
                    Toggle(lang == "es" ? "Permitir mensajes" : "Allow DMs", isOn: .constant(true))
                }
                .tint(.white).foregroundStyle(.white)
            }
            .padding(.horizontal)

            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text(lang == "es" ? "Idioma" : "Language")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))

                    Picker("", selection: $lang) {
                        Text("English").tag("en")
                        Text("Español").tag("es")
                    }
                    .pickerStyle(.segmented)
                }
                .foregroundStyle(.white)
            }
            .padding(.horizontal)

            // --- Logout row ---
            GlassCard {
                Button(role: .destructive) {
                    showLogoutConfirm = true
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text(lang == "es" ? "Cerrar sesión" : "Log out")
                            .font(.headline)
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .padding(.vertical, 4)
                }
            }
            .padding(.horizontal)
        }
        .confirmationDialog(
            lang == "es" ? "¿Cerrar sesión?" : "Log out?",
            isPresented: $showLogoutConfirm,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task { await performLogout() }
            } label: {
                Text(lang == "es" ? "Cerrar sesión" : "Log out")
            }
            Button(lang == "es" ? "Cancelar" : "Cancel", role: .cancel) { }
        }
    }

    @MainActor
    private func refreshVESRateIfNeeded(force: Bool = false) async {
        if !force, let cached = FXAPI.cachedRate(), !FXAPI.shouldRefresh() {
            vesPerUSD = cached
            fxSource = "cache"
            return
        }
        do {
            let (live, src) = try await FXAPI.fetchVESPerUSD()
            vesPerUSD = live
            fxSource = src           // "override" or "bcv"
            FXAPI.save(rate: live)
        } catch {
            if let cached = FXAPI.cachedRate() {
                vesPerUSD = cached
                fxSource = "cache"
            } else {
                fxSource = ""
            }
        }
    }

    @MainActor
    private func reloadMySocial() async {
        guard myId > 0 else { return }
        async let followers = SocialAPI.fetch(.followers(userId: myId), limit: 100)
        async let following = SocialAPI.fetch(.following(userId: myId), limit: 100)
        async let friends   = SocialAPI.fetch(.friends(userId: myId),   limit: 100)
        async let countsReq = SocialAPI.fetchCounts(userId: myId)

        myFollowers = (try? await followers) ?? myFollowers
        myFollowing = (try? await following) ?? myFollowing
        myFriends   = (try? await friends)   ?? myFriends
        counts      = (try? await countsReq) ?? counts
    }

    // MARK: - Data
    @MainActor
    private func performLogout() async {
        TokenManager.shared.deleteToken()
        isLoggedIn = false
        NotificationCenter.default.post(name: .didLogout, object: nil)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        toast = .success(
            title: lang == "es" ? "Sesión cerrada" : "Signed out",
            message: lang == "es" ? "Vuelve a iniciar sesión cuando quieras."
                                  : "Sign in again anytime."
        )
    }

    @MainActor
    private func loadMe() async {
        isFetching = true
        defer { isFetching = false }

        guard TokenManager.shared.getAccessToken() != nil else {
            toast = .info(
                title: lang == "es" ? "Aviso" : "Notice",
                message: lang == "es" ? "Inicia sesión para ver tu perfil." : "Please sign in to view your profile."
            )
            return
        }

        do {
            let me = try await UserProfileAPI.getMe()
            myId        = me.id
            displayName = me.displayName ?? (userSession.fullName ?? "")
            username    = me.username ?? (userSession.username ?? "me")
            bio         = me.bio ?? ""
            if let url  = me.avatarUrl { userSession.avatarUrl = url }

            async let followersTask = SocialAPI.fetch(.followers(userId: me.id), limit: 100)
            async let followingTask = SocialAPI.fetch(.following(userId: me.id), limit: 100)
            async let friendsTask   = SocialAPI.fetch(.friends(userId: me.id),   limit: 100)
            async let badgesTask    = BadgesAPI.myBadges()
            async let countsTask    = SocialAPI.fetchCounts(userId: me.id)

            myFollowers = (try? await followersTask) ?? []
            myFollowing = (try? await followingTask) ?? []
            myFriends   = (try? await friendsTask)   ?? []
            myBadges    = (try? await badgesTask)    ?? []
            counts      = (try? await countsTask)    ?? counts

        } catch {
            print("Profile load failed:", error)
            toast = .error(
                title: "Error",
                message: lang == "es" ? "No se pudo cargar el perfil." : "Failed to load profile."
            )
        }
    }

    @MainActor
    private func loadStats() async {
        statsLoading = true
        defer { statsLoading = false }
        do {
            stats = try await ProfileAnalyticsAPI.myStats()
        } catch {
            stats = nil
        }
    }

    private func saveBio() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await UserProfileAPI.updateBio(bio)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                toast = .success(title: lang == "es" ? "Listo" : "Saved",
                                 message: lang == "es" ? "Perfil actualizado." : "Profile updated.")
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                toast = .error(title: "Error",
                               message: (lang == "es" ? "Error al guardar: " : "Save failed: ") + error.localizedDescription)
            }
        }
    }

    @MainActor
    private func handleAvatarPicked() async {
        guard let item = selectedItem else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                avatarPreview = img
                avatarUploading = true
                defer { avatarUploading = false }
                let newUrl = try await UserProfileAPI.uploadAvatar(img)
                userSession.avatarUrl = newUrl
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                toast = .success(title: lang == "es" ? "Listo" : "Success",
                                 message: lang == "es" ? "Foto actualizada." : "Photo updated.")
            }
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            toast = .error(title: "Error",
                           message: (lang == "es" ? "Error al subir: " : "Upload failed: ") + error.localizedDescription)
        }
    }

    private func currency(_ value: Double) -> String {
        let amount = (currencyCode == "VES") ? (value * vesPerUSD) : value
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 2
        if currencyCode == "VES" {
            f.currencyCode = "VES"
            f.locale = Locale(identifier: "es_VE")
        } else {
            f.currencyCode = "USD"
            f.locale = Locale(identifier: "en_US")
        }
        let symbol = (currencyCode == "VES") ? "Bs." : "$"
        return f.string(from: NSNumber(value: amount)) ?? "\(symbol)\(String(format: "%.2f", amount))"
    }

    private func statChip<Dest: View>(count: Int, title: String, dest: @escaping () -> Dest) -> some View {
        NavigationLink { dest() } label: {
            HStack(spacing: 6) {
                Text("\(count)").font(.headline.bold())
                Text(title).font(.footnote.weight(.semibold)).opacity(0.85)
            }
            .foregroundStyle(.white)
            .padding(.vertical, 10).frame(maxWidth: .infinity)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Components

private struct InlineField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.08), lineWidth: 1))
    }
}
private extension View { func applyFieldStyle() -> some View { modifier(InlineField()) } }

// Metric tile
private struct MetricTile: View {
    let title: String
    let value: String
    let sub: String
    let gradient: Gradient

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
            Text(value).font(.title3.bold())
            Text(sub).font(.caption2).foregroundStyle(.white.opacity(0.6))
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(gradient: gradient, startPoint: .topLeading, endPoint: .bottomTrailing).opacity(0.9))
        .background(.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.08), lineWidth: 1))
    }
}

// Skeleton while analytics loads (kept if you want to use it elsewhere)
private struct AnalyticsSkeleton: View {
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)).frame(height: 14)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)).frame(height: 70)
                    RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)).frame(height: 70)
                    RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)).frame(height: 70)
                    RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)).frame(height: 70)
                }
                RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)).frame(height: 36)
            }
            .redacted(reason: .placeholder)
        }
    }
}

// Snackbar
struct Toast: Equatable, Identifiable {
    enum Style { case success, error, info }
    var id = UUID()
    var style: Style
    var title: String
    var message: String

    static func success(title: String, message: String) -> Toast { .init(style: .success, title: title, message: message) }
    static func error(title: String, message: String) -> Toast { .init(style: .error, title: title, message: message) }
    static func info(title: String, message: String) -> Toast { .init(style: .info, title: title, message: message) }
}

private struct Snackbar: View {
    let toast: Toast
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.headline).padding(8).background(badge.opacity(0.2)).clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title).font(.subheadline.bold())
                Text(toast.message).font(.footnote)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(.black.opacity(0.7))
        .background(.ultraThinMaterial.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.08), lineWidth: 1))
        .padding(.horizontal)
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
    }
    private var icon: String {
        switch toast.style { case .success: "checkmark.circle.fill"; case .error: "xmark.octagon.fill"; case .info: "info.circle.fill" }
    }
    private var badge: Color {
        switch toast.style { case .success: .green; case .error: .red; case .info: .blue }
    }
}

// MARK: - Attendance
private struct AttendanceCard: View {
    let attended: Int
    let upcoming: Int
    let title: String
    let attendedLabel: String
    let upcomingLabel: String

    private var total: CGFloat { CGFloat(max(attended + upcoming, 1)) }
    private var attendedRatio: CGFloat { CGFloat(attended) / total }
    private var upcomingRatio: CGFloat { CGFloat(upcoming) / total }
    private var attendedPctText: String {
        "\(Int(round((Double(attended) / Double(max(attended + upcoming, 1))) * 100)))%"
    }
    private var upcomingPctText: String {
        "\(Int(round((Double(upcoming) / Double(max(attended + upcoming, 1))) * 100)))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: "figure.arms.open")
                    .foregroundColor(.white)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                HStack(spacing: 8) {
                    valueChip(color: .gold, text: attendedLabel, value: attended)
                    valueChip(color: .gold, text: upcomingLabel, value: upcoming)
                }
            }

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.16))
                GeometryReader { geo in
                    let totalW = geo.size.width
                    let attendedW = totalW * attendedRatio
                    Capsule()
                        .fill(LinearGradient(colors: [.blackGold, .gold.opacity(0.7)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: attendedW)
                    Capsule()
                        .fill(LinearGradient(colors: [.blue, .black.opacity(0.7)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: totalW - attendedW)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .frame(height: 14)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 1))

            HStack {
                legendDot(color: .gold, text: "\(attendedLabel) • \(attendedPctText)")
                Spacer()
                legendDot(color: .gold, text: "\(upcomingLabel) • \(upcomingPctText)")
            }
            .font(.caption2)
            .foregroundColor(.white.opacity(0.9))
        }
    }

    private func valueChip(color: Color, text: String, value: Int) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(text): \(value)").font(.caption.weight(.semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.white.opacity(0.10))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 1))
    }

    private func legendDot(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
        }
    }
}

// MARK: - Light tiles
private struct SellerTile: View {
    let title: String
    let name: String
    let avatarURL: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let avatarURL, let url = URL(string: avatarURL) {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Color.white.opacity(0.18)
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 1))
            } else {
                Circle().fill(Color.white.opacity(0.18))
                    .frame(width: 40, height: 40)
                    .overlay(Image(systemName: "person.fill").foregroundColor(.white.opacity(0.9)))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))

                Text(name)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .allowsTightening(true)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
            }
        }
        .padding(12)
        .background(
            LinearGradient(colors: [.blackGold.opacity(0.28), .gold.opacity(0.20)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .background(Color.white.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.18), lineWidth: 1))
    }
}

private struct EventTile: View {
    let title: String
    let eventName: String
    let coverURL: String?
    let count: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let coverURL, let url = URL(string: coverURL) {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Color.white.opacity(0.18)
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.22), lineWidth: 1))
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.18))
                    .frame(width: 40, height: 40)
                    .overlay(Image(systemName: "ticket.fill").foregroundColor(.white.opacity(0.9)))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))

                Text(eventName + (count.map { " ×\($0)" } ?? ""))
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .allowsTightening(true)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
            }
        }
        .padding(12)
        .background(
            LinearGradient(colors: [.blackGold.opacity(0.28), .gold.opacity(0.20)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .background(Color.white.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.18), lineWidth: 1))
    }
}

// Snackbar infra
private struct SnackbarModifier: ViewModifier {
    @Binding var toast: Toast?
    func body(content: Content) -> some View {
        ZStack(alignment: .bottom) {
            content
            if let toast {
                Snackbar(toast: toast)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                                self._toast.wrappedValue = nil
                            }
                        }
                    }
            }
        }
    }
}

struct VESRateInfoSheet: View {
    @AppStorage("vesPerUSD") private var vesPerUSD: Double = 179.43
    @State private var fxSource: String = ""    // "override" | "bcv" | "cache"
    @State private var loading = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            Text("USD → VES (from server)").font(.headline).foregroundStyle(.white)

            HStack(spacing: 8) {
                Text(String(format: "Bs. %.6f per $1", vesPerUSD))
                    .font(.title3.bold())
                    .foregroundStyle(Color.gold)
                Spacer()
                sourceBadge
            }

            Text(explainer)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.leading)

            HStack {
                Button("Close") { dismiss() }
                Spacer()
                Button {
                    Task { await refresh() }          // manual refresh from backend
                } label: {
                    if loading { ProgressView().tint(.white) }
                    else { Text("Refresh") }
                }
                .buttonStyle(.borderedProminent)
            }
            .foregroundStyle(.white)
        }
        .padding()
        .background(
            LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .task { await refresh() }
    }

    private var explainer: String {
        switch fxSource {
        case "override": return "Admin override is active on the backend. This value persists across restarts until it expires or is cleared."
        case "bcv":      return "Live BCV rate fetched by the backend. Cached on the server for a short time."
        case "cache":    return "Using cached rate from the backend."
        default:         return "Managed by the backend."
        }
    }

    private var sourceBadge: some View {
        Text(fxSource.isEmpty ? "server" : fxSource)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.white.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))
    }

    @MainActor
    private func refresh() async {
        loading = true; defer { loading = false }
        do {
            let (rate, src) = try await FXAPI.fetchVESPerUSD()
            vesPerUSD = rate                        // ← stored for rest of the app
            fxSource = src
            FXAPI.save(rate: rate)                  // keep local cache fresh
        } catch {
            // keep existing vesPerUSD; optionally show a toast in the parent
        }
    }
}


private extension View {
    func snackbar(_ toast: Binding<Toast?>) -> some View { modifier(SnackbarModifier(toast: toast)) }
}
