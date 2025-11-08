// eventFront/Resale/ResaleFeedView.swift
import SwiftUI
import UIKit

struct ResaleFeedView: View {
    @AppStorage("selectedLanguage") var lang: String = "en"
    @EnvironmentObject var userSession: UserSession
    @StateObject private var badge = AppBadgeStore.shared

    @State private var posts: [ResalePostDTO] = []
    @State private var myTickets: [TicketDTO] = []
    @State private var allEvents: [Event] = []

    @State private var isLoading = true
    @State private var showPostCreation = false
    @State private var showMyChats = false
    @State private var showMyListings = false

    // ADD near other @State vars:
    @State private var selectedChatDTO: ChatRoomSummaryDTO? = nil
    
    @StateObject private var postVM = PostCreationViewModel()

    @State private var selectedChatSummary: ChatRoomSummary? = nil
    @State private var selectedBuyNowPost: ResalePostDTO? = nil

    @State private var unreadCount: Int = 0
    @State private var pendingOrdersCount: Int = 0

    @State private var showToast = false
    @State private var toastText = ""

    // Deep link + session analytics
    @State private var deepLinkTargetPostId: Int? = nil
    @State private var viewedThisSession: Set<Int> = []

    // Edit price
    @State private var showEditPriceSheet = false
    @State private var editingPost: ResalePostDTO? = nil
    @State private var newPriceText: String = ""

    // Share
    @State private var shareURL: URL? = nil
    @State private var showShareSheet = false
    
    @State private var unreadTimer: Timer? = nil
    @State private var pendingTimer: Timer? = nil
    
    // how much vertical space your floating buttons occupy
    @State private var overlayTopHeight: CGFloat = 0
    private let overlayTopInset: CGFloat = 108 // tweak 96–120 to taste


