import SwiftUI
import MapKit
import UIKit
import Charts

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

                            if event.createdByEmail == userSession.email && event.type != "reunion" {
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
                            isOwner: event.createdByEmail == userSession.email,
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
            LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
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
        }
        .fullScreenCover(item: $directChatSummary) { summary in
            ChatView(chatSummary: summary, currentUserId: userSession.userId)
        }
        .fullScreenCover(isPresented: $showPromoterDashboard) {
            EventPromoterDashboardView(event: event)
        }
        .fullScreenCover(isPresented: $showPromoterStats) {
            PromoterAnalyticsView(eventId: event.id)
        }
        .sheet(isPresented: $showScannerView) {
            TicketValidationViewForScanner(eventId: event.id)
        }
        .sheet(isPresented: $showAnalyticsView) {
            EventAnalyticsView(eventId: event.id)
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ActivityViewController(activityItems: [url])
            } else {
                ProgressView(lang == "es" ? "Preparando link...": "Preparing link...").padding().background(Color.black).cornerRadius(12)
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
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(colors: [.purple.opacity(0.4), .pink.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .blur(radius: 40)
                .frame(height: 260)
                .padding(.horizontal)

            if let imageUrl = event.imageUrl,
               !imageUrl.isEmpty,
               let url = URL(string: imageUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ZStack {
                            Color.black.opacity(0.2)
                            ProgressView().tint(.white)
                        }
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Image("defaultEvent").resizable().scaledToFill()
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(height: 240)
                .frame(maxWidth: .infinity)
                .cornerRadius(20)
                .clipped()
                .padding(.horizontal)
                .shadow(color: .purple.opacity(0.4), radius: 10, x: 0, y: 6)
            } else {
                Image("defaultEvent")
                    .resizable()
                    .scaledToFill()
                    .frame(height: 240)
                    .frame(maxWidth: .infinity)
                    .cornerRadius(20)
                    .clipped()
                    .padding(.horizontal)
                    .shadow(color: .purple.opacity(0.4), radius: 10, x: 0, y: 6)
            }
        }
    }

    private var eventInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(event.title)
                    .font(.title.bold())
                    .foregroundColor(.white)

                Spacer()

                if event.createdByEmail == userSession.email {
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
                    Button(action: {
                        showPromoterStats = true
                    }) {
                        Image(systemName: "chart.bar.xaxis")
                            .foregroundColor(.green)
                            .padding(8)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
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
                startDirectChat()
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
                                VStack(spacing: 16) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 20)
                                            .fill(LinearGradient(colors: [.deepNavy, .black], startPoint: .topLeading, endPoint: .bottomTrailing))
                                            .frame(width: 320, height: 320)
                                            .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)

                                        AsyncImage(url: URL(string: "https://backendevent-etce.onrender.com\(ticket.qrCodeUrl ?? "")")) { image in
                                            image
                                                .resizable()
                                                .interpolation(.none)
                                                .scaledToFit()
                                                .frame(width: 240, height: 240)
                                                .padding()
                                        } placeholder: {
                                            ProgressView()
                                        }
                                    }

                                    Text("🎟 Ticket #\(ticket.id)")
                                        .foregroundColor(.white.opacity(0.8))
                                        .font(.subheadline)
                                    
                                    if ["zelle", "pagomovil", "cash"].contains(ticket.paymentMethod.lowercased()) && !ticket.paid {
                                        Text(lang == "es"
                                             ? "⏳ Tu pago está pendiente de aprobación por el organizador."
                                             : "⏳ Your payment is pending approval by the organizer.")
                                        .font(.footnote)
                                        .foregroundColor(.orange)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
                        .frame(height: 400)
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
    
    func startDirectChat() {
        guard let token = TokenManager.shared.getAccessToken() else { return }

        let url = URL(string: "https://backendevent-etce.onrender.com/chat/start-direct")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["eventId": event.id]
        request.httpBody = try? JSONEncoder().encode(body)

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data else { return }

            do {
                if let str = String(data: data, encoding: .utf8) {
                    print("🧾 Chat Room response: \(str)")
                }
                let decoded = try JSONDecoder().decode(ChatRoomDTO.self, from: data)
                DispatchQueue.main.async {
                    self.directChatSummary = ChatRoomSummary(
                        chatRoomId: decoded.id,                        resalePostId: nil,
                        title: "Chat with Organizer",
                        sellerName: event.createdByEmail ?? "Organizer", // or just "Organizer"
                        unreadMessages: 0,
                        buyerId: nil,
                        eventId: Int64(event.id),
                        type: "DIRECT" 
                    )
                    self.showChatView = true
                }
            } catch {
                print("❌ Failed to decode ChatRoomDTO:", error)
            }
        }.resume()
    }


    
    func checkIfPromoter() {
        guard let token = TokenManager.shared.getAccessToken() else { return }

        let url = URL(string: "https://backendevent-etce.onrender.com/api/promoters/my-stats/event/\(event.id)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, response, _ in
            guard let data = data else {
                print("❌ No data received")
                return
            }

            // Print raw string for debugging
            if let raw = String(data: data, encoding: .utf8) {
                print("🧾 Raw response string:\n\(raw)")
            }

            do {
                struct PromoterStatsResponse: Decodable {
                    let referralCode: String
                    let ticketsSold: Int
                    let buyers: [ReferredBuyerDTO]
                }

                let stats = try JSONDecoder().decode(PromoterStatsResponse.self, from: data)

                DispatchQueue.main.async {
                    self.isPromoterForEvent = true
                    self.promoterStats = PromoterEvent(
                        id: 0,
                        ticketsSold: stats.ticketsSold,
                        event: event,
                        promoter: PromoterDTO(id: 0, referralCode: stats.referralCode, user: UserDTO(firstName: "", lastName: "", username: ""))
                    )
                    self.referredBuyers = stats.buyers
                }

            } catch {
                // Fallback in case response is not JSON
                let fallback = String(data: data, encoding: .utf8) ?? ""
                if fallback.contains("not a promoter") {
                    print("ℹ️ User is not a promoter — ignoring.")
                    DispatchQueue.main.async {
                        self.isPromoterForEvent = false
                    }
                } else {
                    print("❌ JSON decode failed: \(error)")
                }
            }
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
            shareURL = URL(string: "http://localhost:3000/events/\(event.id)")
            return
        }

        var request = URLRequest(url: URL(string: "https://backendevent-etce.onrender.com/api/promoters/me")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                if let data = data,
                   let promoter = try? JSONDecoder().decode(Promoter.self, from: data) {
                    let ref = promoter.user.username
                    self.shareURL = URL(string: "http://localhost:3000/events/\(event.id)?ref=\(ref)")
                } else {
                    self.shareURL = URL(string: "http://localhost:3000/events/\(event.id)")
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
