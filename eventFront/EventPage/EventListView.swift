import SwiftUI
import Foundation
import UIKit

// MARK: - Config
private let BASE_URL = "https://backendevent-etce.onrender.com"

// MARK: - Local URL normalizer (scoped to avoid any duplicate global names)
@inline(__always)
private func normalizeAvatarURL(_ raw: String?) -> URL? {
    guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
    if s.hasPrefix("http://") { s = "https://" + s.dropFirst("http://".count) }
    if s.hasPrefix("https://") { return URL(string: s) }
    if s.hasPrefix("//")      { return URL(string: "https:\(s)") }
    if s.hasPrefix("/")       { return URL(string: "\(BASE_URL)\(s)") }
    if s.contains(".") && !s.contains("://") { return URL(string: "https://\(s)") }
    return URL(string: s)
}

// MARK: - Date parsing & pretty formatting
private func parseEventDate(_ s: String) -> Date? {
    struct DF {
        static let plain: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = .current
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            return f
        }()
        static let millis: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = .current
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
            return f
        }()
        static let zulu: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(secondsFromGMT: 0)
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
            return f
        }()
    }
    if let d = DF.plain.date(from: s) { return d }
    if let d = DF.millis.date(from: s) { return d }
    if s.hasSuffix("Z"), let d = DF.zulu.date(from: s) { return d }
    return nil
}

private func prettyEventDate(_ iso: String, lang: String) -> String {
    guard let d = parseEventDate(iso) else { return iso }

    let isSpanish = (lang == "es")
    let loc = Locale(identifier: isSpanish ? "es_ES" : "en_US")
    let cal = Calendar.current

    let timeFmt = DateFormatter()
    timeFmt.locale = loc
    timeFmt.timeStyle = .short
    timeFmt.dateStyle = .none

    if cal.isDateInToday(d) {
        return (isSpanish ? "Hoy" : "Today") + " • " + timeFmt.string(from: d)
    }
    if cal.isDateInTomorrow(d) {
        return (isSpanish ? "Mañana" : "Tomorrow") + " • " + timeFmt.string(from: d)
    }

    let dateFmt = DateFormatter()
    dateFmt.locale = loc
    // EEE = Tue, MMM d = Sep 9 (localized automatically)
    dateFmt.setLocalizedDateFormatFromTemplate(
        cal.isDate(d, equalTo: Date(), toGranularity: .year) ? "EEE MMM d" : "EEE MMM d yyyy"
    )

    return dateFmt.string(from: d) + " • " + timeFmt.string(from: d)
}


// MARK: - Minimal auth image loader (keeps initials visible while loading)
private struct AuthImager: View {
    let url: URL
    let token: String?

    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var failed = false

    var body: some View {
        Group {
            if let ui = image {
                Image(uiImage: ui).resizable()
            } else if isLoading {
                EmptyView() // leave initials visible behind
            } else if failed {
                EmptyView()
            } else {
                Color.clear.onAppear(perform: load)
            }
        }
    }

    private func load() {
        isLoading = true
        var req = URLRequest(url: url)
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.setValue("*/*", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: req) { data, resp, _ in
            var out: UIImage? = nil
            var ok = false
            if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
               let data, let ui = UIImage(data: data) {
                out = ui; ok = true
            }
            DispatchQueue.main.async {
                image = out
                failed = !ok
                isLoading = false
            }
        }.resume()
    }
}

// MARK: - Avatar with fallback lookup (uses id/username if url missing)
private struct AvatarThumb: View {
    let userId: Int
    let username: String
    let url: String?
    let size: CGFloat
    let fallbackInitials: String

    @State private var fetchedURL: URL? = nil
    @State private var isFetching = false

