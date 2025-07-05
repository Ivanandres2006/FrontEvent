import SwiftUI

struct AdminView: View {
    @State private var selectedTab = "Users"
    private let tabs = ["Users", "Events", "Resales"]

    @State private var users: [AdminUser] = []
    @State private var events: [AdminEvent] = []
    @State private var resales: [AdminResalePost] = []

    @State private var loading = false
    @State private var errorMessage: String?
    @State private var searchText = ""

    @State private var expandedEventId: Int?
    @State private var selectedAnalyticsEvent: EventIDWrapper?

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                VStack(spacing: 12) {
                    Picker("Select", selection: $selectedTab) {
                        ForEach(tabs, id: \.self) { tab in
                            Text(tab).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    SearchBar(text: $searchText)
                        .padding(.horizontal)

                    ScrollView {
                        VStack(spacing: 16) {
                            if loading {
                                ForEach(0..<5, id: \.self) { _ in
                                    if selectedTab == "Users" {
                                        SkeletonUserRow()
                                    } else if selectedTab == "Events" {
                                        SkeletonEventRow()
                                    } else {
                                        SkeletonResaleRow()
                                    }
                                }
                            } else if let error = errorMessage {
                                Text("Error: \(error)").foregroundColor(.red).padding()
                            } else {
                                if selectedTab == "Users" {
                                    ForEach(filteredUsers) { user in
                                        adminUserRow(user)
                                    }
                                } else if selectedTab == "Events" {
                                    ForEach(filteredEvents) { event in
                                        adminEventRow(event)
                                    }
                                } else if selectedTab == "Resales" {
                                    ForEach(filteredResales) { post in
                                        adminResaleRow(post)
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                    .refreshable {
                        loadData()
                    }
                }
                .navigationTitle("Admin Dashboard")
                .foregroundColor(.white)
            }
            .onAppear { loadData() }
            .onChange(of: selectedTab) { _ in loadData() }
            .sheet(item: $selectedAnalyticsEvent) { wrapper in
                EventAnalyticsView(eventId: wrapper.id)
            }
        }
    }

    // MARK: - Filtered Lists

    var filteredUsers: [AdminUser] {
        users.filter {
            searchText.isEmpty ||
            $0.email.localizedCaseInsensitiveContains(searchText) ||
            $0.firstName.localizedCaseInsensitiveContains(searchText) ||
            $0.lastName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var filteredEvents: [AdminEvent] {
        events.filter {
            searchText.isEmpty ||
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.location.localizedCaseInsensitiveContains(searchText)
        }
    }

    var filteredResales: [AdminResalePost] {
        resales.filter {
            searchText.isEmpty ||
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            ($0.description ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Rows

    private func adminUserRow(_ user: AdminUser) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(user.email).bold()
                Text("\(user.firstName) \(user.lastName)").font(.subheadline).opacity(0.8)
            }
            Spacer()
            Button(role: .destructive) {
                deleteUser(id: user.id)
            } label: {
                Image(systemName: "trash").foregroundColor(.red)
            }
        }
        .padding()
        .background(Color.white.opacity(0.08))
        .cornerRadius(12)
    }

    private func adminEventRow(_ event: AdminEvent) -> some View {
        let isOversold = event.soldTickets > event.totalTickets
        let remaining = max(event.totalTickets - event.soldTickets, 0)
        let soldPercent = event.totalTickets > 0
            ? min(Double(event.soldTickets) / Double(event.totalTickets) * 100, 100)
            : 0

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(event.title)
                        .bold()
                        .foregroundColor(.white)

                    Text(event.location)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }

                Spacer()

                Button(role: .destructive) {
                    deleteEvent(id: event.id)
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
            }

            if expandedEventId == event.id {
                VStack(alignment: .leading, spacing: 6) {
                    Divider().background(Color.white.opacity(0.2))

                    Text("📊 Analytics")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)

                    Text("Tickets Sold: \(event.soldTickets)")
                        .foregroundColor(isOversold ? .red : .white.opacity(0.9))

                    Text("Tickets Remaining: \(remaining)")
                        .foregroundColor(isOversold ? .red : .white.opacity(0.9))

                    if isOversold {
                        Text("⚠️ Oversold")
                            .font(.caption.bold())
                            .foregroundColor(.red)
                    }

                    Text(String(format: "Revenue: $%.2f", event.totalRevenue))
                        .foregroundColor(.neonGreen)

                    ProgressView(value: soldPercent, total: 100)
                        .tint(isOversold ? .red : .neonGreen)

                    Text(String(format: "%.0f%% of tickets sold", soldPercent))
                        .font(.footnote)
                        .foregroundColor(isOversold ? .red : .white.opacity(0.7))

                    Button {
                        selectedAnalyticsEvent = EventIDWrapper(id: event.id)
                    } label: {
                        Text("📈 View Charts")
                            .font(.subheadline.bold())
                            .foregroundColor(.black)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(Color.neonGreen)
                            .cornerRadius(10)
                            .padding(.top, 8)
                    }
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(Color.white.opacity(0.08))
        .cornerRadius(12)
        .onTapGesture {
            withAnimation {
                expandedEventId = expandedEventId == event.id ? nil : event.id
            }
        }
    }



    private func adminResaleRow(_ post: AdminResalePost) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(post.title).bold()
                if let desc = post.description {
                    Text(desc).font(.subheadline).opacity(0.8)
                }
            }
            Spacer()
            Button(role: .destructive) {
                deleteResalePost(id: post.id)
            } label: {
                Image(systemName: "trash").foregroundColor(.red)
            }
        }
        .padding()
        .background(Color.white.opacity(0.08))
        .cornerRadius(12)
    }

    // MARK: - Network

    private func loadData() {
        loading = true
        errorMessage = nil

        let path: String
        switch selectedTab {
        case "Users": path = "/admin/users"
        case "Events": path = "/admin/events"
        case "Resales": path = "/admin/resale-posts"
        default: return
        }

        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "http://localhost:8080\(path)") else {
            errorMessage = "Invalid token or URL"
            loading = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                loading = false
                if let error = error {
                    errorMessage = error.localizedDescription
                    return
                }

                guard let data = data else {
                    errorMessage = "No data"
                    return
                }
                
                // 🔍 Debug print the raw backend JSON
                if let raw = String(data: data, encoding: .utf8) {
                    print("🛑 Raw JSON Response:")
                    print(raw)
                }

                do {
                    switch selectedTab {
                    case "Users":
                        users = try JSONDecoder().decode([AdminUser].self, from: data)
                    case "Events":
                        events = try JSONDecoder().decode([AdminEvent].self, from: data)
                    case "Resales":
                        resales = try JSONDecoder().decode([AdminResalePost].self, from: data)
                    default: break
                    }
                } catch {
                    errorMessage = "Decoding error: \(error.localizedDescription)"
                }
            }
        }.resume()
    }

    private func deleteUser(id: Int) {
        deleteItem(path: "/admin/user/\(id)") {
            users.removeAll { $0.id == id }
        }
    }

    private func deleteEvent(id: Int) {
        deleteItem(path: "/admin/event/\(id)") {
            events.removeAll { $0.id == id }
        }
    }

    private func deleteResalePost(id: Int) {
        deleteItem(path: "/admin/resale-post/\(id)") {
            resales.removeAll { $0.id == id }
        }
    }

    private func deleteItem(path: String, onSuccess: @escaping () -> Void) {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "http://localhost:8080\(path)") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { _, _, _ in
            DispatchQueue.main.async {
                onSuccess()
            }
        }.resume()
    }
}

