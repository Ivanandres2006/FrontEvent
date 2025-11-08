import SwiftUI

struct MainTabView: View {
    @StateObject private var userSession = UserSession()
    @StateObject private var badge = AppBadgeStore.shared

    @State private var allEvents: [Event] = []
    @State private var selectedTab = 0
    @AppStorage("selectedLanguage") var lang: String = "en"
    @State private var userActiveEventIds: Set<Int> = []
    @Binding var deepLinkEventId: String?

    @State private var showNotifications = false
    
    // inside MainTabView
    @State private var deepLinkResalePostId: Int? = nil
    
    @State private var selectedChatId: Int? = nil
    @State private var showChat = false


    var body: some View {
        TabView(selection: $selectedTab) {

            // 🔘 Events
            NavigationStack {
                EventListView(events: $allEvents, selectedTab: $selectedTab, deepLinkEventId: $deepLinkEventId)
            }
            .tabItem {
                Label(lang == "es" ? "Eventos" : "Events", systemImage: "calendar")
            }
            .tag(0)

            // 🔖 My Events
            NavigationStack {
                MyEventsView(allEvents: $allEvents, userActiveEventIds: $userActiveEventIds)
            }
            .tabItem {
                Label(lang == "es" ?"Mis eventos" : "My Events", systemImage: "bookmark.fill")
            }
            .tag(1)

            // ➕ Create
            NavigationStack {
                CreateEventView(allEvents: $allEvents, selectedTab: $selectedTab)
            }
            .tabItem {
                Label(lang == "es" ? "Crear" : "Create", systemImage: "plus.circle.fill")
            }
            .tag(2)

            // 🧑 Profile
            NavigationStack {
                ProfileView()
            }
            .tabItem {
                Label(lang == "es" ? "Perfil" : "Profile", systemImage: "person.circle.fill")
            }
            .tag(3)

            // 🛒 Resale
            NavigationStack {
                ResaleFeedView()
            }
            .tabItem {
                ZStack(alignment: .topTrailing) {
                    Label(lang == "es" ? "Revender" : "Resale", systemImage: "dollarsign.circle.fill")
                    if badge.pendingResale > 0 {
                        Text("\(min(badge.pendingResale, 99))")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(.black)
                            .padding(4)
                            .background(Color.gold)
                            .clipShape(Circle())
                            .offset(x: 18, y: -6)
                    }
                }
            }
            .tag(4)
        }
        .accentColor(.gold)
        .environmentObject(userSession)
        .onAppear {
            userSession.loadUser()
            fetchAllEventData()
        }
        .onOpenURL { url in
            if let link = AppDeepLink.parse(url: url) {
                switch link {
                case .resalePost(let id):
                    selectedTab = 4 // jump to Resale tab
                    deepLinkResalePostId = id
                    NotificationCenter.default.post(name: .openResalePostFromLink, object: id)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openChatFromPush)) { notif in
            if let chatIdStr = notif.object as? String,
               let chatId = Int(chatIdStr) {
                selectedChatId = chatId
                showChat = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openNotificationsFromPush)) { _ in
            showNotifications = true
        }
        .sheet(isPresented: $showNotifications) {
            NavigationStack {
                NotificationsView(initialTab: .activity)
                    .environmentObject(userSession)
                    .navigationTitle(lang == "es" ? "Notificaciones" : "Notifications")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
    

    func fetchAllEventData() {
        guard let token = TokenManager.shared.getAccessToken() else { return }

        // 1) Tickets -> event IDs
        if let eventIdsUrl = URL(string: "https://backendevent-etce.onrender.com/api/tickets/my-event-ids") {
            var request = URLRequest(url: eventIdsUrl)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            URLSession.shared.dataTask(with: request) { data, _, _ in
                if let data = data,
                   let ids = try? JSONDecoder().decode([Int].self, from: data) {
                    DispatchQueue.main.async {
                        self.userActiveEventIds = Set(ids)

                        // 2) RSVP
                        if let rsvpUrl = URL(string: "https://backendevent-etce.onrender.com/events/rsvp-attending") {
                            var rsvpRequest = URLRequest(url: rsvpUrl)
                            rsvpRequest.httpMethod = "GET"
                            rsvpRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

                            URLSession.shared.dataTask(with: rsvpRequest) { rsvpData, _, _ in
                                if let rsvpData = rsvpData,
                                   let rsvpIds = try? JSONDecoder().decode([Int].self, from: rsvpData) {
                                    DispatchQueue.main.async {
                                        self.userActiveEventIds.formUnion(rsvpIds)
                                    }
                                }
                            }.resume()
                        }
                    }
                }
            }.resume()
        }

        // 3) All events
        if let url = URL(string: "https://backendevent-etce.onrender.com/events?page=0&size=100") {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            URLSession.shared.dataTask(with: request) { data, _, _ in
                guard let data = data else { return }
                if let decoded = try? JSONDecoder().decode(PaginatedResponse<Event>.self, from: data) {
                    DispatchQueue.main.async {
                        self.allEvents = decoded.content
                        print("✅ MainTabView fetched events: \(decoded.content.count)")
                    }
                }
            }.resume()
        }
    }
}