    var body: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.10))
            Text(fallbackInitials)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundColor(.white.opacity(0.92))
                .minimumScaleFactor(0.5)

            if let final = normalizedURL {
                if needsAuth(final) {
                    let token = TokenManager.shared.getAccessToken()
                    AuthImager(url: final, token: token)
                        .id((token ?? "") + "|" + final.absoluteString)
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                } else {
                    AsyncImage(url: final) { phase in
                        if case .success(let img) = phase {
                            img.resizable()
                                .scaledToFill()
                                .frame(width: size, height: size)
                                .clipShape(Circle())
                        }
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
        .task {
            // If list didn’t deliver a usable URL, fall back to fetching profile
            if normalizedURL == nil && !isFetching {
                isFetching = true
                fetchedURL = await fetchAvatarURL(userId: userId, username: username)
                isFetching = false
            }
        }
    }

    private var normalizedURL: URL? {
        if let fetchedURL { return fetchedURL }
        return normalizeAvatarURL(url)
    }

    private func needsAuth(_ u: URL) -> Bool {
        guard let host = u.host?.lowercased() else { return false }
        return host.contains("backendevent-etce") || host.hasSuffix("onrender.com")
    }

    /// Try a few likely endpoints to fetch a user's avatar if search payload omitted it.
    /// Try backend endpoints that actually exist to fetch a user's avatar if search payload omitted it.
    private func fetchAvatarURL(userId: Int, username: String) async -> URL? {
        guard let token = TokenManager.shared.getAccessToken() else { return nil }

        // ✅ Use the real routes from your backend:
        // - GET /user/{id}
        // - GET /user/by-username/{username}
        let paths: [String] = [
            "/user/\(userId)",
            "/user/by-username/\(username)"
        ]

        for p in paths {
            guard let url = URL(string: BASE_URL + p) else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Accept")

            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { continue }

                // This will find "avatarUrl" from PublicUserResponse
                if let urlStr = extractAvatar(from: data), let u = normalizeAvatarURL(urlStr) {
                    return u
                }
            } catch {
                // try next candidate
                continue
            }
        }
        return nil
    }
    
    // MARK: - Shared avatar extractor
    

    /// Tolerant avatar extractor from a user JSON blob (flat or nested).
    private func extractAvatar(from data: Data) -> String? {
        // Try common shapes
        if let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            // 1) direct string keys
            let stringKeys = [
                "avatarUrl","avatarURL","avatar_url",
                "imageUrl","image_url",
                "photo","picture",
                "profileImageUrl","profile_image_url",
                "profilePic","profile_pic",
                "avatarPath","avatarThumb","avatarSmall"
            ]
            for k in stringKeys {
                if let s = dict[k] as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return s }
            }
            // 2) nested objects (avatar / profileImage / profile / images)
            for nk in ["avatar","profileImage","profile","images"] {
                if let n = dict[nk] as? [String: Any] {
                    for kk in ["secure_url","secureUrl","url","path","src"] {
                        if let s = n[kk] as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return s }
                    }
                    if let file = n["file"] as? [String: Any] {
                        for kk in ["secure_url","secureUrl","url","path","src"] {
                            if let s = file[kk] as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return s }
                        }
                    }
                }
            }
        }
        return nil
    }
}

// MARK: - EventListView
struct EventListView: View {
    @AppStorage("selectedLanguage") var lang: String = "en"
    @Binding var events: [Event]
    @Binding var selectedTab: Int
    @Binding var deepLinkEventId: String?

    @State private var currentPage = 0
    @State private var isLoading = false
    @State private var hasMore = true
    @State private var previousTab = 0

    @EnvironmentObject var userSession: UserSession

    @State private var selectedCity: CitySelection? = nil
    @State private var selectedEvent: Event? = nil
    @State private var showDetail = false

    @State private var showDirectChats = false
    @State private var reunionToRsvp: Event? = nil
    @State private var eventNotFound = false
    @State private var eventNotFoundMsg = ""

    @State private var searchText: String = ""
    @State private var showRequests = false
    @State private var showInitialLoading = true
    
    @State private var unreadTotal: Int = 0


