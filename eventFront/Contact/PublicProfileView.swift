import SwiftUI
import Foundation

// MARK: - Public analytics DTO/Client (unchanged logic; tolerant decoder)
private struct ProfileStatsPublic: Decodable, Equatable {
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

private enum PublicProfileAnalyticsAPI {
    private static let base = URL(string: "https://backendevent-etce.onrender.com")!
    private static func bearer() -> String? { TokenManager.shared.getAccessToken() }

    static func me() async throws -> ProfileStatsPublic { try await get("/api/analytics/me/profile") }
    static func user(_ id: Int) async throws -> ProfileStatsPublic { try await get("/api/analytics/me/user/\(id)/profile") }

    private static func get(_ path: String) async throws -> ProfileStatsPublic {
        var req = URLRequest(url: base.appendingPathComponent(path))
        if let t = bearer() { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(ProfileStatsPublic.self, from: data)
    }
}

struct PublicUserDTO: Decodable, Identifiable {
    let id: Int
    let username: String
    let displayName: String?
    let avatarUrl: String?
    let bio: String?
    let isPrivate: Bool
    let followersCount: Int
    let followingCount: Int
    let friendsCount: Int
    let eventsCount: Int

    private enum CodingKeys: String, CodingKey {
        case id, username, displayName, avatarUrl, avatarURL, bio, isPrivate,
             followersCount, followingCount, friendsCount, eventsCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(Int.self, forKey: .id)
        username        = try c.decode(String.self, forKey: .username)
        displayName     = try? c.decode(String.self, forKey: .displayName)

        // Accept either `avatarUrl` or `avatarURL`, trim, turn "" into nil
        let rawAvatar = (try? c.decode(String.self, forKey: .avatarUrl))
                     ?? (try? c.decode(String.self, forKey: .avatarURL))
        let trimmed = rawAvatar?.trimmingCharacters(in: .whitespacesAndNewlines)
        avatarUrl       = (trimmed?.isEmpty == true) ? nil : trimmed

        bio             = try? c.decode(String.self, forKey: .bio)
        isPrivate       = (try? c.decode(Bool.self, forKey: .isPrivate)) ?? false
        followersCount  = (try? c.decode(Int.self,  forKey: .followersCount)) ?? 0
        followingCount  = (try? c.decode(Int.self,  forKey: .followingCount)) ?? 0
        friendsCount    = (try? c.decode(Int.self,  forKey: .friendsCount)) ?? 0
        eventsCount     = (try? c.decode(Int.self,  forKey: .eventsCount)) ?? 0
    }
}


// MARK: - View
struct PublicProfileView: View {
    let userId: Int
    let usernameOrId: String?

    @EnvironmentObject var userSession: UserSession
    @AppStorage("selectedLanguage") private var lang: String = "en"

    enum Tab: String, CaseIterable, Identifiable { case overview = "Overview", photos = "Photos"; var id: String { rawValue } }

    // Header info
    @State private var displayName: String?
    @State private var username: String = ""
    @State private var bio: String = ""
    @State private var avatarUrl: String?
    @State private var isPrivate = false

    // Relationship
    @State private var isFollowing = false
    @State private var isRequested = false   // NEW: pending state
    @State private var isFollowedBy = false
    @State private var workingFollow = false

    // Lists
    @State private var followers: [UserSummary] = []
    @State private var following: [UserSummary] = []
    @State private var friends:   [UserSummary] = []

    // Badges
    @State private var badges: [BadgeDTO] = []

    // Analytics
    @State private var stats: ProfileStatsPublic?
    @State private var statsLoading = false

    // UI
    @State private var loading = true
    @State private var message: String?
    @State private var expandBio = false
    @State private var tab: Tab = .overview
    
    @State private var counts = SocialCounts(followers: 0, following: 0, friends: 0)

    private var meId: Int { Int(userSession.userId ?? 0) }
    private var isMe: Bool { meId == userId }

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom).ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    headerCard
                    topTabs