    var body: some View {
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                backgroundGradient

                // Feed content sits *below* the measured buttons height
                content
                    .padding(.top, overlayTopHeight)

                // Floating buttons (measured)
                topRightControls
                    .reportTopOverlayHeight()

                if showToast {
                    ToastView(text: toastText)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            // No header at all
            .toolbar(.hidden, for: .navigationBar)
            // Receive the measured height
            .onPreferenceChange(TopOverlayHeightKey.self) { overlayTopHeight = $0 }

            // -------- your existing lifecycle & sheets below ----------
            .onAppear(perform: onAppear)
            .onReceive(NotificationCenter.default.publisher(for: .openResalePostFromLink)) { note in
                if let id = note.object as? Int {
                    deepLinkTargetPostId = id
                    openDeepLinkedPostIfReady()
                }
            }
            .onDisappear {
                unreadTimer?.invalidate(); unreadTimer = nil
                pendingTimer?.invalidate(); pendingTimer = nil
            }
            .sheet(isPresented: $showPostCreation) {
                PostCreationView(viewModel: postVM) { fetchResalePosts() }
                    .environmentObject(userSession)
            }
            .fullScreenCover(isPresented: $showMyChats) {
                ChatListView()
            }
            // …WITH this
            .fullScreenCover(item: $selectedChatDTO) { room in
                NavigationStack {
                    ChatRoomView(room: room, myUserId: Int(userSession.userId))
                }
            }
            .fullScreenCover(isPresented: $showMyListings) {
                NavigationStack {
                    MyResaleListingsView()
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button { showMyListings = false } label: {
                                    Image(systemName: "xmark.circle.fill").font(.title2)
                                }
                            }
                        }
                }
            }
            .sheet(item: $selectedBuyNowPost) { post in
                BuyNowView(
                    resalePost: post,
                    event: .constant(Event(id: post.eventId ?? -1, title: post.eventTitle ?? "Event")),
                    userEmail: userSession.email,
                    onComplete: { fetchResalePosts() }
                )
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = shareURL { ShareSheet(items: [url]) }
            }
            .sheet(isPresented: $showEditPriceSheet) {
                EditPriceSheet(
                    lang: lang,
                    priceText: $newPriceText,
                    onCancel: { showEditPriceSheet = false },
                    onSave: { saveEditedPrice() }
                )
            }
        }
    }

    // MARK: - Split out views

    private var backgroundGradient: some View {
        LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            LoadingBlock(text: lang == "es" ? "Cargando Publicaciones de Reventa..." : "Loading Resale Posts...")
        } else if posts.isEmpty {
            EmptyBlock(text: lang == "es" ? "No se encontraron entradas en reventa" : "No resale tickets found")
        } else {
            ScrollView {
                LazyVStack(spacing: 24) {
                    ForEach(posts) { post in
                        PostRow(
                            post: post,
                            userId: userSession.userId,
                            // REPLACE the old onMessage with:
                            onMessage: { Task { await openResaleChat(for: post) } },
                            onBuyNow: { selectedBuyNowPost = post },
                            onEditPrice: {
                                editingPost = post
                                newPriceText = String(format: "%.2f", post.price ?? 0)
                                showEditPriceSheet = true
                            },
                            onTogglePause: { togglePause(post) },
                            onShare: {
                                fetchDeepLink(post.id) { url in
                                    if let url = url {
                                        shareURL = url; showShareSheet = true
                                    } else {
                                        showErrorToast(lang == "es" ? "No se pudo generar enlace." : "Couldn't generate link.")
                                    }
                                }
                            },
                            onAppear: {
                                if !viewedThisSession.contains(post.id) {
                                    viewedThisSession.insert(post.id)
                                    trackView(post.id)
                                }
                            }
                        )
                    }
                }
                .padding()
            }
        }
    }

    private var topRightControls: some View {
        HStack(spacing: 14) {
            // My Listings
            Button { showMyListings = true } label: {
                BadgeIcon(systemName: "doc.richtext", badge: pendingOrdersCount, badgeColor: .gold, baseTint: .white)
            }

            // Chats
            Button { showMyChats = true } label: {
                BadgeIcon(systemName: "bubble.left.and.bubble.right.fill", badge: unreadCount, badgeColor: .red, baseTint: .white)
            }

            let eligibleNow = eligibleTicketsForResale()

            Button {
                if !eligibleNow.isEmpty {
                    postVM.tickets = eligibleNow
                    showPostCreation = true
                } else {
                    showErrorToast(lang == "es"
                        ? "Necesitas una entrada elegible para publicar en reventa."
                        : "You need an eligible ticket to list for resale.")
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title).foregroundColor(.gold)
                    .background(Circle().fill(Color.black.opacity(0.5)).frame(width: 44, height: 44))
            }
        }
        .padding(.top, 16)
        .padding(.trailing, 20)
    }

    // MARK: - Lifecycle
    
    
    private func eligibleTicketsForResale() -> [TicketDTO] {
        let now = Date()

        // tickets I already listed and are still active
        let myActivePostTicketIds = Set(
            posts
                .filter { $0.sellerId == userSession.userId && ($0.sold == false) && ($0.paused ?? false) == false }
                .compactMap { $0.ticketId }
        )

        return myTickets.filter { t in
            // not already listed by me
            guard !myActivePostTicketIds.contains(t.id) else { return false }

            // must be unused
            guard t.used == false else { return false }

            // must be paid/valid (either enum or boolean)
            let st = t.status.uppercased()
            let paidOrValid = t.paid || st == "PAID" || st == "VALID"
            guard paidOrValid else { return false }

            // resolve event date (prefer DTO, fallback to events list)
            guard let eventDate =
                    parseISODate(t.eventDateTime)
                    ?? allEvents.first(where: { $0.id == t.eventId })?.dateAsDate
            else { return false }

            // STRICT future: allow only tiny local clock skew (2s)
            let isFuture = eventDate >= now.addingTimeInterval(-2)
            guard isFuture else { return false }

            // We intentionally ignore server `resellEligible` here so anything
            // strictly in the future shows up for resale (1 minute or 1 year).
            return true
        }
        .sorted {
            (parseISODate($0.eventDateTime) ?? .distantFuture)
            < (parseISODate($1.eventDateTime) ?? .distantFuture)
        }
    }




    private func onAppear() {
        fetchMyTickets()
        fetchAllEvents { fetchResalePosts() }
        fetchUnreadCount()
        fetchPendingOrdersCount()
        startUnreadTimer()
        startPendingOrdersTimer()
    }

    
    private func parseISODate(_ s: String?) -> Date? {
        guard let s = s, !s.isEmpty else { return nil }
        // ISO8601 with fractional seconds
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFrac.date(from: s) { return d }
        // ISO8601 without fractional seconds
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        // Plain "yyyy-MM-dd'T'HH:mm:ss"
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.date(from: s)
    }

    private func eventDate(of t: TicketDTO, fallbackFrom events: [Event]) -> Date? {
        if let d = parseISODate(t.eventDateTime) { return d }
        if let ev = events.first(where: { $0.id == t.eventId }) { return ev.dateAsDate }
        return nil
        
    }

    // In ResaleFeedView.swift
    private func openResaleChat(for post: ResalePostDTO) async {
        // Your ids are Int64 → ChatAPI expects Int
        let resaleId = Int(post.id)
        let sellerId = Int(post.sellerId)

        // Supply JWT via TokenManager
        ChatAPI.shared.setTokenProvider { TokenManager.shared.getAccessToken() }

        do {
            let roomId = try await ChatAPI.shared.startResale(
                resalePostId: resaleId,
                sellerId: sellerId
            )

            // --- iconUrl (pick ONE that exists on your model) ---
            // If your ResalePostDTO has a single image field, use it here:
            //   let rawIcon = post.imageUrl
            //   let rawIcon = post.coverUrl
            //   let rawIcon = post.thumbnailUrl
            //
            // If you don't have any image on the post, just leave `rawIcon = nil`
            // (your chat row shows initials automatically).
            let rawIcon: String? = nil
            let icon = chatIconURLString(from: rawIcon)

            selectedChatDTO = ChatRoomSummaryDTO(
                id: roomId,
                type: .DIRECT,                    // resale is 1:1
                displayName: post.title,          // (change if your title is optional)
                iconUrl: icon,                    // ← absolute https string or nil
                lastMessagePreview: nil,
                lastMessageAt: nil,
                unreadCount: 0
            )
        } catch {
            print("openResaleChat error:", error.localizedDescription)
        }
    }

    // MARK: - Deep link

    private func openDeepLinkedPostIfReady() {
        guard let id = deepLinkTargetPostId else { return }
        if let match = posts.first(where: { $0.id == id }) {
            selectedBuyNowPost = match
            deepLinkTargetPostId = nil
        }
    }
    
    /// Returns an absolute https URL string for chat icons (uses your existing resolver)
    @inline(__always)
    private func chatIconURLString(from raw: String?) -> String? {
        resolveAvatarURL(raw)?.absoluteString
    }


    // MARK: - Filtering / Fetch

    private func filterValidResalePosts(_ posts: [ResalePostDTO]) -> [ResalePostDTO] {
        posts.filter { post in
            if let event = allEvents.first(where: { Int($0.id) == post.eventId }) {
                let inFuture = (event.dateAsDate ?? .distantPast) > Date()
                let notPaused = (post.paused ?? false) == false
                let notSold = post.sold == false
                return inFuture && notPaused && notSold
            }
            return false
        }
    }

    private func fetchResalePosts() {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/resale/available") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data else {
                DispatchQueue.main.async { self.isLoading = false }
                return
            }
            do {
                let decoded = try JSONDecoder().decode([ResalePostDTO].self, from: data)
                DispatchQueue.main.async {
                    self.posts = decoded
                    self.isLoading = false
                    openDeepLinkedPostIfReady()
                }

            } catch {
                DispatchQueue.main.async { self.isLoading = false }
            }
        }.resume()
    }

    private func fetchAllEvents(completion: @escaping () -> Void) {
        guard let token = TokenManager.shared.getAccessToken() else { completion(); return }

        func req(_ path: String, done: @escaping () -> Void) {
            guard let url = URL(string: "https://backendevent-etce.onrender.com\(path)") else { done(); return }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            URLSession.shared.dataTask(with: request) { data, _, _ in
                if let data = data,
                   let decoded = try? JSONDecoder().decode(PaginatedResponse<Event>.self, from: data) {
                    DispatchQueue.main.async { self.allEvents = decoded.content; done() }
                } else { done() }
            }.resume()
        }

        req("/events") {
            if self.allEvents.isEmpty {
                req("/api/events", done: completion)
            } else { completion() }
        }
    }


    func fetchMyTickets() {
        guard let token = TokenManager.shared.getAccessToken() else { return }

        func mergeAssign(_ arr: [TicketDTO]) {
            var seen = Set(myTickets.map(\.id))
            let merged = myTickets + arr.filter { seen.insert($0.id).inserted }
            self.myTickets = merged
        }

        func get(_ path: String, done: (() -> Void)? = nil) {
            guard let url = URL(string: "https://backendevent-etce.onrender.com" + path) else { done?(); return }
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.timeoutInterval = 8
            URLSession.shared.dataTask(with: req) { data, _, _ in
                if let data = data, let arr = try? JSONDecoder().decode([TicketDTO].self, from: data) {
                    DispatchQueue.main.async { mergeAssign(arr); done?() }
                } else { DispatchQueue.main.async { done?() } }
            }.resume()
        }

        // Try all sources; merge whatever we get
        get("/api/tickets/eligible") {
            if let email = self.userSession.email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               !email.isEmpty {
                get("/api/tickets/my?email=\(email)") {
                    get("/api/tickets/mine-all")
                }
            } else {
                get("/api/tickets/mine-all")
            }
        }
    }


    private func fetchUnreadCount() {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/chat/unread-count") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 6   // keep it short

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard error == nil, let data = data,
                  let decoded = try? JSONDecoder().decode([String: Int].self, from: data),
                  let count = decoded["unread"] else { return }

            DispatchQueue.main.async {
                withAnimation {
                    self.unreadCount = count
                    badge.unreadChats = count
                }
            }
        }.resume()
    }


    private func fetchPendingOrdersCount() {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/api/resale/manual/pending") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data else { return }
            if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                DispatchQueue.main.async {
                    withAnimation {
                        self.pendingOrdersCount = arr.count
                        badge.pendingResale = arr.count
                    }
                }
            }
        }.resume()
    }

    private func startUnreadTimer() {
        unreadTimer?.invalidate()
        unreadTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            fetchUnreadCount()
        }
    }
    private func startPendingOrdersTimer() {
        pendingTimer?.invalidate()
        pendingTimer = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { _ in
            fetchPendingOrdersCount()
        }
    }

    
    // MARK: - Seller actions

    private func saveEditedPrice() {
        guard let post = editingPost, let price = Double(newPriceText) else { return }
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/api/resale/\(post.id)/price") else { return }

        var r = URLRequest(url: url)
        r.httpMethod = "PATCH"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["price": price])

        URLSession.shared.dataTask(with: r) { _, resp, _ in
            guard let http = resp as? HTTPURLResponse else { return }
            DispatchQueue.main.async {
                if http.statusCode == 200 {
                    showEditPriceSheet = false
                    fetchResalePosts()
                } else {
                    showErrorToast("Server \(http.statusCode)")
                }
            }
        }.resume()
    }

    private func togglePause(_ post: ResalePostDTO) {
        let isPaused = (post.paused ?? false)
        let endpoint = isPaused ? "resume" : "pause"

        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/api/resale/\(post.id)/\(endpoint)") else { return }

        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: r) { _, resp, _ in
            guard let http = resp as? HTTPURLResponse else { return }
            DispatchQueue.main.async {
                if http.statusCode == 200 {
                    fetchResalePosts()
                } else {
                    showErrorToast("Server \(http.statusCode)")
                }
            }
        }.resume()
    }

    private func fetchDeepLink(_ postId: Int, completion: @escaping (URL?) -> Void) {
        guard let url = URL(string: "https://backendevent-etce.onrender.com/api/resale/deeplink/\(postId)") else {
            completion(nil); return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let map = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let s = map["url"] as? String,
                  let link = URL(string: s) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            DispatchQueue.main.async { completion(link) }
        }.resume()
    }

    // MARK: - Analytics

    private func trackView(_ postId: Int) {
        guard let url = URL(string: "https://backendevent-etce.onrender.com/api/resale/\(postId)/track/view") else { return }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        URLSession.shared.dataTask(with: r).resume()
    }

    private func trackChatOpen(_ postId: Int) {
        guard let url = URL(string: "https://backendevent-etce.onrender.com/api/resale/\(postId)/track/chat-open") else { return }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        URLSession.shared.dataTask(with: r).resume()
    }

    // MARK: - Chat entry

    private func openChat(for post: ResalePostDTO) {
        if post.sellerId == userSession.userId {
            showErrorToast(lang == "es" ? "No puedes chatear contigo mismo." : "You can’t chat with yourself.")
            return
        }

        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/chat/start") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["resalePostId": post.id]
        request.httpBody = try? JSONEncoder().encode(body)

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data else {
                DispatchQueue.main.async {
                    showErrorToast(lang == "es" ? "Sin respuesta del servidor." : "No response from server.")
                }
                return
            }

            if let errorDict = try? JSONDecoder().decode([String: String].self, from: data),
               let errorMsg = errorDict["error"] {
                DispatchQueue.main.async { showErrorToast(errorMsg) }
                return
            }

            if let decoded = try? JSONDecoder().decode(ChatRoom.self, from: data) {
                DispatchQueue.main.async {
                    self.selectedChatSummary = ChatRoomSummary(
                        chatRoomId: decoded.id,
                        resalePostId: post.id,
                        title: post.title,
                        sellerName: post.sellerName,
                        unreadMessages: 0,
                        buyerId: Int(userSession.userId),
                        eventId: Int64(post.eventId ?? -1),
                        type: "DIRECT"
                    )
                    trackChatOpen(post.id)
                }
            } else {
                DispatchQueue.main.async {
                    showErrorToast(lang == "es" ? "No se pudo abrir el chat." : "Couldn't open chat.")
                }
            }
        }.resume()
    }

    // MARK: - Toast / timers

    private func showErrorToast(_ text: String) {
        toastText = text
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { showToast = false }
        }
    }

    struct ChatRoom: Codable { var id: Int }
}

