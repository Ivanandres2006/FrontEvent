import SwiftUI
import Foundation

struct FxInfo: Decodable {
    let vesPerUsd: Double
    let source: String?
    let fetchedAt: String?
    let fallback: Double?
    let overrideActive: Bool?
    let overrideUntil: String?
}

// MARK: - Admin API (hardened)
final class AdminAPI {
    static let shared = AdminAPI(); private init() {}
        private let base = "https://backendevent-etce.onrender.com"

        private func authedRequest(_ path: String, method: String = "GET", body: Data? = nil) -> URLRequest? {
            guard let url = URL(string: base + path),
                  let token = TokenManager.shared.getAccessToken() else { return nil }
            var r = URLRequest(url: url)
            r.httpMethod = method
            r.cachePolicy = .reloadIgnoringLocalCacheData
            r.timeoutInterval = 30
            r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            r.setValue("application/json", forHTTPHeaderField: "Accept")
            if body != nil { r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
            r.httpBody = body
            return r
        }

        

        // Public FX read (no auth required)
        func getFxInfo() async throws -> FxInfo {
            let url = URL(string: base + "/api/fx/ves-per-usd")!
            let (data, resp) = try await URLSession.shared.data(from: url)
            try validate(resp)
            return try JSONDecoder().decode(FxInfo.self, from: data)
        }

        // Admin: set override
        func setFxOverride(rate: Double, ttlMinutes: Int? = nil) async throws {
            let payload = try JSONSerialization.data(withJSONObject: [
                "rate": rate,
                "ttlMinutes": ttlMinutes as Any
            ].compactMapValues { $0 }, options: [])

            guard let req = authedRequest("/admin/fx/ves-per-usd", method: "POST", body: payload) else { return }
            let (_, resp) = try await URLSession.shared.data(for: req)
            try validate(resp)
        }

        // Admin: clear override
        func clearFxOverride() async throws {
            guard let req = authedRequest("/admin/fx/ves-per-usd", method: "DELETE") else { return }
            let (_, resp) = try await URLSession.shared.data(for: req)
            try validate(resp)
        }


    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let dec = JSONDecoder()
        return try dec.decode(T.self, from: data)
    }

    private func validate(_ resp: URLResponse?) throws {
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        switch http.statusCode {
        case 200..<300: return
        case 401: throw NSError(domain: "AdminAPI", code: 401, userInfo: [NSLocalizedDescriptionKey: "Unauthorized. Please log in again."])
        case 403: throw NSError(domain: "AdminAPI", code: 403, userInfo: [NSLocalizedDescriptionKey: "Forbidden. Your account is not an admin."])
        default: throw NSError(domain: "AdminAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server error \(http.statusCode)."])
        }
    }

    func getUsers() async throws -> [AdminUser] {
        guard let req = authedRequest("/admin/users") else { return [] }
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(resp)
        return try decode([AdminUser].self, from: data)
    }

    func setUserPermission(userId: Int, allow: Bool) async throws {
        guard let req = authedRequest("/admin/user/\(userId)/permission?allow=\(allow)", method: "POST") else { return }
        let (_, resp) = try await URLSession.shared.data(for: req)
        try validate(resp)
    }

    func deleteUser(userId: Int) async throws {
        guard let req = authedRequest("/admin/user/\(userId)", method: "DELETE") else { return }
        let (_, resp) = try await URLSession.shared.data(for: req)
        try validate(resp)
    }

    func getEvents() async throws -> [AdminEvent] {
        guard let req = authedRequest("/admin/events") else { return [] }
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(resp)
        return try decode([AdminEvent].self, from: data)
    }

    func deleteEvent(eventId: Int) async throws {
        guard let req = authedRequest("/admin/event/\(eventId)", method: "DELETE") else { return }
        let (_, resp) = try await URLSession.shared.data(for: req)
        try validate(resp)
    }

    func getResales() async throws -> [AdminResalePost] {
        guard let req = authedRequest("/admin/resale-posts") else { return [] }
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(resp)
        return try decode([AdminResalePost].self, from: data)
    }

    func deleteResale(id: Int) async throws {
        guard let req = authedRequest("/admin/resale-post/\(id)", method: "DELETE") else { return }
        let (_, resp) = try await URLSession.shared.data(for: req)
        try validate(resp)
    }
}