                    Group {
                        switch tab {
                        case .overview: overviewTab
                        case .photos:   photosTab
                        }
                    }
                    .transition(.opacity)
                }
                .padding(.bottom, 44)
                .padding(.top, 10)
            }

            if loading { ProgressView().tint(.white) }
        }
        .navigationTitle(lang == "es" ? "Perfil" : "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .socialDidChange)) { note in
            guard let ev = note.object as? SocialEvent else { return }
            switch ev.kind {
            case .requestAccepted, .requestRejected:
                if isMe { Task { await reloadSocial() } }  // my followers changed
            case .followed(let uid), .unfollowed(let uid):
                if isMe || uid == self.userId { Task { await reloadSocial() } }
            }
        }
    }

    // MARK: - Header
    private var headerCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    AvatarView(url: avatarUrl, size: 88)

                    // ⬇️ Make the name column expand and win space
                    VStack(alignment: .leading, spacing: 6) {
                        Text(displayNameOrUsername)
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                            .lineLimit(1)                // no wrapping
                            .minimumScaleFactor(0.85)    // shrink a bit if tight
                            .allowsTightening(true)
                            .truncationMode(.tail)       // “madriz…”
                        
                        if !username.isEmpty {
                            Text("@\(username)")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .allowsTightening(true)
                                .truncationMode(.tail)
                        }

                        if isFollowedBy && !isMe {
                            Label(lang == "es" ? "Te sigue" : "Follows you",
                                  systemImage: "arrowtriangle.right.circle.fill")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.white.opacity(0.12))
                                .clipShape(Capsule())
                                .foregroundStyle(.white.opacity(0.95))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)    // <-- important: text gets priority

                    Spacer(minLength: 0)

                    if !isMe {
                        Button(action: toggleFollow) {
                            if workingFollow { ProgressView().tint(.white) }
                            else {
                                Text(buttonTitle)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                    .allowsTightening(true)
                                    .truncationMode(.tail)
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background { buttonBackground }
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
                        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                        .fixedSize()        // <-- button doesn't expand and squeeze text
                    }
                }


                if !(bio.isEmpty || isPrivate) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(lang == "es" ? "Biografía" : "Bio")
                            .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                        Text(bio)
                            .font(.callout).foregroundStyle(.white.opacity(0.95))
                            .lineLimit(expandBio ? nil : 3)
                            .animation(.easeInOut(duration: 0.2), value: expandBio)

                        if bio.count > 140 {
                            Button(expandBio ? (lang == "es" ? "Ver menos" : "See less")
                                             : (lang == "es" ? "Ver más"  : "See more")) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { expandBio.toggle() }
                            }
                            .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.95))
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }
    
    private var normalizedAvatarUrl: String? {
        guard let url = avatarUrl, !url.isEmpty else { return nil }
        if url.starts(with: "http") { return url }
        return "https://backendevent-etce.onrender.com" + (url.hasPrefix("/") ? "" : "/") + url
    }


    private var buttonTitle: String {
        if isFollowing { return lang == "es" ? "Siguiendo" : "Following" }
        if isRequested { return lang == "es" ? "Solicitado" : "Requested" }
        return lang == "es" ? "Seguir" : "Follow"
    }

    @ViewBuilder private var buttonBackground: some View {
        if isFollowing || isRequested {
            Color.white.opacity(0.16)
        } else {
            LinearGradient(colors: [.neonCyan.opacity(0.8), .neonPurple.opacity(0.8)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
    
    // Add this helper inside PublicProfileView
    private var displayNameOrUsername: String {
        if let d = displayName, !d.isEmpty { return d }
        if !username.isEmpty { return username }
        return "@user\(userId)"
    }


    // MARK: - Tabs
    private var topTabs: some View {
        HStack(spacing: 10) {
            ForEach(Tab.allCases) { t in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { tab = t }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: t == .overview ? "chart.bar.fill" : "square.grid.3x3.fill")
                            .font(.footnote.bold())
                        Text(t == .overview ? (lang == "es" ? "Resumen" : "Overview")
                                            : (lang == "es" ? "Fotos"   : "Photos"))
                            .font(.footnote.weight(.semibold))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .foregroundColor(.white)
                    .background(
                        t == tab
                        ? AnyView(LinearGradient(colors: [.neonCyan.opacity(0.55), .neonPurple.opacity(0.55)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                        : AnyView(Color.white.opacity(0.10))
                    )
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Overview
    private var overviewTab: some View {
        VStack(spacing: 16) {
            countsRow

            if !badges.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(lang == "es" ? "Insignias" : "Badges", systemImage: "seal.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.9))
                        BadgeRow(badges: badges)
                    }
                }
                .padding(.horizontal)
            }

            analyticsCard
        }
    }

    // MARK: - Photos
    private var photosTab: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(lang == "es" ? "Fotos" : "Photos")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.9))
                UserPhotosGridView(userId: userId)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Counts row
    private var countsRow: some View {
        HStack(spacing: 12) {
            navPill(title: lang == "es" ? "Seguidores" : "Followers", count: counts.followers) {
                PeopleListView(mode: .followers, userId: userId)
            }
            navPill(title: lang == "es" ? "Siguiendo" : "Following", count: counts.following) {
                PeopleListView(mode: .following, userId: userId)
            }
            navPill(title: lang == "es" ? "Amigos" : "Friends", count: counts.friends) {
                PeopleListView(mode: .friends, userId: userId)
            }
        }
        .padding(.horizontal)
    }


    private func navPill<Dest: View>(title: String, count: Int, dest: @escaping () -> Dest) -> some View {
        NavigationLink { dest() } label: {
            VStack(spacing: 2) {
                Text("\(count)").font(.headline.bold()).foregroundStyle(.white)
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Analytics
    @ViewBuilder
    private var analyticsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label(lang == "es" ? "Resumen" : "Overview", systemImage: "chart.bar.fill")
                        .font(.subheadline.weight(.semibold)).foregroundColor(.white)
                    Spacer()
                    Text(Date(), style: .date).font(.caption).foregroundStyle(.white.opacity(0.55))
                }

                let s = stats
                let tickets = s?.totalTickets ?? 0
                let totalSpent: Double? = s?.totalSpent ?? {
                    guard let avg = s?.averageTicketPrice else { return nil }
                    return Double(tickets) * avg
                }()
                let avgPerEvent: Double? = s?.avgPerEvent ?? {
                    guard let total = totalSpent else { return nil }
                    let attended = s?.attended ?? 0
                    return attended > 0 ? (total / Double(attended)) : 0
                }()

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    MetricTile(title: lang == "es" ? "Gastado" : "Total Spent",
                               value: totalSpent.map(currency) ?? "—",
                               sub: lang == "es" ? "acumulado" : "lifetime",
                               gradient: Gradient(colors: [.neonCyan.opacity(0.38), .neonCyan.opacity(0.14)]))
                    MetricTile(title: lang == "es" ? "Entradas" : "Tickets",
                               value: "\(tickets)",
                               sub: lang == "es" ? "compradas" : "purchased",
                               gradient: Gradient(colors: [.neonMint.opacity(0.40), .neonMint.opacity(0.14)]))
                    MetricTile(title: lang == "es" ? "Prom. por evento" : "Avg / Event",
                               value: avgPerEvent.map(currency) ?? "—",
                               sub: lang == "es" ? "gasto" : "spend",
                               gradient: Gradient(colors: [.neonOrange.opacity(0.40), .neonOrange.opacity(0.14)]))
                    MetricTile(title: lang == "es" ? "Prom. por ticket" : "Avg / Ticket",
                               value: (s?.averageTicketPrice).map(currency) ?? "—",
                               sub: lang == "es" ? "precio" : "price",
                               gradient: Gradient(colors: [.neonPurple.opacity(0.38), .neonPurple.opacity(0.14)]))
                }
                .redacted(reason: statsLoading ? .placeholder : [])

                AttendanceCard(
                    attended: s?.attended ?? 0,
                    upcoming: s?.attending ?? 0,
                    title: lang == "es" ? "Asistencia" : "Attendance",
                    attendedLabel: lang == "es" ? "Asistidos" : "Attended",
                    upcomingLabel: lang == "es" ? "Por asistir" : "Upcoming"
                )
                .redacted(reason: statsLoading ? .placeholder : [])

                if let name = s?.topSellerName, !name.isEmpty || (s?.mostEventName?.isEmpty == false) {
                    Divider().overlay(Color.white.opacity(0.08))
                    HStack(spacing: 12) {
                        if let name = s?.topSellerName, !name.isEmpty {
                            SellerTile(title: lang == "es" ? "Más compras a" : "Most purchased from",
                                       name: name, avatarURL: s?.topSellerAvatar)
                                .frame(maxWidth: .infinity)
                        }
                        if let ev = s?.mostEventName, !ev.isEmpty {
                            EventTile(title: lang == "es" ? "Evento más asistido" : "Most attended event",
                                      eventName: ev, coverURL: s?.mostEventCover, count: s?.topEventCount)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
        .opacity(isPrivate ? 0.6 : 1)
    }

    // MARK: - Data
    @MainActor
    private func load() async {
        loading = true
        defer { loading = false }

        if let uname = usernameOrId, !uname.isEmpty { username = uname }

        // 1) Public profile basics
        do {
            if let url = URL(string: "https://backendevent-etce.onrender.com/user/\(userId)") {
                var req = URLRequest(url: url)
                if let t = TokenManager.shared.getAccessToken() {
                    req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
                }
                req.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                    let u = try JSONDecoder().decode(PublicUserDTO.self, from: data)
                    displayName = u.displayName
                    username    = u.username
                    avatarUrl   = u.avatarUrl
                    bio         = u.bio ?? ""
                    isPrivate   = u.isPrivate
                }
            }
        } catch { /* non-fatal */ }

        // 2) If it's me, hydrate from /user/me
        if isMe, let me = try? await UserProfileAPI.getMe() {
            displayName = me.displayName ?? displayName
            username    = me.username ?? username
            bio         = me.bio ?? bio
            avatarUrl   = me.avatarUrl ?? avatarUrl
        }

        // 3) Lists / Badges
        await reloadSocial()

        // 4) Relationship (prefer v2)
        if meId > 0 && meId != userId {
            if let r = try? await SocialAPI.relationshipV2(otherId: userId) {
                isFollowing  = (r.outgoing == "ACCEPTED")
                isRequested  = (r.outgoing == "PENDING")
                isFollowedBy = (r.incoming == "ACCEPTED" || r.incoming == "PENDING")
            } else if let rel = try? await SocialAPI.relationship(meId: meId, otherId: userId) {
                isFollowing  = rel.isFollowing
                isRequested  = false
                isFollowedBy = rel.isFollowedBy
            }
        }

        // 5) Analytics
        statsLoading = true
        Task {
            defer { statsLoading = false }
            do {
                let result = try await (isMe ? PublicProfileAnalyticsAPI.me()
                                             : PublicProfileAnalyticsAPI.user(userId))
                await MainActor.run { stats = result }
            } catch { /* optional */ }
        }

        // 6) Authoritative counts (NEW)
        if let live = try? await SocialAPI.fetchCounts(userId: userId) {
            counts = live
        }
    }


    @MainActor
    private func reloadSocial() async {
        do {
            async let f1 = SocialAPI.fetch(.followers(userId: userId), limit: 100)
            async let f2 = SocialAPI.fetch(.following(userId: userId), limit: 100)
            async let fr = SocialAPI.fetch(.friends(userId: userId),   limit: 100)
            async let bd = BadgesAPI.badges(userId: userId)
            async let ct = SocialAPI.fetchCounts(userId: userId)              // <-- new

            (followers, following, friends, badges) = try await (f1, f2, fr, bd)
            counts = (try? await ct) ?? counts                                // <-- assign
        } catch {
            message = lang == "es" ? "No se pudo cargar las listas." : "Failed to load lists."
        }
    }

    @MainActor
    private func toggleFollow() {
        guard !workingFollow, meId > 0 else { return }
        workingFollow = true

        Task {
            defer { workingFollow = false }
            do {
                if isFollowing || isRequested {
                    // --- Unfollow branch ---
                    try await SocialAPI.unfollow(userId: userId)
                    isFollowing = false
                    isRequested = false
                    SocialBus.post(.init(kind: .unfollowed(userId: userId)))

                    // refresh local state
                    await reloadSocial()

                    // also pull authoritative counts
                    if let live = try? await SocialAPI.fetchCounts(userId: userId) {
                        counts = live
                    }

                } else {
                    // --- Follow branch ---
                    try await SocialAPI.follow(userId: userId)
                    isRequested = true // optimistic until accepted
                    SocialBus.post(.init(kind: .followed(userId: userId)))

                    if let r = try? await SocialAPI.relationshipV2(otherId: userId) {
                        isFollowing = (r.outgoing == "ACCEPTED")
                        isRequested = (r.outgoing == "PENDING")
                    }

                    // refresh local state
                    await reloadSocial()

                    // also pull authoritative counts
                    if let live = try? await SocialAPI.fetchCounts(userId: userId) {
                        counts = live
                    }
                }

            } catch {
                message = lang == "es"
                    ? "Acción fallida."
                    : "Action failed."
            }
        }
    }



    // MARK: - Utils
    private func currency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.currencySymbol = "$"
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }
}

// MARK: - Reusable tiles (same as before)

private struct MetricTile: View {
    let title: String, value: String, sub: String
    let gradient: Gradient
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
            Text(value).font(.title3.bold()).foregroundStyle(.white)
            Text(sub).font(.caption2).foregroundStyle(.white.opacity(0.65))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(gradient: gradient, startPoint: .topLeading, endPoint: .bottomTrailing).opacity(0.95))
        .background(.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.10), lineWidth: 1))
    }
}

private struct AttendanceCard: View {
    let attended: Int, upcoming: Int
    let title: String, attendedLabel: String, upcomingLabel: String

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
                    valueChip(color: .neonMint, text: attendedLabel, value: attended)
                    valueChip(color: .neonOrange, text: upcomingLabel, value: upcoming)
                }
            }

            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.16))
                GeometryReader { geo in
                    let w = geo.size.width
                    Capsule().fill(LinearGradient(colors: [.neonMint, .neonMint.opacity(0.7)],
                                                  startPoint: .leading, endPoint: .trailing))
                        .frame(width: w * attendedRatio)
                    Capsule().fill(LinearGradient(colors: [.neonOrange, .neonOrange.opacity(0.7)],
                                                  startPoint: .leading, endPoint: .trailing))
                        .frame(width: w * upcomingRatio)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .frame(height: 14)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 1))

            HStack {
                legendDot(color: .neonMint, text: "\(attendedLabel) • \(attendedPctText)")
                Spacer()
                legendDot(color: .neonOrange, text: "\(upcomingLabel) • \(upcomingPctText)")
            }
            .font(.caption2)
            .foregroundColor(.white.opacity(0.95))
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
        HStack(spacing: 6) { Circle().fill(color).frame(width: 8, height: 8); Text(text) }
    }
}