// MARK: - Small building blocks

private struct LoadingBlock: View {
    let text: String
    var body: some View {
        VStack {
            Spacer()
            ProgressView(text)
                .foregroundColor(.white)
                .progressViewStyle(CircularProgressViewStyle(tint: .gold))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EmptyBlock: View {
    let text: String
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "ticket")
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .foregroundColor(.white.opacity(0.5))
            Text(text)
                .foregroundColor(.white.opacity(0.8))
                .font(.title3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .multilineTextAlignment(.center)
    }
}

private struct ToastView: View {
    let text: String
    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle.fill").foregroundColor(.white)
                Text(text)
                    .foregroundColor(.white)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.red.opacity(0.95))
                    .shadow(radius: 12, y: 6)
            )
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 18)
    }
}

private struct BadgeIcon: View {
    let systemName: String
    let badge: Int
    let badgeColor: Color
    let baseTint: Color

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: systemName)
                .font(.title2)
                .padding(10)
                .background(Color.white.opacity(0.15))
                .clipShape(Circle())
                .foregroundColor(baseTint)

            if badge > 0 {
                Text("\(badge)")
                    .font(.caption2.bold())
                    .foregroundColor(badgeColor == .red ? .white : .black)
                    .padding(6)
                    .background(badgeColor)
                    .clipShape(Circle())
                    .offset(x: 8, y: -8)
            }
        }
    }
}

