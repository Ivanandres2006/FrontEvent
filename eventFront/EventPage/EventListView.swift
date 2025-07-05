import SwiftUI

struct EventListView: View {
    @Binding var events: [Event]
    @Binding var selectedTab: Int

    @State private var currentPage = 0
    @State private var isLoading = false
    @State private var hasMore = true
    @State private var previousTab = 0

    @EnvironmentObject var userSession: UserSession

    @State private var selectedCity: CitySelection? = nil
    @State private var selectedEvent: Event? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("Welcome, \(userSession.firstName)")
                            .font(.largeTitle.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal)

                        // Popular Events
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Popular Events")
                                .font(.title2.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal)

                            if upcomingEvents.isEmpty {
                                emptyEventsView
                            } else {
                                paginatedEventsTabView
                            }
                        }

                        // Cities
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Cities")
                                .font(.title2.bold())
                                .foregroundColor(.white)
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
                    .padding(.top, 20)
                }
            }
            .onAppear {
                if events.isEmpty {
                    fetchEvents(reset: true)
                }
            }
            .onChange(of: selectedTab) { newTab in
                if newTab == 0 && previousTab != 0 {
                    fetchEvents(reset: true)
                }
                previousTab = newTab
            }
            .onChange(of: events.count) { _ in
                currentPage = 0
                hasMore = true
            }
            .sheet(item: $selectedEvent) { event in
                EventDetailView(event: event, allEvents: $events)
            }
            .navigationDestination(item: $selectedCity) { selection in
                NavigationStack {
                    CityEventsView(city: selection.name, allEvents: $events)
                        .environmentObject(userSession)
                }
            }
        }
    }

    // MARK: - Sections

    var emptyEventsView: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 50))
                .foregroundColor(.white.opacity(0.5))
            Text("No upcoming events")
                .foregroundColor(.white.opacity(0.6))
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
                                .onTapGesture {
                                    selectedEvent = event
                                }
                        }
                    }
                    .frame(width: UIScreen.main.bounds.width - 40)
                    .padding(.vertical, isSingleEvent ? 10 : 8)
                }
            }
            .frame(height: isSingleEvent ? 170 : 280) // 🛠 Adjust this value as needed
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
            .animation(.easeInOut(duration: 0.3), value: upcomingEvents)
            .padding(.horizontal)
        }
    }

    var emptyCitiesView: some View {
        VStack(spacing: 10) {
            Image(systemName: "building.2.crop.circle")
                .font(.system(size: 50))
                .foregroundColor(.white.opacity(0.5))
            Text("No cities found")
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    var citiesScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(uniqueCities, id: \.self) { city in
                    CityCard(city: city)
                        .onTapGesture {
                            selectedCity = CitySelection(name: city)
                        }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Helpers

    var upcomingEvents: [Event] {
        let today = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current

        return events.filter {
            guard let eventDate = formatter.date(from: $0.dateTime) else { return false }
            return eventDate >= today
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
              let url = URL(string: "http://localhost:8080/events?page=\(currentPage)&size=\(pageSize)") else {
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
                    events.append(contentsOf: decoded.content)
                    currentPage += 1
                    hasMore = !decoded.last
                }
            }
        }.resume()
    }
}

// MARK: - City Selection Wrapper

struct CitySelection: Identifiable, Hashable {
    let id = UUID()
    let name: String
}

struct CityCard: View {
    let city: String

    private var assetName: String {
        city.replacingOccurrences(of: " ", with: "").lowercased()
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let uiImage = UIImage(named: assetName) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.gray.opacity(0.3)
                    Image(systemName: "photo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            Text(city)
                .font(.headline)
                .foregroundColor(.white)
                .padding(6)
                .background(Color.black.opacity(0.4))
                .cornerRadius(10)
                .padding(8)
        }
        .frame(width: 140, height: 100)
        .clipped()
        .cornerRadius(16)
    }
}
