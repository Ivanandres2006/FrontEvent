import SwiftUI

struct MainTabView: View {
    @StateObject private var userSession = UserSession()
    @State private var allEvents: [Event] = []
    @State private var selectedTab = 0
    @AppStorage("selectedLanguage") var lang: String = "en"
    @State private var userActiveEventIds: Set<Int> = []
    @Binding var deepLinkEventId: String?


    var body: some View {
        TabView(selection: $selectedTab) {
            // 🔘 Event List
            NavigationStack {
                EventListView(events: $allEvents, selectedTab: $selectedTab, deepLinkEventId: $deepLinkEventId) // <--
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

            // 🛒 Resale Feed
            NavigationStack {
                ResaleFeedView()
            }
            .tabItem {
                Label(lang == "es" ? "Revender" : "Resale", systemImage: "dollarsign.circle.fill")
            }
            .tag(4)
        }
        .accentColor(.gold)
        .environmentObject(userSession)
        .onAppear {
            userSession.loadUser()
            fetchAllEventData()
        }
    }
    
    func fetchAllEventData() {
        guard let token = TokenManager.shared.getAccessToken() else { return }

        // Step 1: Fetch ticket-based event IDs
        if let eventIdsUrl = URL(string: "https://backendevent-etce.onrender.com/api/tickets/my-event-ids") {
            var request = URLRequest(url: eventIdsUrl)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            URLSession.shared.dataTask(with: request) { data, _, _ in
                if let data = data,
                   let ids = try? JSONDecoder().decode([Int].self, from: data) {
                    DispatchQueue.main.async {
                        self.userActiveEventIds = Set(ids)

                        // Step 2: Fetch RSVP-based IDs
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

        // Step 3: Fetch all events
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
