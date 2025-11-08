//
//  EventDetailView.swift
//  WKND
//
//  Promoter-safe version
//  - Uses /api/promoters/me + /api/promoters/event/{id}/dashboard (stable DTOs)
//  - Defensive JSON checks (prevents “Unexpected end of file” crashes)
//  - Share URL uses wkndevent.com
//

import SwiftUI
import MapKit
import UIKit
import Charts
import PassKit

struct EventDetailView: View {
    @AppStorage("selectedLanguage") var lang: String = "en"
    @State var event: Event
    @Binding var allEvents: [Event]
    @EnvironmentObject var userSession: UserSession
    @Environment(\.dismiss) var dismiss
    
    @State private var purchasedTickets: [TicketDTO] = []
    @State private var isFetchingTickets = false
    @State private var showRegisterSheet = false
    @State private var showShareSheet = false
    @State private var showHandle = false
    @State private var appear = false
    @State private var message = ""
    @State private var showEditView = false
    @State private var showAnalyticsView = false
    @State private var showScannerView = false
    
    // ADD near your other @State vars:
    @State private var directChatDTO: ChatRoomSummaryDTO? = nil

    // Safer conversion; avoids Optional<Int> issues
    private var currentUserId: Int { Int(userSession.userId) ?? 0 }
    
    @State private var shareURL: URL? = nil
    @State private var isFetchingShareLink = false
    
    @State private var eventPromoters: [PromoterEvent] = []
    @State private var showAddPromoterSheet = false
    @State private var showPromoterDashboard = false
    
    @State private var isPromoterForEvent = false
    @State private var promoterStats: PromoterEvent? = nil
    @State private var referredBuyers: [ReferredBuyerDTO] = []
    @State private var showPromoterStats = false
    
    @State private var directChatSummary: ChatRoomSummary?
    @State private var showChatView = false
    
    @State private var selectedTab: String = "overview" // "overview" or "dashboard"
    
    @State private var goingUsers: [Attendee] = []
    @State private var isLoadingGoing = false
    @State private var showGoingList = false

