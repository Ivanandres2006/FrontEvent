import SwiftUI

struct ChatListView: View {
    @EnvironmentObject var userSession: UserSession
    @Environment(\.dismiss) var dismiss

    @State private var chatPosts: [ChatRoomSummary] = []
    @State private var isLoading = true
    @State private var selectedPost: ChatRoomSummary?

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                if isLoading {
                    ProgressView("Loading Chats...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else if chatPosts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.5))
                        Text("No active chats found")
                            .foregroundColor(.white.opacity(0.7))
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 20) {
                            ForEach(chatPosts) { post in
                                Button {
                                    selectedPost = post
                                } label: {
                                    HStack(spacing: 12) {
                                        ZStack(alignment: .topTrailing) {
                                            Image(systemName: "ticket.fill")
                                                .foregroundColor(.neonGreen)
                                                .font(.title2)

                                            if let unread = post.unreadMessages, unread > 0 {
                                                Text("\(unread)")
                                                    .font(.caption2.bold())
                                                    .foregroundColor(.white)
                                                    .padding(5)
                                                    .background(Color.red)
                                                    .clipShape(Circle())
                                                    .offset(x: 8, y: -8)
                                                    .transition(.scale)
                                                    .animation(.spring(), value: unread)
                                            }
                                        }

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(post.title)
                                                .font(.headline)
                                                .foregroundColor(.white)
                                            Text("With \(post.sellerName)")
                                                .font(.subheadline)
                                                .foregroundColor(.white.opacity(0.6))
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.white.opacity(0.3))
                                    }
                                    .padding()
                                    .background(Color.white.opacity(0.06))
                                    .cornerRadius(12)
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Chats")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: fetchChats)
            .sheet(item: $selectedPost) { post in
                ChatView(
                    chatSummary: post,
                    currentUserId: userSession.userId ?? 0
                )
            }
        }
    }

    func fetchChats() {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "http://localhost:8080/chat/my") else {
            self.isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                self.isLoading = false
            }
            

            if let data = data {
                do {
                    let decoded = try JSONDecoder().decode([ChatRoomSummary].self, from: data)
                    DispatchQueue.main.async {
                        
                        self.chatPosts = Array(Dictionary(grouping: decoded, by: \.resalePostId).values.map { $0.first! })
                    }
                } catch {
                    print("❌ Failed to decode chat posts: \(error)")
                    print(String(data: data, encoding: .utf8) ?? "No response body")
                }
            }
        }.resume()
    }
}
