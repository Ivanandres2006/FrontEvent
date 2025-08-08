import SwiftUI

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
    
    @State private var showInitialLoading = true
    
    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                
                if eventNotFound {
                    eventNotFoundBanner
                }
                
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack(alignment: .center, spacing: 0) {
                            // Greeting + Name
                            VStack(alignment: .leading, spacing: 7) {
                                Text(getGreeting(lang: lang) + ",")
                                    .font(.system(size: 17, weight: .regular))
                                    .foregroundColor(.white.opacity(0.68))
                                    .textCase(.none)
                                Text(userSession.firstName.capitalized)
                                    .font(.system(size: 29, weight: .bold))
                                    .foregroundColor(.white)
                                    .textCase(.none)
                            }
                            .padding(.vertical, 8) // Add some top and bottom for better balance
                            
                            Spacer()
                            
                            // Buttons (now vertically centered!)
                            HStack(spacing: 14) {
                                Button(action: {
                                    // Notification action
                                }) {
                                    Circle()
                                        .fill(Color.white.opacity(0.18))
                                        .frame(width: 38, height: 38)
                                        .overlay(
                                            Image(systemName: "bell")
                                                .font(.system(size: 18, weight: .medium))
                                                .foregroundColor(.white.opacity(0.93))
                                        )
                                }
                                Button(action: {
                                    showDirectChats = true
                                }) {
                                    Circle()
                                        .fill(Color.white.opacity(0.18))
                                        .frame(width: 38, height: 38)
                                        .overlay(
                                            Image(systemName: "message.circle")
                                                .font(.system(size: 20, weight: .medium))
                                                .foregroundColor(.white.opacity(0.93))
                                        )
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 14)
                        
                        searching
                        
                        if isLoading || showInitialLoading {
                            loadingView
                        } else {
                            // Popular Events
                            VStack(alignment: .leading, spacing: 12) {
                                Text(lang == "es" ? "Eventos":"Events")
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
                                Text(lang == "es" ? "Ciudad" : "Cities")
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
                        
                    }
                    .padding(.top, 20)
                }
            }
            .refreshable {
                print("🔄 Pull-to-refresh triggered in EventListView")
                fetchEvents(reset: true)
            }
            .onAppear {
                print("📥 EventListView received events count: \(events.count)")
                if events.isEmpty {
                    withAnimation { showInitialLoading = true }
                    fetchEvents(reset: true)
                } else {
                    withAnimation { showInitialLoading = false }
                }
                
            }
            .onChange(of: selectedTab) { newTab in
                if newTab == 0 && previousTab != 0 {
                    fetchEvents(reset: true)
                }
                previousTab = newTab
            }
            .onChange(of: deepLinkEventId) { newValue in
                if let idStr = newValue, let id = Int(idStr), let event = events.first(where: { $0.id == id }) {
                    selectedEvent = event
                    showDetail = true
                } else if newValue != nil {
                    // Not found!
                    eventNotFoundMsg = "Event not found or has been deleted."
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        eventNotFound = true
                    }
                    // Hide after 2 seconds, with "drag-down" style
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) {
                            eventNotFound = false
                        }
                        deepLinkEventId = nil // Clean up
                    }
                }
            }
            .sheet(isPresented: $showDetail, onDismiss: {
                deepLinkEventId = nil // Clear after showing
            }) {
                if let event = selectedEvent {
                    EventDetailView(
                        event: event,
                        allEvents: $events // <-- pass the binding!
                    )
                }
            }
            .fullScreenCover(isPresented: $showDirectChats) {
                NavigationStack {
                    DirectChatListView()
                        .environmentObject(userSession)
                }
            }
            .sheet(item: $reunionToRsvp) { reunion in
                ReunionRSVPView(
                    eventId: reunion.id,
                    title: reunion.title,
                    location: reunion.location,
                    dateTime: reunion.dateTime,
                    onComplete: {
                        reunionToRsvp = nil
                    }
                )
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
    
    var searching: some View {
        // Search Bar (under the header)
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.7))
                .font(.system(size: 20))
                .padding(.leading, 10)
            
            TextField(lang == "es" ? "Buscar eventos, lugares..." : "Search events, venues...", text: $searchText)
                .font(.system(size: 18))
                .foregroundColor(.white.opacity(0.95))
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .padding(.vertical, 13)
                .padding(.horizontal, 4)
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1.2)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.13))
                )
                .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 5)
        )
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .padding(.top, 5)
    }
    
    var emptyEventsView: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 50))
                .foregroundColor(.white.opacity(0.5))
            Text(lang == "es" ? "No hay futuros eventos": "No upcoming events")
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
            Text(lang == "es" ? "No hay ciudades encontradas" : "No cities found")
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
    private var eventNotFoundBanner: some View {
        VStack {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                Text(eventNotFoundMsg)
                    .foregroundColor(.white)
                    .bold()
                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.red.opacity(0.92))
            )
            .padding(.horizontal)
            .transition(.move(edge: .top).combined(with: .opacity))
            .zIndex(100)
            Spacer(minLength: 8)
        }
    }
    
    var loadingView: some View{
        ZStack {
            Color.clear
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var upcomingEvents: [Event] {
        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

        return events.filter { event in
            guard let eventDate = formatter.date(from: event.dateTime) else {
                return false
            }
            let isFuture = eventDate >= now

            // 👇 Only show if user is allowed (owner or guest for reunions, always for other events)
            return isFuture && isReunionVisible(event, for: userSession)
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

        // 1. Owner can see
        if let ownerId = event.createdBy?.id, ownerId == user.userId {
            return true
        }
        // 2. (Optionally also support old field)
        if let ownerEmailLegacy = event.createdByEmail, ownerEmailLegacy.lowercased() == user.email.lowercased() {
            return true
        }
        // 3. Reunion guest can see
        if let guests = event.reunionGuests {
            if guests.contains(where: { $0.email.lowercased() == user.email.lowercased() }) {
                return true
            }
        }
        // 4. Not owner or guest: hide
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
              let url = URL(string: "https://backendevent-etce.onrender.com/events?page=\(currentPage)&size=\(pageSize)") else {
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
                    

                    // ✅ Show RSVP popup if there's a reunion the user hasn’t RSVP’d yet
                    let upcomingReunionsNeedingRsvp = decoded.content.filter {
                        guard $0.type == "reunion" else { return false }
                        
                        let guest = ($0.reunionGuests ?? []).first(where: {
                            $0.email.lowercased() == userSession.email.lowercased()
                        })
                        
                        return guest != nil && guest?.attending == false
                    }
                    
                    
                    if let target = upcomingReunionsNeedingRsvp.first {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            self.reunionToRsvp = target
                        }
                    }
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

import SwiftUI

struct CityCard: View {
    let city: String
    @State private var remoteImageUrl: URL? = nil
    @State private var isLoading = false

    // Get asset name from city string (all lowercase, no spaces)
    private var assetName: String {
        city.replacingOccurrences(of: " ", with: "").lowercased()
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // 1. Try asset image
            if let uiImage = UIImage(named: assetName) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
            // 2. Else try remote (Unsplash)
            else if let url = remoteImageUrl {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        placeholder
                        ProgressView()
                            .scaleEffect(1.2)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
                .transition(.opacity)
            }
            // 3. If not loading and not already fetched, trigger API
            else {
                placeholder
                    .onAppear {
                        if !isLoading { fetchCityImage() }
                    }
            }

            // Modern text overlay
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
            Image(systemName: "photo")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .foregroundColor(.white.opacity(0.65))
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
                  let imageUrl = URL(string: imageUrlStr) else {
                return
            }
            DispatchQueue.main.async {
                self.remoteImageUrl = imageUrl
            }
        }.resume()
    }
}