    var coordinate: CLLocationCoordinate2D? {
        if let lat = event.latitude, let lng = event.longitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        return nil
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.3))
                .frame(width: 40, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 6)
                .opacity(showHandle ? 1 : 0)
                .offset(y: showHandle ? 0 : -10)
                .animation(.easeOut(duration: 0.3), value: showHandle)
            
            ScrollView {
                VStack(spacing: 16) {
                    // ✅ Tab Switcher — only for reunions
                    if event.type == "reunion" {
                        HStack(spacing: 0) {
                            Button(action: {
                                selectedTab = "overview"
                            }) {
                                Text(lang == "es" ? "Vista General" : "Overview")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(selectedTab == "overview" ? Color.gold : Color.clear)
                                    .foregroundColor(selectedTab == "overview" ? .black : .white.opacity(0.6))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            
                            Button(action: {
                                selectedTab = "dashboard"
                            }) {
                                Text(lang == "es" ? "Panel" : "Dashboard")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(selectedTab == "dashboard" ? Color.gold : Color.clear)
                                    .foregroundColor(selectedTab == "dashboard" ? .black : .white.opacity(0.6))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .padding(.horizontal)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                    
                    // ✅ Overview tab (or default for normal events)
                    if selectedTab == "overview" || event.type != "reunion" {
                        VStack(spacing: 24) {
                            eventImageSection
                            eventInfoSection
                            registerButtons
                            
                            // "Going" strip
                            if isLoadingGoing {
                                HStack(spacing: 8) {
                                    ProgressView().tint(.gold)
                                    Text(lang == "es" ? "Cargando asistentes..." : "Loading attendees...")
                                        .foregroundColor(.white.opacity(0.8))
                                        .font(.footnote)
                                    Spacer()
                                }
                                .padding(.horizontal)
                            } else if !goingUsers.isEmpty {
                                Button {
                                    showGoingList = true
                                } label: {
                                    HStack(alignment: .center, spacing: 12) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(lang == "es" ? "Asistirán" : "Going")
                                                .font(.subheadline.bold())
                                                .foregroundColor(.white)

                                            Text(goingSubtitleText())
                                                .foregroundColor(.white.opacity(0.7))
                                                .font(.caption)
                                                .lineLimit(1)
                                        }

                                        Spacer(minLength: 8)

                                        OverlappingAvatarStack(attendees: goingUsers, maxCount: 6, size: 30)

                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.white.opacity(0.45))
                                    }
                                    .padding(12)
                                    .background(Color.white.opacity(0.05))
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal)
                            }

                            if isOwnerOrAdmin && event.type != "reunion" {
                                Button(action: {
                                    showPromoterDashboard = true
                                }) {
                                    HStack {
                                        Image(systemName: "person.3.fill")
                                        Text(lang == "es" ? "Administracion" : "Management")
                                    }
                                    .font(.headline)
                                    .foregroundColor(.black)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color.gold)
                                    .cornerRadius(12)
                                    .padding(.horizontal)
                                }
                            }
                            
                            aboutSection
                            mapSection
                            qrCodeSection
                            errorSection
                        }
                        .padding(.top)
                    }
                    
                    // ✅ Dashboard tab — only for reunions
                    else if selectedTab == "dashboard" {
                        ReunionDashboardView(
                            budgetGoal: event.budgetGoal ?? 0,
                            attendees: event.reunionGuests ?? [],
                            isOwner: isOwnerOrAdmin,
                            eventId: event.id
                        )
                        .padding(.top)
                    }
                }
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 30)
                .animation(.easeOut(duration: 0.4), value: appear)
            }
        }
        .background(
            LinearGradient(colors: [Color.black, .deepNavy], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
        )
        .onAppear {
            DispatchQueue.main.async {
                withAnimation {
                    showHandle = true
                    appear = true
                }
            }
            fetchTickets()
            checkIfPromoter()
            fetchGoing()
        }
        // …WITH this
        .fullScreenCover(item: $directChatDTO) { room in
            NavigationStack {
                ChatRoomView(room: room, myUserId: currentUserId)
            }
        }
        .fullScreenCover(isPresented: $showPromoterDashboard) {
            EventPromoterDashboardView(event: event)
        }
        .fullScreenCover(isPresented: $showPromoterStats) {
            PromoterSelfView(eventId: event.id)
        }
        .sheet(isPresented: $showScannerView) {
            TicketValidationViewForScanner(eventId: event.id)
        }
        .sheet(isPresented: $showGoingList) {
            GoingListView(
                eventId: event.id,
                lang: lang,
                initial: goingUsers
            )
        }
        .sheet(isPresented: $showAnalyticsView) {
            EventAnalyticsView(eventId: event.id)
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ActivityViewController(activityItems: [url])
            } else {
                ProgressView(lang == "es" ? "Preparando link..." : "Preparing link...")
                    .padding()
                    .background(Color.black)
                    .cornerRadius(12)
            }
        }
        .sheet(isPresented: $showRegisterSheet) {
            RegisterTicketView(
                event: event,
                userEmail: userSession.email,
                onComplete: { tickets in
                    self.purchasedTickets = tickets
                    self.refreshEvent()
                    self.showRegisterSheet = false
                }
            )
        }
        .sheet(isPresented: $showEditView) {
            EditEventView(event: event, onSave: { updated in
                self.event = updated
                if let index = allEvents.firstIndex(where: { $0.id == updated.id }) {
                    allEvents[index] = updated
                } else {
                    allEvents.append(updated)
                }
            }, onDelete: {
                onEventDeleted()
            })
        }
    }
    
    private var eventImageSection: some View {
        RemoteImageBox(
            urlString: event.imageUrl,
            fallbackImageName: "defaultEvent",
            aspectRatio: 16.0/9.0,
            fill: true,
            cornerRadius: 20
        )
        .padding(.horizontal)
    }
    
    private var eventInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(event.title)
                    .font(.title.bold())
                    .foregroundColor(.white)
                
                Spacer()
                
                if isOwnerOrAdmin {
                    HStack(spacing: 12) {
                        if event.type != "reunion" {
                            Button(action: {
                                showAnalyticsView = true
                            }) {
                                Image(systemName: "chart.bar.xaxis")
                                    .foregroundColor(.blue)
                                    .padding(8)
                                    .background(Color.white.opacity(0.1))
                                    .clipShape(Circle())
                            }
                            
                            Button(action: {
                                showScannerView = true
                            }) {
                                Image(systemName: "qrcode.viewfinder")
                                    .foregroundColor(.yellow)
                                    .padding(8)
                                    .background(Color.white.opacity(0.1))
                                    .clipShape(Circle())
                            }
                        }
                        
                        Button(action: {
                            showEditView = true
                        }) {
                            Image(systemName: "square.and.pencil")
                                .foregroundColor(.gold)
                                .padding(8)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                    }
                } else if isPromoterForEvent && event.type != "reunion" {
                    HStack(spacing: 12) {
                        Button(action: { showPromoterStats = true }) {
                            Image(systemName: "chart.bar.xaxis")
                                .foregroundColor(.green)
                                .padding(8)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                        Button(action: { showScannerView = true }) {
                            Image(systemName: "qrcode.viewfinder")
                                .foregroundColor(.yellow)
                                .padding(8)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                    }
                }
            }
            
            Text(formattedDate(event.dateTime))
                .foregroundColor(.white.opacity(0.8))
                .font(.subheadline)
            
            HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse").foregroundColor(.mint)
                Text(event.location)
                    .foregroundColor(.white.opacity(0.8))
                    .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }
    
    private var isOwnerOrAdmin: Bool {
        userSession.role == "ADMIN" || event.createdByEmail == userSession.email
    }
    
    private var registerButtons: some View {
        HStack(spacing: 16) {
            Button(action: { showRegisterSheet = true }) {
                VStack {
                    Image(systemName: "plus")
                    Text(lang == "es" ? "Registarse" : "Register").font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .foregroundColor(.black)
                .background(Color.gold)
                .cornerRadius(16)
            }
            
            Button(action: {
                Task { await startDirectChat() }
            }) {
                VStack {
                    Image(systemName: "envelope")
                    Text(lang == "es" ? "Contactar" : "Contact").font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .foregroundColor(.white)
                .background(Color.white.opacity(0.08))
                .cornerRadius(16)
            }
            
            Button(action: openShareSheet) {
                VStack {
                    Image(systemName: "square.and.arrow.up")
                    Text(lang == "es" ? "Compartir" : "Share").font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .foregroundColor(.white)
                .background(Color.white.opacity(0.08))
                .cornerRadius(16)
            }
        }
        .padding(.horizontal)
    }
    
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(lang == "es" ? "Informacion" : "About").font(.headline).foregroundColor(.white)
            Text(event.description).foregroundColor(.white.opacity(0.85)).font(.body)
            Divider().background(Color.white.opacity(0.2))
        }
        .padding(.horizontal)
    }
    
    private var mapSection: some View {
        Group {
            if let coord = coordinate {
                let region = MKCoordinateRegion(center: coord, span: .init(latitudeDelta: 0.01, longitudeDelta: 0.01))
                let pin = IdentifiableCoordinate(coordinate: coord)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(lang == "es" ? "Ubicacion" : "Location").font(.headline).foregroundColor(.white)
                    Map(coordinateRegion: .constant(region), annotationItems: [pin]) { item in
                        MapMarker(coordinate: item.coordinate, tint: .red)
                    }
                    .frame(height: 200)
                    .cornerRadius(16)
                    .onTapGesture { openInMaps() }
                }
                .padding(.horizontal)
            }
        }
    }
    
    private var qrCodeSection: some View {
        Group {
            if isFetchingTickets {
                ProgressView(lang == "es" ? "Cargando tu ticket..." : "Loading your tickets...")
                    .foregroundColor(.white)
                    .padding(.top)
            } else {
                let eventTickets = purchasedTickets.filter { $0.eventId == event.id }
                
                if !eventTickets.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(lang == "es" ? "🎫 Tus Tickets" : "🎫 Your Tickets")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal)
                        
                        TabView {
                            ForEach(eventTickets, id: \.id) { ticket in
                                TicketCardView(ticket: ticket, event: event, lang: lang)
                            }
                        }
                        .frame(height: 410)
                        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
                    }
                    .padding(.top)
                }
            }
        }
    }

    private var errorSection: some View {
        Group {
            if !message.isEmpty {
                Text(message)
                    .foregroundColor(.red)
                    .font(.footnote)
                    .padding(.top, 8)
            }
        }
    }
    
    // Build the "Followed by Ana, Mike and more" line without heavy inline logic
    private func goingSubtitleText() -> String {
        let names = goingUsers.compactMap { $0.username }.filter { !$0.isEmpty }
        if names.isEmpty {
            return "\(goingUsers.count) " + (lang == "es" ? "personas" : "people")
        }
        let shown = Array(names.prefix(2))
        let head = shown.joined(separator: ", ")
        let suffix = names.count > 2 ? (lang == "es" ? " y más" : " and more") : ""
        return (lang == "es" ? "Seguido por " : "Followed by ") + head + suffix
    }

    private func fetchGoing() {
        guard let token = TokenManager.shared.getAccessToken() else { return }
        guard let url = URL(string: "https://backendevent-etce.onrender.com/api/attendance/events/\(event.id)/going") else { return }

        isLoadingGoing = true
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: req) { data, resp, _ in
            DispatchQueue.main.async {
                self.isLoadingGoing = false
                guard let data = data else { return }
                if let decoded = try? JSONDecoder().decode([Attendee].self, from: data) {
                    self.goingUsers = decoded
                } else {
                    self.goingUsers = []
                }
            }
        }.resume()
    }
    
    /// Tries to get the organizer's userId for this event.
    /// Uses event.createdByEmail -> /api/users/by-email/{email} (or common fallbacks).
    private func resolveOrganizerUserId() async -> Int? {
        // If your Event later adds a direct userId field, you can early-return it here.

        // Use createdByEmail (present in your model)
        guard let rawEmail = event.createdByEmail,
              let email = rawEmail.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              !email.isEmpty else { return nil }


        // Try common endpoints your backend likely exposes.
        // These calls compile either way; if the server doesn’t have the path it just returns nil.
        let candidates: [String] = [
            "https://backendevent-etce.onrender.com/api/users/by-email/\(email)",
            "https://backendevent-etce.onrender.com/user/by-email/\(email)"
        ]

        for urlString in candidates {
            guard let url = URL(string: urlString) else { continue }

            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            if let t = TokenManager.shared.getAccessToken() {
                req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
            }

            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { continue }

                // Accept a few shapes: {id:Int,...} or {user:{id:Int}} etc.
                struct Flat: Decodable { let id: Int? }
                struct Wrapped: Decodable { let user: Flat?; let data: Flat? }

                if let flat = try? JSONDecoder().decode(Flat.self, from: data), let id = flat.id {
                    return id
                }
                if let w = try? JSONDecoder().decode(Wrapped.self, from: data),
                   let id = w.user?.id ?? w.data?.id {
                    return id
                }
                // Generic dictionary fallback
                if let map = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let id = map["id"] as? Int { return id }
                    if let user = map["user"] as? [String: Any], let id = user["id"] as? Int { return id }
                    if let data = map["data"] as? [String: Any], let id = data["id"] as? Int { return id }
                }
            } catch {
                // try next candidate
            }
        }
        return nil
    }

    // In EventDetailView.swift

    // Replace your startDirectChat() with this:
    private func startDirectChat() async {
        // Prefer the organizer id on the event; fall back to email lookup if missing
        let organizerId: Int
        if let id = event.createdBy?.id {
            organizerId = id
        } else if let id = await resolveOrganizerUserId() {
            organizerId = id
        } else {
            await MainActor.run {
                self.message = (lang == "es" ? "No se pudo encontrar al organizador." : "Couldn’t find the organizer.")
            }
            return
        }

        // Prevent self-DM by id
        if organizerId == currentUserId {
            await MainActor.run {
                self.message = (lang == "es" ? "No puedes chatear contigo mismo." : "You can’t chat with yourself.")
            }
            return
        }

        // Ensure REST calls include the JWT
        ChatAPI.shared.setTokenProvider { TokenManager.shared.getAccessToken() }

        do {
            // Create or fetch the DIRECT room for this pair + event
            let roomId = try await ChatAPI.shared.startDirect(eventId: event.id, otherUserId: organizerId)

            // Optionally resolve room meta after creation
            let summaries = try? await ChatAPI.shared.myRooms()
            let resolved = summaries?.first(where: { $0.id == roomId })

            await MainActor.run {
                self.directChatDTO = resolved ?? ChatRoomSummaryDTO(
                    id: roomId,
                    // NOTE: if your enum is lowerCamelCase, change `.DIRECT` to `.direct`
                    type: .DIRECT,
                    displayName: event.title,
                    iconUrl: (event.imageUrl?.isEmpty == false) ? event.imageUrl : nil,
                    lastMessagePreview: nil,
                    lastMessageAt: nil,
                    unreadCount: 0
                )
            }
        } catch {
            await MainActor.run {
                self.message = (lang == "es" ? "No se pudo abrir el chat." : "Couldn't open chat.")
            }
        }
    }

    // MARK: Promoter check (stable DTOs, no /my-stats)
    func checkIfPromoter() {
        guard let token = TokenManager.shared.getAccessToken() else { return }
        
        // 1) /api/promoters/me
        var meReq = URLRequest(url: URL(string: "https://backendevent-etce.onrender.com/api/promoters/me")!)
        meReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: meReq) { meData, meResp, _ in
            guard let http = meResp as? HTTPURLResponse, http.statusCode == 200, let meData = meData else {
                DispatchQueue.main.async { self.isPromoterForEvent = false }
                return
            }
            if let ctype = http.value(forHTTPHeaderField: "Content-Type"),
               !ctype.lowercased().contains("application/json") {
                DispatchQueue.main.async { self.isPromoterForEvent = false }
                return
            }
            struct PromoterMeDTO: Decodable {
                let id: Int
                let referralCode: String?
                let user: InnerUser
                struct InnerUser: Decodable { let id: Int; let username: String? }
            }
            guard let me = try? JSONDecoder().decode(PromoterMeDTO.self, from: meData) else {
                DispatchQueue.main.async { self.isPromoterForEvent = false }
                return
            }
            
            // 2) /api/promoters/event/{eventId}/dashboard
            var dashReq = URLRequest(url: URL(string: "https://backendevent-etce.onrender.com/api/promoters/event/\(self.event.id)/dashboard")!)
            dashReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            URLSession.shared.dataTask(with: dashReq) { dData, dResp, _ in
                guard let http2 = dResp as? HTTPURLResponse, http2.statusCode == 200, let dData = dData else {
                    DispatchQueue.main.async { self.isPromoterForEvent = false }
                    return
                }
                if let ctype = http2.value(forHTTPHeaderField: "Content-Type"),
                   !ctype.lowercased().contains("application/json") {
                    DispatchQueue.main.async { self.isPromoterForEvent = false }
                    return
                }
                
                struct PromoterEventView: Decodable {
                    struct PromoterSummary: Decodable { let id: Int }
                    let id: Int
                    let promoter: PromoterSummary
                    let ticketsSold: Int
                }
                guard let rows = try? JSONDecoder().decode([PromoterEventView].self, from: dData) else {
                    DispatchQueue.main.async { self.isPromoterForEvent = false }
                    return
                }
                if let mine = rows.first(where: { $0.promoter.id == me.id }) {
                    DispatchQueue.main.async {
                        self.isPromoterForEvent = true
                        self.promoterStats = PromoterEvent(
                            id: mine.id,
                            ticketsSold: mine.ticketsSold,
                            event: self.event,
                            promoter: PromoterDTO(
                                id: me.id,
                                referralCode: me.user.username ?? me.referralCode ?? "",
                                user: UserDTO(id: me.user.id,firstName: "", lastName: "", username: me.user.username ?? "")
                            ), grossRevenue: nil
                        )
                    }
                } else {
                    DispatchQueue.main.async { self.isPromoterForEvent = false }
                }
            }.resume()
        }.resume()
    }

    func refreshEvent() {
        guard let url = URL(string: "https://backendevent-etce.onrender.com/events/\(event.id)"),
              let token = TokenManager.shared.getAccessToken() else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data = data,
               let updated = try? JSONDecoder().decode(Event.self, from: data) {
                DispatchQueue.main.async {
                    self.event = updated
                }
            }
        }.resume()
    }

    func fetchTickets() {
        guard let url = URL(string: "https://backendevent-etce.onrender.com/api/tickets/my?email=\(userSession.email)"),
              let token = TokenManager.shared.getAccessToken() else { return }

        isFetchingTickets = true

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                self.isFetchingTickets = false
                if let data = data,
                   let tickets = try? JSONDecoder().decode([TicketDTO].self, from: data) {
                    self.purchasedTickets = tickets
                }
            }
        }.resume()
    }

    func formattedDate(_ isoString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        guard let date = formatter.date(from: isoString) else { return isoString }

        let output = DateFormatter()
        output.dateFormat = "EEEE, MMM d 'at' h:mm a"
        return output.string(from: date)
    }
    
    func openShareSheet() {
        prepareShareURL()
        showShareSheet = true
    }

    func prepareShareURL() {
        guard let token = TokenManager.shared.getAccessToken() else {
            self.shareURL = URL(string: "https://wkndevent.com/#/events/\(event.id)")
            return
        }
        var req = URLRequest(url: URL(string: "https://backendevent-etce.onrender.com/api/promoters/me")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: req) { data, _, _ in
            DispatchQueue.main.async {
                struct Me: Decodable { struct U: Decodable { let username: String? }
                    let referralCode: String?; let user: U
                }
                if let data, let me = try? JSONDecoder().decode(Me.self, from: data) {
                    let ref = (me.referralCode) ?? (me.user.username)
                    if let ref {
                        self.shareURL = URL(string: "https://wkndevent.com/#/events/\(self.event.id)")
                    } else {
                        self.shareURL = URL(string: "https://wkndevent.com/#/events/\(self.event.id)")
                    }
                } else {
                    self.shareURL = URL(string: "https://wkndevent.com/#/events/\(self.event.id)")
                }
            }
        }.resume()
    }

    func openInMaps() {
        guard let coord = coordinate else { return }
        let placemark = MKPlacemark(coordinate: coord)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = event.title
        mapItem.openInMaps(launchOptions: nil)
    }

    func onEventDeleted() {
        if let index = allEvents.firstIndex(where: { $0.id == event.id }) {
            withAnimation {
                allEvents.remove(at: index)
            }
        }
        dismiss()
    }
}

