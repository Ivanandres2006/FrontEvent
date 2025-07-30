import SwiftUI

struct MyEventsView: View {
    @Binding var allEvents: [Event]
    @Binding var userActiveEventIds: Set<Int>
    @AppStorage("selectedLanguage") var lang: String = "en"

    @State private var selectedTab: Tab = .myEvents
    @State private var selectedEvent: Event? = nil  // ✅ added
    @EnvironmentObject var userSession: UserSession
    @State private var animate = false
    

    enum Tab {
        case myEvents
        case createdEvents
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // 🔘 Tab buttons
                        HStack {
                            TabButton(title: lang == "es" ? "Mis Eventos" : "My Events", isSelected: selectedTab == .myEvents) {
                                selectedTab = .myEvents
                            }
                            TabButton(title: lang == "es" ? "Eventos Creados" : "Created Events", isSelected: selectedTab == .createdEvents) {
                                selectedTab = .createdEvents
                            }
                        }
                        .padding(.top, 20)

                        if selectedTab == .myEvents {
                            // Attending
                            let attending = futureAttendingEvents()
                            SectionHeader(icon: "clock.fill", title: lang == "es" ? "Atentiendo":"Attending", color: .cyan)
                            if attending.isEmpty {
                                emptyMessage(lang == "es" ? "No has unido a ninguna evento proximo" : "You haven’t joined any upcoming events.")
                            } else {
                                EventList(events: attending, selectedEvent: $selectedEvent) // ✅
                            }

                            // Attended
                            let attended = pastAttendingEvents()
                            SectionHeader(icon: "checkmark.circle.fill", title: lang == "es" ? "Asistio" : "Attended", color: .green)
                            if attended.isEmpty {
                                emptyMessage(lang == "es" ? "No has ido a ningun evento": "You haven’t attended any events yet.")
                            } else {
                                EventList(events: attended, selectedEvent: $selectedEvent) // ✅
                            }

                        } else {
                            // Future Created
                            let future = futureCreatedEvents()
                            SectionHeader(icon: "calendar.badge.plus", title:lang == "es" ? "Creaciones Futuras": "Future Created", color: .mint)
                            if future.isEmpty {
                                emptyMessage(lang == "es" ? "No has creado ningun proximo evento ": "You haven’t created any upcoming events.")
                            } else {
                                EventList(events: future, selectedEvent: $selectedEvent) // ✅
                            }

                            // Past Created
                            let past = pastCreatedEvents()
                            SectionHeader(icon: "clock.arrow.circlepath", title: lang == "es" ? "Creaciones Pasadas": "Past Created", color: .orange)
                            if past.isEmpty {
                                emptyMessage(lang == "es" ? "No hay eventos creados en el pasado": "No past created events.")
                            } else {
                                EventList(events: past, selectedEvent: $selectedEvent) // ✅
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 30)
                }
                .refreshable {
                    fetchAllEvents()
                }
            }
            .navigationTitle(lang == "es" ? "Mis eventos": "My Events")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                print("👤 userSession.id = \(userSession.userId)")
                    print("📧 userSession.email = \(userSession.email)")
                animate = true
            }
            .sheet(item: $selectedEvent) { event in
                EventDetailView(event: event, allEvents: $allEvents)
                    .environmentObject(userSession) // ✅ Needed
            }
        }
    }

    private func futureAttendingEvents() -> [Event] {
        let now = Date()
        return allEvents.filter {
            userActiveEventIds.contains($0.id) && ($0.dateAsDate ?? now) >= now
        }
    }

    private func pastAttendingEvents() -> [Event] {
        let now = Date()
        return allEvents.filter {
            userActiveEventIds.contains($0.id) && ($0.dateAsDate ?? now) < now
        }
    }

    private func futureCreatedEvents() -> [Event] {
        let now = Date()
        var matching: [Event] = []

        for event in allEvents {
            let byId = event.createdBy?.id == userSession.userId
            let byEmail = event.createdByEmail?.lowercased() == userSession.email.lowercased()
            let isReunionGuest = (event.type == "reunion") &&
                (event.reunionGuests?.contains(where: {
                    $0.email.lowercased() == userSession.email.lowercased()
                }) == true)
            let isFuture = (event.dateAsDate ?? now) >= now
            print("🕒 \(event.title): dateTime = \(event.dateTime), parsed = \(event.dateAsDate)")

            print("🔍 \(event.title): byId=\(byId), byEmail=\(byEmail), isReunionGuest=\(isReunionGuest), isFuture=\(isFuture)")

            if (byId || byEmail), isFuture {
                matching.append(event)
            }
        }

        print("✅ total matched: \(matching.count)")
        return matching
    }



    private func pastCreatedEvents() -> [Event] {
        let now = Date()
        return allEvents.filter {
            ($0.createdBy?.id == userSession.userId) ||
            ($0.createdByEmail?.lowercased() == userSession.email.lowercased())
            && ($0.dateAsDate ?? now) < now
        }
    }


    func fetchAllEvents() {
        guard let token = TokenManager.shared.getAccessToken() else { return }

        // Fetch event IDs where user has PAID tickets
        if let eventIdsUrl = URL(string: "https://backendevent-etce.onrender.com/api/tickets/my-event-ids") {
            var request = URLRequest(url: eventIdsUrl)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            URLSession.shared.dataTask(with: request) { data, _, _ in
                if let data = data,
                   let ids = try? JSONDecoder().decode([Int].self, from: data) {
                    DispatchQueue.main.async {
                        // First: fetch ticket-based IDs
                        self.userActiveEventIds = Set(ids)

                        // Then: fetch RSVP-based IDs
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

        // Fetch all events
        if let url = URL(string: "https://backendevent-etce.onrender.com/events?page=0&size=100") {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            URLSession.shared.dataTask(with: request) { data, _, _ in
                guard let data = data else { return }
                if let decoded = try? JSONDecoder().decode(PaginatedResponse<Event>.self, from: data) {
                    DispatchQueue.main.async {
                        DispatchQueue.main.async {
                            let existingIds = Set(self.allEvents.map { $0.id })
                            let newEvents = decoded.content.filter { !existingIds.contains($0.id) }
                            self.allEvents.append(contentsOf: newEvents)
                        }
                    }
                }
            }.resume()
        }
    }


    @ViewBuilder
    func emptyMessage(_ text: String) -> some View {
        Text(text)
            .foregroundColor(.gray)
            .font(.subheadline)
            .multilineTextAlignment(.center)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - EventList Updated

struct EventList: View {
    let events: [Event]
    @Binding var selectedEvent: Event?

    var body: some View {
        LazyVStack(spacing: 16) {
            ForEach(events) { event in
                EventCardMini(event: event)
                    .onTapGesture {
                        selectedEvent = event
                    }
            }
        }
    }
}


struct SectionHeader: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 10)
    }
}

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .fontWeight(.bold)
                .foregroundColor(isSelected ? .black : .white)
                .padding(.vertical, 10)
                .padding(.horizontal, 20)
                .background(isSelected ? Color.gold : Color.clear)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity)
    }
}
