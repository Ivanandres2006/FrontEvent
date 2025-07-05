import SwiftUI

struct MainTabView: View {
    @StateObject private var userSession = UserSession()
    @State private var allEvents: [Event] = []
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // 🔘 Event List
            NavigationStack {
                EventListView(events: $allEvents, selectedTab: $selectedTab)
            }
            .tabItem {
                Label("Events", systemImage: "calendar")
            }
            .tag(0)

            // 🔖 My Events
            NavigationStack {
                MyEventsView()
            }
            .tabItem {
                Label("My Events", systemImage: "bookmark.fill")
            }
            .tag(1)

            // ➕ Create
            NavigationStack {
                CreateEventView(allEvents: $allEvents, selectedTab: $selectedTab)
            }
            .tabItem {
                Label("Create", systemImage: "plus.circle.fill")
            }
            .tag(2)

            // 🧑 Profile
            NavigationStack {
                ProfileView()
            }
            .tabItem {
                Label("Profile", systemImage: "person.circle.fill")
            }
            .tag(3)

            // 🛒 Resale Feed
            NavigationStack {
                ResaleFeedView()
            }
            .tabItem {
                Label("Resale", systemImage: "dollarsign.circle.fill")
            }
            .tag(4)
        }
        .accentColor(.neonGreen)
        .environmentObject(userSession)
        .onAppear {
            userSession.loadUser()
        }
    }
}