    // Search
    @State private var isSearchActive = false
    @State private var recentQueries: [String] = []
    @State private var userResults: [UserLite] = []
    @State private var isSearchingUsers = false
    @State private var debounceWork: DispatchWorkItem?
    @Namespace private var searchNS
    @FocusState private var isSearchFocused: Bool
    private var hasQuery: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    // Profile navigation
    @State private var profileNav: ProfileNav?

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                if eventNotFound { eventNotFoundBanner }

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Header
                        HStack(alignment: .center, spacing: 0) {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(getGreeting(lang: lang) + ",")
                                    .font(.system(size: 17, weight: .regular))
                                    .foregroundColor(.white)
                                Text(userSession.firstName.capitalized)
                                    .font(.system(size: 29, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .padding(.vertical, 8)

                            Spacer()

                            HStack(spacing: 14) {
                                Button(action: { showRequests = true }) {
                                    Circle()
                                        .fill(Color.white.opacity(0.18))
                                        .frame(width: 38, height: 38)
                                        .overlay(Image(systemName: "bell").font(.system(size: 18, weight: .medium))
                                            .foregroundColor(.gold))
                                }
                                Button(action: { showDirectChats = true }) {
                                    ZStack(alignment: .topTrailing) {
                                        Circle()
                                            .fill(Color.white.opacity(0.18))
                                            .frame(width: 38, height: 38)
                                            .overlay(
                                                Image(systemName: "message.circle")
                                                    .font(.system(size: 20, weight: .medium))
                                                    .foregroundColor(.gold)
                                            )

                                        if unreadTotal > 0 {
                                            BadgeCount(count: unreadTotal)
                                                .offset(x: 6, y: -6)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 14)

                        // Search bar (base)
                        searching

                        if isLoading || showInitialLoading {
                            loadingView
                        } else {
                            // Events
                            VStack(alignment: .leading, spacing: 12) {
                                Text(lang == "es" ? "Eventos" : "Events")
                                    .font(.title2.bold())
                                    .foregroundColor(.gold)
                                    .padding(.horizontal)

                                if upcomingEvents.isEmpty {
                                    emptyEventsView
                                } else {
                                    paginatedEventsTabView
                                }
                            }

                            // Cities
                            VStack(alignment: .leading, spacing: 12) {
                                Text(lang == "es" ? "Ciudad" : "Cities")
                                    .font(.title2.bold())
                                    .foregroundColor(.gold)
                                    .padding(.horizontal)

                                if uniqueCities.isEmpty {
                                    emptyCitiesView
                                } else {
                                    citiesScrollView
                                }
                            }

                            if upcomingEvents.count > 1 {
                                Spacer(minLength: 60)
                            }
                        }
                    }
                    .padding(.top, 20)
                }
                .scrollDisabled(isSearchActive)
            }
            // Full-screen search overlay
            .overlay(alignment: .top) {
                if isSearchActive {
                    searchOverlayFullScreen
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal:   .move(edge: .top).combined(with: .opacity)
                            )
                        )
                        .zIndex(1000)
                }
            }
            .animation(.interactiveSpring(response: 0.42, dampingFraction: 0.88, blendDuration: 0.18), value: isSearchActive)
            .refreshable { fetchEvents(reset: true) }
            .onAppear {
                recentQueries = UserDefaults.standard.stringArray(forKey: "wknd_recent_queries") ?? []
                if events.isEmpty {
                    withAnimation { showInitialLoading = true }
                    fetchEvents(reset: true)
                } else {
                    withAnimation { showInitialLoading = false }
                }
                Task { await refreshUnreadBadge() }        // ⟵ NEW
            }
            .onChange(of: selectedTab) { newTab in
                if newTab == 0 && previousTab != 0 { fetchEvents(reset: true) }
                previousTab = newTab
            }
            .onChange(of: deepLinkEventId) { newValue in
                if let idStr = newValue, let id = Int(idStr), let event = events.first(where: { $0.id == id }) {
                    selectedEvent = event
                    showDetail = true
                } else if newValue != nil {
                    eventNotFoundMsg = "Event not found or has been deleted."
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { eventNotFound = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) { eventNotFound = false }
                        deepLinkEventId = nil
                    }
                }
            }
            .sheet(isPresented: $showRequests) { NavigationStack { NotificationsView().navigationTitle("Notifications") } }
            .sheet(isPresented: $showDetail, onDismiss: { deepLinkEventId = nil }) {
                if let event = selectedEvent {
                    EventDetailView(event: event, allEvents: $events)
                }
            }
            .fullScreenCover(isPresented: $showDirectChats) {
                NavigationStack { ChatListView().environmentObject(userSession) }
            }
            .onChange(of: showDirectChats) { isShowing in
                if !isShowing {
                    Task { await refreshUnreadBadge() }    // ⟵ NEW
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                Task { await refreshUnreadBadge() }        // ⟵ NEW
            }
            .sheet(item: $reunionToRsvp) { reunion in
                ReunionRSVPView(
                    eventId: reunion.id,
                    title: reunion.title,
                    location: reunion.location,
                    dateTime: reunion.dateTime,
                    onComplete: { reunionToRsvp = nil }
                )
            }
            .sheet(item: $selectedEvent) { event in
                EventDetailView(event: event, allEvents: $events)
            }
            .navigationDestination(item: $selectedCity) { selection in
                NavigationStack { CityEventsView(city: selection.name, allEvents: $events).environmentObject(userSession) }
            }
            .navigationDestination(item: $profileNav) { nav in
                PublicProfileView(userId: nav.id, usernameOrId: nav.username)
                    .environmentObject(userSession)
            }
        }
    }

    // MARK: - Full-screen Search Overlay
    private var searchOverlayFullScreen: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.white.opacity(0.75))
                    .font(.system(size: 18, weight: .medium))

                TextField(lang == "es" ? "Buscar eventos, lugares y personas…" : "Search events, places & people…",
                          text: $searchText)
                    .font(.system(size: 17))
                    .foregroundColor(.white.opacity(0.98))
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .submitLabel(.search)
                    .focused($isSearchFocused)
                    .onSubmit { commitSearch() }

                Button {
                    withAnimation {
                        if hasQuery {
                            searchText = ""
                            userResults = []
                        } else {
                            closeSearch()
                        }
                    }
                } label: {
                    Image(systemName: hasQuery ? "xmark.circle.fill" : "xmark")
                        .font(.system(size: hasQuery ? 18 : 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 4)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.20), lineWidth: 1.0))
                    .shadow(color: .black.opacity(0.35), radius: 22, x: 0, y: 14)
            )
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .matchedGeometryEffect(id: "searchbar", in: searchNS, isSource: isSearchActive)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    searchPanelContent
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black.ignoresSafeArea())
        .onAppear { DispatchQueue.main.async { isSearchFocused = true } }
    }

    // MARK: - Base Search Bar
    var searching: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.white.opacity(0.75))
                    .font(.system(size: 18, weight: .medium))

                TextField(lang == "es" ? "Buscar eventos, lugares y personas…" : "Search events, places & people…",
                          text: $searchText,
                          onEditingChanged: { _ in withAnimation { isSearchActive = true } })
                    .font(.system(size: 17))
                    .foregroundColor(.white.opacity(0.98))
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .submitLabel(.search)
                    .onSubmit { commitSearch() }

                if isSearchActive {
                    Button {
                        withAnimation {
                            if hasQuery {
                                searchText = ""
                                userResults = []
                            } else {
                                closeSearch()
                            }
                        }
                    } label: {
                        Image(systemName: hasQuery ? "xmark.circle.fill" : "xmark")
                            .font(.system(size: hasQuery ? 18 : 16, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 4)
                    }
                    .transition(.opacity.combined(with: .scale))
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 1.0))
                    .shadow(color: .black.opacity(0.25), radius: 18, x: 0, y: 9)
            )
            .padding(.horizontal, 24)
            .matchedGeometryEffect(id: "searchbar", in: searchNS, isSource: !isSearchActive)
            .disabled(isSearchActive)
        }
        .onChange(of: searchText) { newValue in scheduleUserLookup(for: newValue) }
        .onChange(of: isSearchActive) { active in isSearchFocused = active }
        .opacity(isSearchActive ? 0 : 1)
    }

    // MARK: - Search Content Sections
    private var searchPanelContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !hasQuery {
                Text(lang == "es" ? "Sugerencias" : "Suggestions")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.95))
                    .padding(.top, 8)

                recentChips

                HStack(spacing: 8) {
                    tagChip("Events", system: "ticket.fill")
                    tagChip("Cities", system: "building.2.crop.circle")
                    tagChip("People", system: "person.crop.circle")
                }
                .padding(.top, 2)
            } else {
                // EVENTS
                let evts = filteredEvents(query: searchText)
                if !evts.isEmpty {
                    sectionHeader(title: lang == "es" ? "Eventos" : "Events")
                    ForEach(evts.prefix(12), id: \.id) { e in
                        Button {
                            selectedEvent = e
                            closeSearch()
                        } label: { EventRow(event: e, lang: lang) }
                        .buttonStyle(.plain)
                    }
                }

                // CITIES
                let cities = filteredCities(query: searchText)
                if !cities.isEmpty {
                    sectionHeader(title: lang == "es" ? "Ciudades" : "Cities")
                    ForEach(cities.prefix(12), id: \.self) { c in
                        Button {
                            selectedCity = CitySelection(name: c)
                            closeSearch()
                        } label: { CityRow(city: c) }
                        .buttonStyle(.plain)
                    }
                }

                // PEOPLE
                sectionHeader(title: lang == "es" ? "Personas" : "People")
                if isSearchingUsers {
                    HStack(spacing: 8) {
                        ProgressView().tint(.white)
                        Text(lang == "es" ? "Buscando usuarios…" : "Searching users…")
                            .foregroundColor(.white.opacity(0.8))
                            .font(.subheadline)
                    }
                    .padding(.vertical, 6)
                } else if userResults.isEmpty {
                    Text(lang == "es" ? "No se encontraron usuarios" : "No users found")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.subheadline)
                        .padding(.vertical, 4)
                } else {
                    ForEach(userResults.prefix(12)) { u in
                        Button {
                            profileNav = ProfileNav(id: u.id, username: u.username)
                            closeSearch()
                        } label: { UserRow(user: u) }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Helpers & UI bits

    private func closeSearch() {
        isSearchFocused = false
        withAnimation(.interactiveSpring(response: 0.42, dampingFraction: 0.88, blendDuration: 0.18)) {
            isSearchActive = false
            dismissKeyboard()
        }
        commitSearch()
    }

    private func commitSearch() {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        if let i = recentQueries.firstIndex(of: q) { recentQueries.remove(at: i) }
        recentQueries.insert(q, at: 0)
        recentQueries = Array(recentQueries.prefix(6))
        UserDefaults.standard.set(recentQueries, forKey: "wknd_recent_queries")
    }

    private func filteredEvents(query: String) -> [Event] {
        let q = query.lowercased()
        return upcomingEvents.filter { e in
            e.title.lowercased().contains(q) ||
            e.location.lowercased().contains(q) ||
            (e.description.lowercased().contains(q) ?? false)
        }
    }

    private func filteredCities(query: String) -> [String] {
        let q = query.lowercased()
        return uniqueCities.filter { $0.lowercased().contains(q) }
    }

    private var recentChips: some View {
        let recents = recentQueries.isEmpty
        ? ["Chicago", "Tonight", "Afterparty", "Caracas", "DJ"]
        : recentQueries

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(recents, id: \.self) { r in
                    Button {
                        withAnimation { searchText = r }
                    } label: {
                        Text(r)
                            .font(.subheadline)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(Color.white.opacity(0.10)))
                            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func tagChip(_ label: String, system: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: system)
            Text(label).font(.footnote.bold())
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(Color.neonMint.opacity(0.18)))
        .overlay(Capsule().stroke(Color.neonMint.opacity(0.55), lineWidth: 1))
    }

    private func sectionHeader(title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.bold())
            .foregroundColor(.white.opacity(0.6))
            .padding(.top, 10)
    }

    // MARK: Rows

    private struct EventRow: View {
        let event: Event
        let lang: String
        var body: some View {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 44, height: 44)
                    .overlay(Image(systemName: "ticket.fill").foregroundColor(.white.opacity(0.9)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.title)
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    Text(event.location)
                        .foregroundColor(.white.opacity(0.7))
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(prettyEventDate(event.dateTime, lang: lang))
                        .foregroundColor(.white.opacity(0.55))
                        .font(.caption)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundColor(.white.opacity(0.45))
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
        }
    }

    private struct CityRow: View {
        let city: String
        var body: some View {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 44, height: 44)
                    .overlay(Image(systemName: "building.2.crop.circle").foregroundColor(.white.opacity(0.9)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(city)
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .semibold))
                    Text("City")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.caption)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundColor(.white.opacity(0.45))
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
        }
    }

    private struct UserRow: View {
        let user: UserLite
        var body: some View {
            HStack(spacing: 12) {
                // Pass id/username to AvatarThumb so it can fallback fetch if url is missing
                AvatarThumb(userId: user.id, username: user.username, url: user.avatarUrl, size: 44, fallbackInitials: user.initials)

                VStack(alignment: .leading, spacing: 3) {
                    Text(user.displayNameOrUsername)
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    Text("@\(user.username)")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.subheadline)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.white.opacity(0.45))
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
        }
    }

    // MARK: - Model used for search results (tolerant decode in strict path)
    private struct AvatarObj: Decodable { let url: String? }

    struct UserLite: Identifiable, Hashable, Codable {
        let id: Int
        let username: String
        let displayName: String?
        let avatarUrl: String?

        init(id: Int, username: String, displayName: String? = nil, avatarUrl: String? = nil) {
            self.id = id
            self.username = username
            self.displayName = displayName
            self.avatarUrl = avatarUrl
        }

        init(from decoder: Decoder) throws {
            // Decode to a dictionary of [String: String]
            let container = try decoder.singleValueContainer()
            let raw = try container.decode([String: String?].self).compactMapValues { $0 }

            // id
            let id = Int(raw["id"] ?? "") ?? 0

            // username
            let uname = raw["username"] ?? raw["handle"] ?? raw["userName"] ?? "user\(id)"

            // displayName
            let display = raw["displayName"] ?? raw["name"]

            // avatar
            let rawAvatar = EventListView.extractAvatarString(from: raw as [String: Any])
            let norm = normalizeAvatarURL(rawAvatar)?.absoluteString

            self.id = id
            self.username = uname
            self.displayName = display
            self.avatarUrl = norm
        }



        var initials: String {
            let base = (displayName?.isEmpty == false ? displayName! : username)
            let parts = base.split(separator: " ")
            let first = parts.first?.first.map(String.init) ?? String(base.prefix(1))
            let last  = parts.dropFirst().first?.first.map(String.init) ?? ""
            return (first + last).uppercased()
        }

        var displayNameOrUsername: String {
            if let d = displayName, !d.isEmpty { return d }
            return username
        }
    }

    private func refreshUnreadBadge() async {
        ChatAPI.shared.setTokenProvider { TokenManager.shared.getAccessToken() }
        do {
            let rooms = try await ChatAPI.shared.myRooms()
            let total = rooms.reduce(0) { $0 + max(0, $1.unreadCount) }
            await MainActor.run { self.unreadTotal = total }
        } catch {
            // Ignore silently; badge will just not update this cycle
        }
    }

    // MARK: - Debounced search
    private func scheduleUserLookup(for text: String) {
        debounceWork?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { userResults = []; return }
        let work = DispatchWorkItem { [trimmed] in lookupUsersRemote(query: trimmed) }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    // MARK: - Tolerant users decode (works for many shapes; fast to type-check)
    private func decodeSearchUsers(_ data: Data) -> [UserLite] {
        // Try direct decode first
        if let arr = try? JSONDecoder().decode([UserLite].self, from: data) { return arr }

        // Try wrappers
        struct Wrap<T: Decodable>: Decodable {
            let data: [T]?; let items: [T]?; let content: [T]?; let results: [T]?; let users: [T]?
            let followers: [T]?; let following: [T]?; let friends: [T]?
            struct Page<U: Decodable>: Decodable { let content: [U]? }
            let page: Page<T>?
        }
        if let w = try? JSONDecoder().decode(Wrap<UserLite>.self, from: data) {
            if let picked = [w.data,w.items,w.content,w.results,w.users,w.followers,w.following,w.friends,w.page?.content]
                .compactMap({ $0 }).first { return picked }
        }

        // Manual fallback using JSONSerialization
        if let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
            return arr.compactMap(mapLooseUserDict)
        }
        if let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            for k in ["data","items","content","results","followers","following","friends","users"] {
                if let arr = root[k] as? [[String: Any]] { return arr.compactMap(mapLooseUserDict) }
            }
            if let page = root["page"] as? [String: Any],
               let arr = page["content"] as? [[String: Any]] {
                return arr.compactMap(mapLooseUserDict)
            }
        }
        return []
    }


    private func mapLooseUserDict(_ d: [String: Any]) -> UserLite? {
        let id = (d["id"] as? Int)
              ?? Int(d["id"] as? String ?? "")
              ?? (d["id"] as? Double).map { Int($0) }
              ?? 0

        let uname = (d["username"] as? String)
                 ?? (d["handle"] as? String)
                 ?? (d["userName"] as? String)
                 ?? "user\(id)"

        let display = (d["displayName"] as? String)
                   ?? (d["name"] as? String)

        let rawAvatar = EventListView.extractAvatarString(from: d)
        let norm = normalizeAvatarURL(rawAvatar)?.absoluteString

        return UserLite(id: id, username: uname, displayName: display, avatarUrl: norm)
    }
    
    static func extractAvatarString(from dict: [String: Any]) -> String? {
        let stringKeys = [
            "avatarUrl","avatarURL","avatar_url",
            "imageUrl","image_url",
            "photo","picture",
            "profileImageUrl","profile_image_url",
            "profilePic","profile_pic",
            "avatarPath","avatarThumb","avatarSmall"
        ]
        for k in stringKeys {
            if let s = dict[k] as? String,
               !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return s
            }
        }

        // Nested objects: avatar, profileImage, profile, images
        for nk in ["avatar","profileImage","profile","images"] {
            if let nested = dict[nk] as? [String: Any] {
                for kk in ["secure_url","secureUrl","url","path","src"] {
                    if let s = nested[kk] as? String,
                       !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return s
                    }
                }
                if let file = nested["file"] as? [String: Any] {
                    for kk in ["secure_url","secureUrl","url","path","src"] {
                        if let s = file[kk] as? String,
                           !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            return s
                        }
                    }
                }
            }
        }
        return nil
    }

    private func lookupUsersRemote(query: String) {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "\(BASE_URL)/search/users?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)") else {
            userResults = []; return
        }

        isSearchingUsers = true
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: req) { data, _, _ in
            DispatchQueue.main.async {
                self.isSearchingUsers = false
                guard let data = data else { self.userResults = []; return }
                self.userResults = self.decodeSearchUsers(data)
            }
        }.resume()
    }

    private func dismissKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    // MARK: - Other Sections (unchanged from your version)

    var emptyEventsView: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.exclamationmark").font(.system(size: 50)).foregroundColor(.white.opacity(0.5))
            Text(lang == "es" ? "No hay futuros eventos": "No upcoming events").foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    var paginatedEventsTabView: some View {
        let pages = paginateEvents(upcomingEvents, itemsPerPage: 2)
        let isSingleEvent = upcomingEvents.count == 1

        return VStack(spacing: 0) {
            TabView {
                ForEach(pages.indices, id: \.self) { index in
                    let page = pages[index]
                    VStack(spacing: isSingleEvent ? 20 : 10) {
                        ForEach(page, id: \.id) { event in
                            EventCardMini(event: event)
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(14)
                                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
                                .onTapGesture { selectedEvent = event }
                        }
                    }
                    .frame(width: UIScreen.main.bounds.width - 40)
                    .padding(.vertical, isSingleEvent ? 10 : 8)
                }
            }
            .frame(height: isSingleEvent ? 170 : 280)
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
            .animation(.easeInOut(duration: 0.3), value: upcomingEvents)
            .padding(.horizontal)
        }
    }

    var emptyCitiesView: some View {
        VStack(spacing: 10) {
            Image(systemName: "building.2.crop.circle").font(.system(size: 50)).foregroundColor(.white.opacity(0.5))
            Text(lang == "es" ? "No hay ciudades encontradas" : "No cities found").foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    var citiesScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(uniqueCities, id: \.self) { city in
                    CityCard(city: city).onTapGesture { selectedCity = CitySelection(name: city) }
                }
            }
            .padding(.horizontal)
        }
    }

    private var eventNotFoundBanner: some View {
        VStack {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.yellow)
                Text(eventNotFoundMsg).foregroundColor(.white).bold()
                Spacer()
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.red.opacity(0.92)))
            .padding(.horizontal)
            .transition(.move(edge: .top).combined(with: .opacity))
            .zIndex(100)
            Spacer(minLength: 8)
        }
    }

    var loadingView: some View {
        ZStack { Color.clear; ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).scaleEffect(1.3) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var upcomingEvents: [Event] {
        let now = Date()
        return events.filter {
            guard let d = parseEventDate($0.dateTime) else { return false }
            return d >= now && isReunionVisible($0, for: userSession)
        }
    }

    var uniqueCities: [String] {
        let cities = upcomingEvents.map { $0.location }
        return Array(Set(cities)).filter { !$0.isEmpty }.sorted()
    }

    func paginateEvents(_ events: [Event], itemsPerPage: Int) -> [[Event]] {
        var result: [[Event]] = []
        var index = 0
        while index < events.count {
            let page = Array(events[index..<min(index + itemsPerPage, events.count)])
            result.append(page)
            index += itemsPerPage
        }
        return result
    }

    func isReunionVisible(_ event: Event, for user: UserSession) -> Bool {
        guard event.type == "reunion" else { return true }
        if let ownerId = event.createdBy?.id, ownerId == user.userId { return true }
        if let ownerEmailLegacy = event.createdByEmail,
           ownerEmailLegacy.lowercased() == user.email.lowercased() { return true }
        if let guests = event.reunionGuests,
           guests.contains(where: { $0.email.lowercased() == user.email.lowercased() }) { return true }
        return false
    }

    func getGreeting(lang: String) -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        if lang == "es" {
            if hour < 12 { return "Buenos días" }
            else if hour < 18 { return "Buenas tardes" }
            else { return "Buenas noches" }
        } else {
            if hour < 12 { return "Good morning" }
            else if hour < 18 { return "Good afternoon" }
            else { return "Good evening" }
        }
    }

    private func fetchEvents(reset: Bool = false) {
        if reset {
            events.removeAll()
            currentPage = 0
            hasMore = true
        }
        guard !isLoading, hasMore else { return }
        isLoading = true
        let pageSize = 50

        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "\(BASE_URL)/events?page=\(currentPage)&size=\(pageSize)") else {
            isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async { isLoading = false }
            guard let data = data else { return }
            if let decoded = try? JSONDecoder().decode(PaginatedResponse<Event>.self, from: data) {
                DispatchQueue.main.async {
                    let existingIds = Set(events.map { $0.id })
                    let newEvents = decoded.content.filter { !existingIds.contains($0.id) }
                    events.append(contentsOf: newEvents)
                    currentPage += 1
                    hasMore = !decoded.last
                    showInitialLoading = false

                    let upcomingReunionsNeedingRsvp = decoded.content.filter {
                        guard $0.type == "reunion" else { return false }
                        let guest = ($0.reunionGuests ?? []).first { $0.email.lowercased() == userSession.email.lowercased() }
                        return guest != nil && guest?.attending == false
                    }
                    if let target = upcomingReunionsNeedingRsvp.first {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.reunionToRsvp = target }
                    }
                }
            }
        }.resume()
    }
}