struct ChatRoomDTO: Codable {
    let id: Int
}

// MARK: - Custom Wallet Button View
struct WalletActionButton: View {
    let title: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: { if !isLoading { action() } }) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
                Text(title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.black)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
        .disabled(isLoading)
    }
}

// MARK: - Ticket Card View (fixed)
struct TicketCardView: View {
    let ticket: TicketDTO
    let event: Event
    let lang: String

    @State private var pkPass: PKPass?
    @State private var showAdd = false
    @State private var walletError: String?
    @State private var isLoading = false

    private static var passCache: [Int: PKPass] = [:]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .fill(
                    LinearGradient(
                        colors: [Color.deepNavy.opacity(0.96), .black.opacity(0.92)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .gold.opacity(0.17), radius: 12, x: 0, y: 7)

            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Text(ticket.tierName ?? "Ticket")
                            .font(.title2.bold())
                            .foregroundColor(.gold)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 14)
                            .background(Color.gold.opacity(0.08))
                            .cornerRadius(12)

                        Spacer()

                        if PKAddPassesViewController.canAddPasses() {
                            Button(action: {
                                if !isLoading { Task { await fetchAndPresentPass() } }
                            }) {
                                HStack(spacing: 6) {
                                    if isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    } else {
                                        Image(systemName: "wallet.pass")
                                            .imageScale(.medium)
                                    }
                                    Text(isLoading
                                         ? (lang == "es" ? "Añadiendo" : "Adding")
                                         : (lang == "es" ? "Añadir a Wallet" : "Add to Wallet"))
                                    .font(.subheadline.weight(.semibold))
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 14)
                                .background(Color.black)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .shadow(radius: 2)
                            }
                            .buttonStyle(.plain)
                            .disabled(isLoading)
                            .accessibilityLabel(lang == "es" ? "Añadir a Wallet" : "Add to Wallet")
                        } else {
                            Text(lang == "es" ? "Wallet no disponible" : "Wallet unavailable")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack {
                        if let price = priceForTicket(ticket, in: event) {
                            Text(price > 0 ? "$\(String(format: "%.2f", price))" : "FREE")
                                .font(.headline)
                                .foregroundColor(.white.opacity(0.78))
                        } else {
                            Text("—")
                                .font(.headline)
                                .foregroundColor(.white.opacity(0.78))
                        }
                        Spacer(minLength: 16)
                        Image(systemName: "calendar")
                            .foregroundColor(.gold)
                        Text(formattedDate(event.dateTime))
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.82))
                    }
                }

                if let token = TokenManager.shared.getAccessToken(),
                   let url = URL(string: "https://backendevent-etce.onrender.com/api/tickets/qr/\(ticket.id)") {
                    AuthImage(url: url, token: token, size: 220)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.black.opacity(0.95))
                            .frame(width: 220, height: 220)
                        Text("No auth / bad URL")
                            .foregroundColor(.red)
                            .font(.footnote)
                    }
                }

                HStack {
                    Label("Ticket #\(ticket.id)", systemImage: "ticket.fill")
                        .font(.subheadline.bold())
                        .foregroundColor(.white.opacity(0.89))
                }

                if let walletError {
                    Text(walletError)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }
            .padding(26)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .sheet(isPresented: $showAdd) {
            if let pkPass {
                WalletSheetWrapper(vc: PKAddPassesViewController(pass: pkPass)!)
            }
        }
    }

    private func fetchAndPresentPass() async {
        if let cached = Self.passCache[ticket.id] {
            self.pkPass = cached
            self.showAdd = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }

        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/api/passes/ticket/\(ticket.id)") else {
            await MainActor.run { walletError = "Missing auth or bad URL." }
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        await MainActor.run {
            isLoading = true
            walletError = nil
        }

        do {
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/vnd.apple.pkpass", forHTTPHeaderField: "Accept")

            let (rawData, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }

            var passData = rawData

            if let json = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any],
               let b64 = json["pkpass"] as? String,
               let decoded = Data(base64Encoded: b64) {
                passData = decoded
            }
            else if let decoded = Data(base64Encoded: rawData) {
                passData = decoded
            }

            let pass = try PKPass(data: passData)
            Self.passCache[ticket.id] = pass

            await MainActor.run {
                self.pkPass = pass
                self.showAdd = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        } catch {
            await MainActor.run {
                walletError = "Wallet error: \(error.localizedDescription)"
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }

        await MainActor.run { isLoading = false }
    }

    func formattedDate(_ isoString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        guard let date = formatter.date(from: isoString) else { return isoString }
        let output = DateFormatter()
        output.dateFormat = "EEEE, MMM d 'at' h:mm a"
        return output.string(from: date)
    }

    func priceForTicket(_ ticket: TicketDTO, in event: Event) -> Double? {
        event.ticketTiers.first(where: { $0.name == ticket.tierName })?.price
    }
}