// MARK: - Screen

struct AdminDashboardView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var users: [AdminUser] = []
    @State private var events: [AdminEvent] = []
    @State private var resales: [AdminResalePost] = []

    @State private var loading = false
    @State private var error: String?

    @State private var selectedTab: Tab = .overview
    @State private var search = ""
    @State private var expandedEventId: Int?
    
    @State private var fxInfo: FxInfo?
    @State private var fxInput: String = ""
    @State private var fxSaving = false


    enum Tab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case events   = "Events"
        case users    = "Users"
        case resales  = "Resales"
        case liveOps  = "Live Ops"
        case marketing = "Marketing"
        case audit    = "Audit"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                contentList
                    .task { await load() }
                    .refreshable { await load() }
                    .onAppear { configureAppearance() }

                if loading { ProgressView().tint(.gold) }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill").font(.title3)
                    }
                    .tint(.white)
                }
                ToolbarItem(placement: .principal) {
                    Text("WKND Owner Console")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Fully scrolling content
    private var contentList: some View {
        List {
            // Header (moved inside List so it scrolls)
            Section {
                HeaderSection(
                    selectedTab: $selectedTab,
                    totalRevenue: totalRevenue,
                    totalSold: totalSold,
                    eventsCount: events.count,
                    openResales: resales.filter { ($0.sold ?? false) == false }.count,
                    soldResales: resales.filter { ($0.sold ?? false) == true }.count
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .transaction { t in t.animation = nil }     // keep: no implicit anims while sizing
            }
            .textCase(nil)
            
            // inside `contentList` List builder, just after the header Section:
            Section {
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("BCV Rate (USD → VES)", systemImage: "coloncurrencysign.circle.fill")
                                .font(.headline)
                            Spacer()
                            if let info = fxInfo {
                                Text(info.overrideActive == true ? "Override active" : (info.source ?? "-"))
                                    .font(.caption).foregroundColor(info.overrideActive == true ? .yellow : .white.opacity(0.7))
                            }
                        }

                        HStack(spacing: 10) {
                            TextField("e.g. 179.4308", text: $fxInput)
                                .keyboardType(.decimalPad)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                                .padding(10)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(10)

                            Button {
                                Task {
                                    guard let val = Double(fxInput.replacingOccurrences(of: ",", with: ".")), val > 0 else { return }
                                    fxSaving = true
                                    defer { fxSaving = false }
                                    try? await AdminAPI.shared.setFxOverride(rate: val, ttlMinutes: 12*60) // 12h default
                                    fxInfo = try? await AdminAPI.shared.getFxInfo()
                                    fxInput = String(format: "%.6f", fxInfo?.vesPerUsd ?? val)
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                }
                            } label: {
                                if fxSaving { ProgressView() }
                                else { Text("Save").font(.subheadline.bold()) }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.gold)

                            Button {
                                Task {
                                    fxSaving = true
                                    defer { fxSaving = false }
                                    try? await AdminAPI.shared.clearFxOverride()
                                    fxInfo = try? await AdminAPI.shared.getFxInfo()
                                    fxInput = String(format: "%.6f", fxInfo?.vesPerUsd ?? 0)
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                }
                            } label: {
                                Text("Clear").font(.subheadline.bold())
                            }
                            .buttonStyle(.bordered)
                        }

                        if let info = fxInfo {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Current: \(String(format: "%.6f", info.vesPerUsd))")
                                if let until = info.overrideUntil, info.overrideActive == true {
                                    Text("Override until: \(until)")
                                }
                                Text("Source: \(info.source ?? "-") • Fallback: \(String(format: "%.4f", info.fallback ?? 0))")
                            }
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.75))
                        }
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            .textCase(nil)


            if needsSearch(selectedTab) {
                Section {
                    SearchBar(text: $search)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                }
                .textCase(nil)
                .listRowBackground(Color.clear)
            }

            if let error {
                Section {
                    GlassCard {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.octagon.fill").foregroundColor(.red)
                            Text("Error: \(error)").foregroundColor(.white)
                            Spacer()
                            Button("Retry") { Task { await load() } }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .textCase(nil)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            switch selectedTab {
            case .overview:
                OverviewSection(events: events, resales: resales)
            case .events:
                EventsSection(events: filteredEvents, expandedEventId: $expandedEventId, onDelete: deleteEvent)
            case .users:
                UsersSection(users: filteredUsers, onTogglePermission: updatePermission, onDelete: deleteUser)
            case .resales:
                ResalesSection(resales: filteredResales, onDelete: deleteResale)
            case .liveOps:
                PlaceholderSection(title: "Live Ops",
                                   subtitle: "Live check-ins, door staff passes, and re-entry controls are next.")
            case .marketing:
                PlaceholderSection(title: "Marketing",
                                   subtitle: "Push campaigns, discount codes, and promoter insights will appear here.")
            case .audit:
                PlaceholderSection(title: "Audit",
                                   subtitle: "View changes, refunds, bans, and suspicious activity once enabled.")
            }
        }
        .id(selectedTab)                          // 👈 important: avoid diffing across very different bodies
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .foregroundColor(.white)
        .background(Color.clear)
    }


    // MARK: - Computed

    private var totalRevenue: Double { events.reduce(0) { $0 + $1.totalRevenue } }
    private var totalSold: Int { events.reduce(0) { $0 + $1.soldTickets } }

    private func configureAppearance() {
        let table = UITableView.appearance()
        table.backgroundColor = .clear
        table.separatorStyle = .none

        let cell = UITableViewCell.appearance()
        cell.backgroundColor = .clear
        cell.contentView.backgroundColor = .clear

        let header = UITableViewHeaderFooterView.appearance()
        header.backgroundView = UIView()
        header.tintColor = .clear

        let seg = UISegmentedControl.appearance()
        seg.selectedSegmentTintColor = UIColor(white: 1, alpha: 0.18)
        seg.setTitleTextAttributes([.foregroundColor: UIColor.white.withAlphaComponent(0.85)], for: .normal)
        seg.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        seg.setTitleTextAttributes([.foregroundColor: UIColor.lightGray], for: .disabled)
        seg.setBackgroundImage(UIImage(), for: .normal, barMetrics: .default)
        seg.setDividerImage(UIImage(), forLeftSegmentState: .normal, rightSegmentState: .normal, barMetrics: .default)
    }

    private func needsSearch(_ tab: Tab) -> Bool {
        tab == .users || tab == .events || tab == .resales
    }

    // MARK: - Filters

    private var trimmedSearch: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var filteredUsers: [AdminUser] {
        guard !trimmedSearch.isEmpty else { return users }
        return users.filter {
            $0.email.localizedCaseInsensitiveContains(trimmedSearch) ||
            $0.firstName.localizedCaseInsensitiveContains(trimmedSearch) ||
            $0.lastName.localizedCaseInsensitiveContains(trimmedSearch)
        }
    }

    private var filteredEvents: [AdminEvent] {
        guard !trimmedSearch.isEmpty else { return events }
        return events.filter {
            $0.title.localizedCaseInsensitiveContains(trimmedSearch) ||
            $0.location.localizedCaseInsensitiveContains(trimmedSearch)
        }
    }

    private var filteredResales: [AdminResalePost] {
        guard !trimmedSearch.isEmpty else { return resales }
        return resales.filter {
            ($0.title.localizedCaseInsensitiveContains(trimmedSearch)) ||
            (($0.description ?? "").localizedCaseInsensitiveContains(trimmedSearch)) ||
            (($0.sellerEmail ?? "").localizedCaseInsensitiveContains(trimmedSearch))
        }
    }

    // MARK: - Data

    @MainActor
    private func load() async {
        guard TokenManager.shared.getAccessToken() != nil else {
            self.error = "Not logged in or token missing."
            self.users = []; self.events = []; self.resales = []
            return
        }
        
        

        loading = true; defer { loading = false }
        error = nil
        do {
            async let u = AdminAPI.shared.getUsers()
            async let e = AdminAPI.shared.getEvents()
            async let r = AdminAPI.shared.getResales()
            async let fx = AdminAPI.shared.getFxInfo()
            let (uu, ee, rr, fi) = try await (u, e, r, fx)
            users = uu; events = ee; resales = rr
            fxInfo = fi
            fxInput = String(format: "%.6f", fi.vesPerUsd)

        } catch {
            self.error = error.localizedDescription
        }
    }

    private func updatePermission(_ user: AdminUser, _ allow: Bool) {
        Task {
            do {
                try await AdminAPI.shared.setUserPermission(userId: user.id, allow: allow)
                await MainActor.run {
                    if let idx = users.firstIndex(where: { $0.id == user.id }) {
                        users[idx].canCreateEvents = allow
                    }
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    private func deleteUser(_ id: Int) {
        Task {
            do {
                try await AdminAPI.shared.deleteUser(userId: id)
                await MainActor.run { users.removeAll { $0.id == id } }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    private func deleteEvent(_ id: Int) {
        Task {
            do {
                try await AdminAPI.shared.deleteEvent(eventId: id)
                await MainActor.run { events.removeAll { $0.id == id } }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    private func deleteResale(_ id: Int) {
        Task {
            do {
                try await AdminAPI.shared.deleteResale(id: id)
                await MainActor.run { resales.removeAll { $0.id == id } }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
}

// MARK: - Header (moved inside List so it scrolls)

private struct HeaderSection: View {
    @Binding var selectedTab: AdminDashboardView.Tab
    let totalRevenue: Double
    let totalSold: Int
    let eventsCount: Int
    let openResales: Int
    let soldResales: Int

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Manage users, events, and secondary market in one place.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal)

            // 👇 FIX: give the nested horizontal ScrollView a stable height
            TabsBar(selected: $selectedTab)
                .frame(height: 44)
                .padding(.horizontal)

            PinnedHeaderStats(
                totalRevenue: totalRevenue,
                totalSold: totalSold,
                eventsCount: eventsCount,
                openResales: openResales,
                soldResales: soldResales
            )
            .padding(.horizontal)
        }
        // Ensure the row computes a stable height during self-sizing
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct TabsBar: View {
    @Binding var selected: AdminDashboardView.Tab
    private let tabs: [AdminDashboardView.Tab] = [.overview, .events, .users, .resales, .liveOps, .marketing, .audit]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(tabs, id: \.self) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { selected = tab }
                    } label: {
                        Text(tab.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(selected == tab ? Color.white.opacity(0.18) : Color.white.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(selected == tab ? Color.gold.opacity(0.6) : Color.white.opacity(0.15),
                                            lineWidth: selected == tab ? 1.2 : 1)
                            )
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(.vertical, 4)
            // 🔻 removed: `.frame(maxHeight: .infinity, alignment: .center)`
        }
        .frame(height: 44)   // fixed, stable height
    }
}


// MARK: - Pinned Header (unchanged)

struct PinnedHeaderStats: View {
    let totalRevenue: Double
    let totalSold: Int
    let eventsCount: Int
    let openResales: Int
    let soldResales: Int

    private static let gridCols: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Stats").font(.headline)

            LazyVGrid(columns: Self.gridCols, spacing: 12) {
                StatCarde(
                    title: "Revenue",
                    value: currency(totalRevenue),
                    icon: "dollarsign.square.fill",
                    subtitle: "From paid tickets",
                    tint: .gold
                )
                .gridCellColumns(2)

                StatCarde(
                    title: "Sold",
                    value: "\(totalSold)",
                    icon: "ticket.fill",
                    subtitle: "Tickets",
                    tint: .green
                )

                StatCarde(
                    title: "Events",
                    value: "\(eventsCount)",
                    icon: "calendar",
                    subtitle: "Active",
                    tint: .blue
                )

                StatCarde(
                    title: "Resales (Open)",
                    value: "\(openResales)",
                    icon: "arrow.triangle.2.circlepath",
                    subtitle: nil,
                    tint: .yellow
                )

                StatCarde(
                    title: "Resales (Sold)",
                    value: "\(soldResales)",
                    icon: "checkmark.seal.fill",
                    subtitle: nil,
                    tint: .green
                )
            }
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    private func currency(_ d: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: d as NSNumber) ?? "$0"
    }
}

// MARK: - Overview

private struct OverviewSection: View {
    let events: [AdminEvent]
    let resales: [AdminResalePost]
    
    
    var body: some View {
        Section {
            GlassCard {
                HStack(spacing: 10) {
                    QuickActionButton(title: "Create Event", icon: "plus.circle.fill") { }
                    QuickActionButton(title: "Send Push", icon: "paperplane.fill", tint: .blue) { }
                    QuickActionButton(title: "Export CSV", icon: "square.and.arrow.down.fill", tint: .green) { }
                }
            }
            .listRowInsets(EdgeInsets())

            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text("Top Events").font(.headline); Spacer() }
                    ForEach(topEvents, id: \.id) { e in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(e.title).font(.subheadline.bold())
                                Spacer()
                                Text(currency(e.totalRevenue))
                                    .foregroundColor(.gold)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            ProgressBar(value: progress(for: e)).frame(height: 10)
                            HStack {
                                Text("\(e.soldTickets)/\(e.totalTickets) sold")
                                    .font(.caption).foregroundColor(.white.opacity(0.7))
                                Spacer()
                                if e.soldTickets > e.totalTickets {
                                    Text("⚠︎ Oversold").font(.caption).foregroundColor(.red)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        Divider().background(.white.opacity(0.1))
                    }
                }
            }
            .listRowInsets(EdgeInsets())
        }
        .textCase(nil)
        .listRowBackground(Color.clear)
    }

    private var topEvents: [AdminEvent] {
        Array(events.sorted { $0.totalRevenue > $1.totalRevenue }.prefix(5))
    }
    private func progress(for e: AdminEvent) -> Double {
        guard e.totalTickets > 0 else { return 0 }
        return min(1.0, Double(e.soldTickets) / Double(e.totalTickets))
    }
    private func currency(_ d: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"
        return f.string(from: d as NSNumber) ?? "$0"
    }
}

// MARK: - Events

private struct EventsSection: View {
    let events: [AdminEvent]
    @Binding var expandedEventId: Int?
    let onDelete: (Int) -> Void

    var body: some View {
        Section {
            if events.isEmpty {
                EmptyState(text: "No events yet")
                    .listRowInsets(EdgeInsets())
            } else {
                ForEach(events) { e in
                    EventRow(
                        event: e,
                        expanded: expandedEventId == e.id,
                        onToggle: { withAnimation { expandedEventId = (expandedEventId == e.id ? nil : e.id) } },
                        onDelete: { onDelete(e.id) }
                    )
                    .listRowInsets(EdgeInsets())
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            onDelete(e.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onDelete { indexSet in
                    indexSet.map { events[$0].id }.forEach(onDelete)
                }
            }
        }
        .textCase(nil)
        .listRowBackground(Color.clear)
    }
}

private struct EventRow: View {
    let event: AdminEvent
    let expanded: Bool
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title).font(.headline)
                        Text(event.location).font(.footnote).foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.subheadline)
                }

                if expanded {
                    Divider().background(.white.opacity(0.15))
                    let remaining = max(event.totalTickets - event.soldTickets, 0)
                    let pct = event.totalTickets > 0 ? Double(event.soldTickets)/Double(event.totalTickets) : 0
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Analytics").font(.subheadline.bold())
                        HStack {
                            Text("Sold: \(event.soldTickets)")
                            Spacer()
                            Text("Remaining: \(remaining)")
                        }
                        ProgressBar(value: min(1, pct)).frame(height: 10)
                        HStack {
                            Text(String(format: "Revenue: $%.2f", event.totalRevenue))
                                .foregroundColor(.gold)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Spacer()
                            if event.soldTickets > event.totalTickets {
                                Text("⚠︎ Oversold").foregroundColor(.red).font(.caption.bold())
                            }
                        }
                        NavigationLink {
                            EventAnalyticsView(eventId: event.id)
                        } label: {
                            Label("View Charts", systemImage: "chart.xyaxis.line")
                                .font(.subheadline.bold())
                        }
                        .padding(.top, 6)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggle)
        }
    }
}

// MARK: - Users

private struct UsersSection: View {
    let users: [AdminUser]
    let onTogglePermission: (AdminUser, Bool) -> Void
    let onDelete: (Int) -> Void

    var body: some View {
        Section {
            if users.isEmpty {
                EmptyState(text: "No users found")
                    .listRowInsets(EdgeInsets())
            } else {
                ForEach(users) { u in
                    GlassCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(u.email).bold()
                                    .lineLimit(1).minimumScaleFactor(0.8)
                                Text("\(u.firstName) \(u.lastName)")
                                    .font(.footnote).foregroundColor(.white.opacity(0.7))
                                Text((u.role ?? "User"))
                                    .font(.caption2).foregroundColor(.white.opacity(0.6))
                            }
                            Spacer()
                            Toggle(isOn: Binding(
                                get: { u.canCreateEvents },
                                set: { onTogglePermission(u, $0) }
                            )) { Text("Create Events").font(.caption2) }
                                .labelsHidden()
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            onDelete(u.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onDelete { indexSet in
                    indexSet.map { users[$0].id }.forEach(onDelete)
                }
            }
        }
        .textCase(nil)
        .listRowBackground(Color.clear)
    }
}

// MARK: - Resales

private struct ResalesSection: View {
    let resales: [AdminResalePost]
    let onDelete: (Int) -> Void

    var body: some View {
        Section {
            if resales.isEmpty {
                EmptyState(text: "No resale posts")
                    .listRowInsets(EdgeInsets())
            } else {
                ForEach(resales) { p in
                    GlassCard {
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(p.title).font(.headline)
                                        .lineLimit(1).minimumScaleFactor(0.8)
                                    if p.sold == true {
                                        Text("SOLD").font(.caption2.bold())
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Color.green.opacity(0.25), in: Capsule())
                                    }
                                }
                                if let d = p.description, !d.isEmpty {
                                    Text(d).font(.footnote).foregroundColor(.white.opacity(0.8))
                                }
                                HStack(spacing: 12) {
                                    if let price = p.price {
                                        Text(String(format: "$%.2f", price))
                                            .foregroundColor(.gold).font(.subheadline.bold())
                                            .lineLimit(1).minimumScaleFactor(0.8)
                                    }
                                    if let email = p.sellerEmail {
                                        Label(email, systemImage: "person.circle")
                                            .font(.caption).foregroundColor(.white.opacity(0.8))
                                            .lineLimit(1).minimumScaleFactor(0.8)
                                    }
                                }
                            }
                            Spacer()
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            onDelete(p.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onDelete { indexSet in
                    indexSet.map { resales[$0].id }.forEach(onDelete)
                }
            }
        }
        .textCase(nil)
        .listRowBackground(Color.clear)
    }
}

// MARK: - Placeholder

private struct PlaceholderSection: View {
    let title: String
    let subtitle: String

    var body: some View {
        Section {
            GlassCard {
                VStack(spacing: 14) {
                    Text(title)
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.leading)

                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            Text("Coming soon")
                                .font(.headline.weight(.semibold))
                                .foregroundColor(.white.opacity(0.6))
                        )
                        .frame(height: 140)
                }
            }
            .listRowInsets(EdgeInsets())
        }
        .textCase(nil)
        .listRowBackground(Color.clear)
    }
}

// MARK: - Shared UI

struct GlassCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.10), lineWidth: 1))
    }
}

struct ProgressBar: View {
    let value: Double // 0...1
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.12))
                RoundedRectangle(cornerRadius: 8).fill(Color.gold)
                    .frame(width: max(8, CGFloat(value) * geo.size.width))
            }
        }
        .frame(height: 10)
    }
}

struct EmptyState: View {
    let text: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray").font(.largeTitle).foregroundColor(.white.opacity(0.5))
            Text(text).foregroundColor(.white.opacity(0.7))
        }
        .padding(.vertical, 24)
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    var tint: Color = .gold
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.headline)
                Text(title).font(.subheadline.bold())
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(tint.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.35)))
        }
        .foregroundColor(.white)
    }
}

struct StatCarde: View {
    let title: String
    let value: String
    let icon: String
    let subtitle: String?
    var tint: Color = .gold
    var body: some View {
        GlassCard {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title2.bold()).foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(value)
                        .font(.title3.bold())
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .allowsTightening(true)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                Spacer()
            }
        }
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


