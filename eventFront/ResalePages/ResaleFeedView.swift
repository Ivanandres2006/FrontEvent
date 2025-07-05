import SwiftUI

struct ResaleFeedView: View {
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

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                if isLoading {
                    ProgressView("Loading Resale Posts...")
                        .foregroundColor(.white)
                } else if posts.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "ticket")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 60, height: 60)
                            .foregroundColor(.white.opacity(0.5))

                        Text("No resale tickets found")
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
                            .foregroundColor(.neonGreen)
                            .background(Circle().fill(Color.black.opacity(0.5)).frame(width: 44, height: 44))
                    }
                }
                .padding(.top, 16)
                .padding(.trailing, 20)
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
            .sheet(isPresented: $showMyChats) {
                ChatListView()
            }
            .sheet(item: $selectedChatSummary) { (summary: ChatRoomSummary) in
                ChatView(chatSummary: summary, currentUserId: userSession.userId)
            }
            .sheet(item: $selectedBuyNowPost) { post in
                if let event = findEvent(for: post) {
                    BuyNowView(
                        resalePost: post,
                        event: .constant(event),
                        userEmail: userSession.email,
                        onComplete: { fetchResalePosts() }
                    )
                } else {
                    Text("Event not found")
                }
            }
        }
    }

    // MARK: - Helpers

    func findEvent(for post: ResalePostDTO) -> Event? {
        allEvents.first { $0.id == post.eventId }
    }

    func filterValidResalePosts(_ posts: [ResalePostDTO]) -> [ResalePostDTO] {
        posts.filter { post in
            if let event = allEvents.first(where: { $0.id == post.eventId }) {
                return (event.dateAsDate ?? .distantPast) > Date()
            }
            return false
        }
    }

    func fetchResalePosts() {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "http://localhost:8080/resale/available") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data else { return }
            if let decoded = try? JSONDecoder().decode([ResalePostDTO].self, from: data) {
                DispatchQueue.main.async {
                    self.posts = filterValidResalePosts(decoded)
                    self.isLoading = false
                }
            } else {
                print("❌ Failed to decode resale posts")
            }
        }.resume()
    }

    func fetchAllEvents(completion: @escaping () -> Void) {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "http://localhost:8080/events") else { return }

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
              let url = URL(string: "http://localhost:8080/api/tickets/my?email=\(email)") else { return }

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
              let url = URL(string: "http://localhost:8080/chat/unread-count") else { return }

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
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "http://localhost:8080/chat/start") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["resalePostId": post.id]
        request.httpBody = try? JSONEncoder().encode(body)

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data else {
                print("❌ No data from /chat/start")
                return
            }

            // ✅ Decode chatRoomId from backend response
            if let decoded = try? JSONDecoder().decode(ChatRoom.self, from: data) {
                DispatchQueue.main.async {
                    self.selectedChatSummary = ChatRoomSummary(
                        chatRoomId: decoded.id,                  // ✅ pass chatRoomId
                        resalePostId: post.id,
                        title: post.title,
                        sellerName: post.sellerName,
                        unreadMessages: 0
                    )
                }
            } else {
                print("❌ Failed to decode ChatRoom")
            }
        }.resume()
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