struct WalletSheetWrapper: UIViewControllerRepresentable {
    let vc: UIViewController
    func makeUIViewController(context: Context) -> UIViewController { vc }
    func updateUIViewController(_ vc: UIViewController, context: Context) {}
}

struct IdentifiableCoordinate: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct RemoteImageBox: View {
    let urlString: String?
    let fallbackImageName: String
    let aspectRatio: CGFloat
    let fill: Bool
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(LinearGradient(colors: [.white.opacity(0.05), .white.opacity(0.02)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))

            if let s = urlString, let url = URL(string: s), !s.isEmpty {
                AsyncImage(url: url, transaction: .init(animation: .easeInOut)) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().tint(.white.opacity(0.9))
                            .transition(.opacity)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: fill ? .fill : .fit)
                            .transition(.opacity)
                    case .failure:
                        Image(fallbackImageName).resizable().scaledToFill()
                            .transition(.opacity)
                    @unknown default:
                        Image(fallbackImageName).resizable().scaledToFill()
                    }
                }
            } else {
                Image(fallbackImageName).resizable().scaledToFill()
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 8, y: 5)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// Lightweight attendee for the "Going" UI
struct Attendee: Identifiable, Hashable, Codable {
    let id: Int
    let username: String?
    let avatarUrl: String?
}