private struct SellerTile: View {
    let title: String, name: String, avatarURL: String?
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let avatarURL, let url = URL(string: avatarURL) {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.18) }
                    .frame(width: 40, height: 40).clipShape(Circle())
                    .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 1))
            } else {
                Circle().fill(Color.white.opacity(0.18))
                    .frame(width: 40, height: 40)
                    .overlay(Image(systemName: "person.fill").foregroundColor(.white.opacity(0.9)))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.9))
                Text(name).font(.headline.weight(.semibold)).foregroundColor(.white)
                    .lineLimit(2).minimumScaleFactor(0.75).allowsTightening(true)
            }
        }
        .padding(12)
        .background(LinearGradient(colors: [.neonCyan.opacity(0.28), .neonMint.opacity(0.20)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .background(Color.white.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.18), lineWidth: 1))
    }
}

private struct EventTile: View {
    let title: String, eventName: String, coverURL: String?, count: Int?
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let coverURL, let url = URL(string: coverURL) {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.18) }
                    .frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.22), lineWidth: 1))
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.18))
                    .frame(width: 40, height: 40)
                    .overlay(Image(systemName: "ticket.fill").foregroundColor(.white.opacity(0.9)))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.9))
                Text(eventName + (count.map { " ×\($0)" } ?? ""))
                    .font(.headline.weight(.semibold)).foregroundColor(.white)
                    .lineLimit(2).minimumScaleFactor(0.75).allowsTightening(true)
            }
        }
        .padding(12)
        .background(LinearGradient(colors: [.neonPurple.opacity(0.28), .neonCyan.opacity(0.20)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .background(Color.white.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.18), lineWidth: 1))
    }
}

// Drop-in replacement for Avatar
private struct AvatarView: View {
    let url: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let resolved = resolveURL(from: url) {
                AsyncImage(url: resolved) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().frame(width: size, height: size)
                    case .success(let img):
                        img.resizable().scaledToFill()
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
    }

    private var placeholder: some View {
        Circle().fill(Color.white.opacity(0.15))
            .overlay(Image(systemName: "person.fill").foregroundColor(.white))
    }

    private func resolveURL(from raw: String?) -> URL? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }

        // Already absolute?
        if s.hasPrefix("https://") || s.hasPrefix("http://") {
            // Prefer https if possible (ATS)
            if s.hasPrefix("http://") {
                s = "https://" + s.dropFirst("http://".count)
            }
            return URL(string: s)
        }

        // Protocol-relative
        if s.hasPrefix("//") {
            return URL(string: "https:\(s)")
        }

        // Hostless/relative path
        if s.hasPrefix("/") {
            return URL(string: "https://backendevent-etce.onrender.com\(s)")
        }

        // Bare host (e.g. res.cloudinary.com/…)
        if s.contains(".") && !s.contains("://") {
            return URL(string: "https://\(s)")
        }

        // Data URLs or anything else
        return URL(string: s)
    }
}

