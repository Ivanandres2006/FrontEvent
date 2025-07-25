import SwiftUI

struct DirectChatListView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var userSession: UserSession
    @AppStorage("selectedLanguage") var lang: String = "en"

    @State private var chatSummaries: [ChatRoomSummary] = []
    @State private var isLoading = true
    @State private var selectedChat: ChatRoomSummary? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [.black, .deepNavy], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    header

                    if isLoading {
                        Spacer()
                        ProgressView(lang == "es" ? "Cargando Chats...": "Loading chats...")
                            .tint(.gold)
                        Spacer()
                    } else if chatSummaries.isEmpty {
                        Spacer()
                        Text(lang == "es" ? "Aun no tienes mensajes": "No messages yet.")
                            .foregroundColor(.gray)
                        Spacer()
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                if !directChats.isEmpty {
                                    Text(lang == "es" ? "💬 Mensajes Directos": "💬 Direct Messages")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .padding(.horizontal)

                                    ForEach(directChats) { summary in
                                        chatCard(summary, icon: "person.crop.circle.fill", color: .gold)
                                    }
                                }

                                if !promoterChats.isEmpty {
                                    Text(lang == "es" ? "👥 Grupo de Promotores Chats": "👥 Promoter Group Chats")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .padding(.horizontal)

                                    ForEach(promoterChats) { summary in
                                        chatCard(summary, icon: "person.3.fill", color: .blue)
                                    }
                                }
                            }
                            .padding(.top, 10)
                        }
                    }
                }
            }
            .fullScreenCover(item: $selectedChat) { summary in
                ChatView(chatSummary: summary, currentUserId: userSession.userId)
            }
            .onAppear {
                print("🧪 Promoted Event IDs:", userSession.promotedEvents)
                ensurePromoterChatsExist(for: userSession.promotedEvents)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    fetchChats()
                }
            }
        }
    }

    var directChats: [ChatRoomSummary] {
        chatSummaries.filter { $0.type == "DIRECT" }
    }

    var promoterChats: [ChatRoomSummary] {
        chatSummaries.filter { $0.type == "PROMOTER_GROUP" }
    }

    @ViewBuilder
    func chatCard(_ summary: ChatRoomSummary, icon: String, color: Color) -> some View {
        Button {
            selectedChat = summary
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .resizable()
                    .frame(width: 36, height: 36)
                    .foregroundColor(color)

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.title)
                        .font(.headline)
                        .foregroundColor(.white)

                    if let unread = summary.unreadMessages, unread > 0 {
                        Text(lang == "es" ? "\(unread) sin leer" : "\(unread) unread")
                            .font(.caption)
                            .foregroundColor(.neonGreen)
                    }
                }

                Spacer()
            }
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }

    var header: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .foregroundColor(.white)
                    .font(.title3.weight(.medium))
                    .padding(10)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }

            Text(lang == "es" ? "Mensajes" : "Messages")
                .font(.title.bold())
                .foregroundColor(.white)
                .padding(.leading, 4)

            Spacer()
        }
        .padding(.top, 60)
        .padding(.horizontal)
        .padding(.bottom, 12)
        .background(Color.black.opacity(0.5))
    }
    
    func ensurePromoterChatsExist(for eventIds: [Int]) {
        guard let token = TokenManager.shared.getAccessToken() else { return }

        for eventId in eventIds {
            guard let url = URL(string: "https://backendevent-etce.onrender.com/chat/promoter-group/\(eventId)") else { continue }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            URLSession.shared.dataTask(with: request) { _, response, _ in
                if let httpRes = response as? HTTPURLResponse {
                    print("🔄 Promoter group for event \(eventId): \(httpRes.statusCode)")
                }
            }.resume()
        }
    }


    func fetchChats() {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/chat/my") else {
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data else { return }

            if let raw = String(data: data, encoding: .utf8) {
                print("📦 Raw response: \(raw)")
            }

            do {
                let decoded = try JSONDecoder().decode([ChatRoomSummary].self, from: data)
                DispatchQueue.main.async {
                    self.chatSummaries = decoded // Let your UI do the filtering
                    self.isLoading = false
                }
            } catch {
                print("❌ Failed to decode direct/promoter chats: \(error.localizedDescription)")
            }
        }.resume()
    }
}