// Small reusable avatar
private struct SmallAvatar: View {
    let url: String?
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.08)).frame(width: size, height: size)
            if let s = url, let u = URL(string: s) {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                            .frame(width: size, height: size).clipShape(Circle())
                    case .empty: ProgressView().tint(.gold)
                    case .failure: Image(systemName: "person.fill").foregroundStyle(Color.gold)
                    @unknown default: EmptyView()
                    }
                }
            } else {
                Image(systemName: "person.fill").foregroundStyle(Color.gold)
            }
        }
        .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
    }
}

// Overlapping stack (like Instagram)
private struct OverlappingAvatarStack: View {
    let attendees: [Attendee]
    let maxCount: Int
    let size: CGFloat
    var body: some View {
        HStack(spacing: -10) {
            ForEach(Array(attendees.prefix(maxCount).enumerated()), id: \.offset) { _, u in
                SmallAvatar(url: u.avatarUrl, size: size)
                    .zIndex(Double(1000 - u.id))
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            }
            if attendees.count > maxCount {
                Text("+\(attendees.count - maxCount)")
                    .font(.footnote.bold()).foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
        }
    }
}

// MARK: - Tiny convenience used in prepareShareURL()
private extension Optional where Wrapped == String {
    var nilIfBlank: String? {
        guard let s = self, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return s
    }
}