// MARK: - Search Bar

struct SearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.6))
            TextField("Search...", text: $text)
                .foregroundColor(.white)
                .placeholder(when: text.isEmpty) {
                    Text("Search...").foregroundColor(.white.opacity(0.5))
                }
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
        }
        .padding(10)
        .background(Color.white.opacity(0.08))
        .cornerRadius(12)
    }
}

// MARK: - Placeholder Extension

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            if shouldShow { placeholder() }
            self
        }
    }
}

// MARK: - Skeleton Views

private func SkeletonUserRow() -> some View {
    HStack {
        VStack(alignment: .leading, spacing: 6) {
            Text("email@example.com").font(.body).bold()
            Text("First Last").font(.subheadline)
        }
        Spacer()
        Image(systemName: "trash").foregroundColor(.red)
    }
    .padding()
    .background(Color.white.opacity(0.08))
    .cornerRadius(12)
    .redacted(reason: .placeholder)
}

private func SkeletonEventRow() -> some View {
    VStack(alignment: .leading, spacing: 6) {
        HStack {
            VStack(alignment: .leading) {
                Text("Event Title")
                Text("Event Location").font(.subheadline)
            }
            Spacer()
            Image(systemName: "trash").foregroundColor(.red)
        }

        VStack(alignment: .leading, spacing: 4) {
            Divider().background(Color.white.opacity(0.2))
            Text("📊 Analytics")
            ProgressView(value: 0.5).tint(.neonGreen)
        }
    }
    .padding()
    .background(Color.white.opacity(0.08))
    .cornerRadius(12)
    .redacted(reason: .placeholder)
}

private func SkeletonResaleRow() -> some View {
    HStack {
        VStack(alignment: .leading, spacing: 4) {
            Text("Resale Ticket Title")
            Text("Resale Description").font(.subheadline)
        }
        Spacer()
        Image(systemName: "trash").foregroundColor(.red)
    }
    .padding()
    .background(Color.white.opacity(0.08))
    .cornerRadius(12)
    .redacted(reason: .placeholder)
}

// MARK: - Identifiable Wrapper for Sheet

struct EventIDWrapper: Identifiable {
    let id: Int
}