// A row wrapper so the heavy ResalePostCard + Menu is compiled in isolation
private struct PostRow: View {
    let post: ResalePostDTO
    let userId: Int64

    let onMessage: () -> Void
    let onBuyNow: () -> Void
    let onEditPrice: () -> Void
    let onTogglePause: () -> Void
    let onShare: () -> Void
    let onAppear: () -> Void

    var body: some View {
        ResalePostCard(
            post: post,
            onMessage: onMessage,
            trailingSellerMenu: {
                if post.sellerId == userId {
                    return AnyView(
                        SellerMenu(
                            isPaused: post.paused ?? false,
                            onEditPrice: onEditPrice,
                            onTogglePause: onTogglePause,
                            onShare: onShare
                        )
                    )
                } else {
                    return AnyView(EmptyView())
                }
            }, onBuyNow: onBuyNow
        )
        .onAppear(perform: onAppear)
    }
}

private struct SellerMenu: View {
    let isPaused: Bool
    let onEditPrice: () -> Void
    let onTogglePause: () -> Void
    let onShare: () -> Void
    @AppStorage("selectedLanguage") var lang: String = "en"

    var body: some View {
        Menu {
            Button(lang == "es" ? "Editar precio" : "Edit price", action: onEditPrice)

            Button(isPaused ? (lang == "es" ? "Reanudar" : "Resume")
                            : (lang == "es" ? "Pausar" : "Pause"),
                   action: onTogglePause)

            Button(lang == "es" ? "Compartir enlace" : "Share link", action: onShare)
        } label: {
            Image(systemName: "ellipsis")
                .foregroundColor(.white)
                .padding(8)
        }
    }
}

