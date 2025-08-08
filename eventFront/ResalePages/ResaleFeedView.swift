import SwiftUI
import UIKit

struct ResaleFeedView: View {
    @AppStorage("selectedLanguage") var lang: String = "en"
    @EnvironmentObject var userSession: UserSession

    @State private var posts: [ResalePostDTO] = []
    @State private var myTickets: [TicketDTO] = []
    @State private var allEvents: [Event] = []

    @State private var isLoading = true
    @State private var showPostCreation = false
    @State private var showMyChats = false

    @StateObject private var postVM = PostCreationViewModel()

    @State private var selectedChatSummary: ChatRoomSummary? = nil
    @State private var selectedBuyNowPost: ResalePostDTO? = nil

    @State private var unreadCount: Int = 0
    
    @State private var showToast = false
    @State private var toastText = ""


    var body: some View {
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                if isLoading {
                    VStack {
                        Spacer()
                        ProgressView(lang == "es" ? "Cargando Publicaciones de Reventa..." : "Loading Resale Posts...")
                            .foregroundColor(.white)
                            .progressViewStyle(CircularProgressViewStyle(tint: .gold))
                        Spacer()
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: isLoading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if posts.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "ticket")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 60, height: 60)
                            .foregroundColor(.white.opacity(0.5))

                        Text(lang == "es" ? "No se encontraron entradas en reventa" : "No resale tickets found")
                            .foregroundColor(.white.opacity(0.8))
                            .font(.title3)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .multilineTextAlignment(.center)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 24) {
                            ForEach(posts) { post in
                                ResalePostCard(post: post, onMessage: {
                                    openChat(for: post)
                                }, onBuyNow: {
                                    selectedBuyNowPost = post
                                })
                            }
                        }
                        .padding()
                    }
                }

                HStack(spacing: 14) {
                    Button {
                        showMyChats = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.title2)
                                .padding(10)
                                .background(Color.white.opacity(0.15))
                                .clipShape(Circle())
                                .foregroundColor(.white)

                            if unreadCount > 0 {
                                Text("\(unreadCount)")
                                    .font(.caption2.bold())
                                    .foregroundColor(.white)
                                    .padding(6)
                                    .background(Color.red)
                                    .clipShape(Circle())
                                    .offset(x: 8, y: -8)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                    }

                    Button {
                        if !myTickets.isEmpty {
                            postVM.tickets = myTickets
                            showPostCreation = true
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title)
                            .foregroundColor(.gold)
                            .background(Circle().fill(Color.black.opacity(0.5)).frame(width: 44, height: 44))
                    }
                }
                .padding(.top, 16)
                .padding(.trailing, 20)
                
                // 🔻 Bottom toast overlay
                if showToast {
                    VStack {
                        Spacer()
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.white)
                            Text(toastText)
                                .foregroundColor(.white)
                                .font(.footnote.weight(.semibold))
                                .lineLimit(2)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.red.opacity(0.95))
                                .shadow(radius: 12, y: 6)
                        )
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .padding(.bottom, 18) // sits just above home bar
                }
            }
            .navigationTitle("Ticket Resale")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                fetchMyTickets()
                fetchAllEvents {
                    fetchResalePosts()
                }
                fetchUnreadCount()
                startUnreadTimer()
            }
            .sheet(isPresented: $showPostCreation) {
                PostCreationView(viewModel: postVM) {
                    fetchResalePosts()
                }
                .environmentObject(userSession)
            }
            .fullScreenCover(isPresented: $showMyChats) {
                ChatListView()
            }
            .fullScreenCover(item: $selectedChatSummary) { (summary: ChatRoomSummary) in
                ChatView(chatSummary: summary, currentUserId: userSession.userId)
                    .environmentObject(userSession)
            }
            .sheet(item: $selectedBuyNowPost) { post in
                // Pass a minimal Event just with id and title to trigger loading spinner
                BuyNowView(
                    resalePost: post,
                    event: .constant(Event(id: post.eventId ?? -1, title: post.eventTitle)),
                    userEmail: userSession.email,
                    onComplete: { fetchResalePosts() }
                )
            }
        }
    }

    // MARK: - Helpers

    func findEvent(for post: ResalePostDTO) -> Event? {
        allEvents.first { $0.id == post.eventId }
    }

    func filterValidResalePosts(_ posts: [ResalePostDTO]) -> [ResalePostDTO] {
        posts.filter { post in
            print("🔎 Filtering \(posts.count) posts")
            if let event = allEvents.first(where: { Int($0.id) == post.eventId }) {
                print("🔹 Post: \(post.title), eventId: \(post.eventId)")
                return (event.dateAsDate ?? .distantPast) > Date()
            }
            return false
        }
    }

    func fetchResalePosts() {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/resale/available") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse {
                print("HTTP STATUS:", http.statusCode)
            }
            guard let data = data else {
                print("No data received from /resale/available")
                DispatchQueue.main.async { self.isLoading = false }
                return
            }
            print("RAW RESALE JSON:", String(data: data, encoding: .utf8) ?? "nil")
            do {
                let decoded = try JSONDecoder().decode([ResalePostDTO].self, from: data)
                DispatchQueue.main.async {
                    print("🪪 Decoded \(decoded.count) resale posts")
                    self.posts = filterValidResalePosts(decoded)
                    self.isLoading = false
                }
            } catch {
                print("❌ Failed to decode resale posts:", error)
                DispatchQueue.main.async { self.isLoading = false }
            }
        }.resume()
    }

    func fetchAllEvents(completion: @escaping () -> Void) {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/events") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data = data {
                if let decoded = try? JSONDecoder().decode(PaginatedResponse<Event>.self, from: data) {
                    DispatchQueue.main.async {
                        self.allEvents = decoded.content
                        completion()
                    }
                } else {
                    print("❌ Failed to decode events")
                    completion()
                }
            }
        }.resume()
    }

    func fetchMyTickets() {
        guard let token = TokenManager.shared.getAccessToken(),
              let email = userSession.email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://backendevent-etce.onrender.com/api/tickets/my?email=\(email)") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data = data,
               let decoded = try? JSONDecoder().decode([TicketDTO].self, from: data) {
                DispatchQueue.main.async {
                    self.myTickets = decoded
                }
            }
        }.resume()
    }

    func fetchUnreadCount() {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/chat/unread-count") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data = data,
               let decoded = try? JSONDecoder().decode([String: Int].self, from: data),
               let count = decoded["unread"] {
                DispatchQueue.main.async {
                    withAnimation {
                        self.unreadCount = count
                    }
                }
            }
        }.resume()
    }

    func openChat(for post: ResalePostDTO) {
        if post.sellerId == userSession.userId {
            showErrorToast(lang == "es" ? "No puedes chatear contigo mismo." : "You can’t chat with yourself.")
            return
        }

        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/chat/start") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["resalePostId": post.id]
        request.httpBody = try? JSONEncoder().encode(body)

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data else {
                DispatchQueue.main.async {
                    showErrorToast(lang == "es" ? "Sin respuesta del servidor." : "No response from server.")
                }
                return
            }

            // Try to decode error from backend
            if let errorDict = try? JSONDecoder().decode([String: String].self, from: data),
               let errorMsg = errorDict["error"] {
                DispatchQueue.main.async {
                    showErrorToast(errorMsg)
                }
                return
            }

            // Decode successful chat creation
            if let decoded = try? JSONDecoder().decode(ChatRoom.self, from: data) {
                DispatchQueue.main.async {
                    self.selectedChatSummary = ChatRoomSummary(
                        chatRoomId: decoded.id,
                        resalePostId: post.id,
                        title: post.title,
                        sellerName: post.sellerName,
                        unreadMessages: 0,
                        buyerId: userSession.userId,
                        eventId: Int64(post.eventId ?? -1),
                        type: "DIRECT"
                    )
                }
            } else {
                DispatchQueue.main.async {
                    showErrorToast(lang == "es" ? "No se pudo abrir el chat." : "Couldn't open chat.")
                }
            }
        }.resume()
    }
    
    
    
    private func showErrorToast(_ text: String) {
        toastText = text
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)   // 🔔 vibration
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { showToast = false }
        }
    }


    func startUnreadTimer() {
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            fetchUnreadCount()
        }
    }

    struct ChatRoom: Codable {
        var id: Int
    }
}