// MARK: - Simple wrappers
struct CitySelection: Identifiable, Hashable { let id = UUID(); let name: String }
struct ProfileNav: Identifiable, Hashable { let id: Int; let username: String? }

// MARK: - City Card (unchanged)
struct CityCard: View {
    let city: String
    @State private var remoteImageUrl: URL? = nil
    @State private var isLoading = false

    private var assetName: String { city.replacingOccurrences(of: " ", with: "").lowercased() }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let uiImage = UIImage(named: assetName) {
                Image(uiImage: uiImage).resizable().scaledToFill().transition(.opacity)
            } else if let url = remoteImageUrl {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty: ZStack { placeholder; ProgressView().scaleEffect(1.2) }
                    case .success(let image): image.resizable().scaledToFill()
                    case .failure: placeholder
                    @unknown default: placeholder
                    }
                }
                .transition(.opacity)
            } else {
                placeholder.onAppear { if !isLoading { fetchCityImage() } }
            }

            Text(city)
                .font(.headline)
                .foregroundColor(.white)
                .padding(6)
                .background(.thinMaterial)
                .cornerRadius(10)
                .padding(8)
        }
        .frame(width: 140, height: 100)
        .clipped()
        .cornerRadius(16)
    }

    private var placeholder: some View {
        ZStack {
            Color.gray.opacity(0.22)
            Image(systemName: "photo").resizable().scaledToFit().frame(width: 40, height: 40).foregroundColor(.white.opacity(0.65))
        }
    }

    private func fetchCityImage() {
        isLoading = true
        let accessKey = "wvlseB4Qkzv5es8WtRKTnKJ09r7oQJUO4_R9wHxoSjM"
        let query = city.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? city
        let urlString = "https://api.unsplash.com/photos/random?query=\(query)&orientation=landscape&client_id=\(accessKey)"
        guard let url = URL(string: urlString) else { return }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            defer { isLoading = false }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let urls = json["urls"] as? [String: Any],
                  let imageUrlStr = urls["regular"] as? String,
                  let imageUrl = URL(string: imageUrlStr) else { return }
            DispatchQueue.main.async { self.remoteImageUrl = imageUrl }
        }.resume()
    }
}

private struct BadgeCount: View {
    let count: Int
    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.caption2.bold())
            .foregroundColor(.black)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(Color.gold)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.8), lineWidth: 1))
    }
}