// Edit price sheet (small and explicit)
private struct EditPriceSheet: View {
    let lang: String
    @Binding var priceText: String
    var onCancel: () -> Void
    var onSave: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Text(lang == "es" ? "Editar precio" : "Edit price")
                    .font(.headline)

                TextField(lang == "es" ? "Nuevo precio" : "New price", text: $priceText)
                    .keyboardType(.decimalPad)
                    .padding()
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(10)
                    .foregroundColor(.white)

                HStack {
                    Button(lang == "es" ? "Cancelar" : "Cancel", action: onCancel)
                    Spacer()
                    Button(lang == "es" ? "Guardar" : "Save", action: onSave)
                        .buttonStyle(.borderedProminent)
                }
                .padding(.top, 6)

                Spacer()
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onCancel) {
                        Image(systemName: "xmark").bold()
                    }
                }
            }
        }
    }
}

private struct FeedTopBar: View {
    let unread: Int
    let pending: Int
    var onListings: () -> Void
    var onChats: () -> Void
    var onCreate: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Spacer()

            Button(action: onListings) {
                BadgeIcon(systemName: "doc.richtext",
                          badge: pending,
                          badgeColor: .gold,
                          baseTint: .white)
            }

            Button(action: onChats) {
                BadgeIcon(systemName: "bubble.left.and.bubble.right.fill",
                          badge: unread,
                          badgeColor: .red,
                          baseTint: .white)
            }

            Button(action: onCreate) {
                Image(systemName: "plus")
                    .font(.headline.weight(.bold))
                    .foregroundColor(.black)
                    .padding(12)
                    .background(
                        Circle()
                            .fill(Color.gold)
                            .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)           // keeps it readable over any bg
        .overlay(Divider(), alignment: .bottom)   // subtle bottom separator
    }
}

private struct TopOverlayHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension View {
    /// Reports this view's rendered height via `TopOverlayHeightKey`
    func reportTopOverlayHeight() -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: TopOverlayHeightKey.self, value: proxy.size.height)
            }
        )
    }
}
