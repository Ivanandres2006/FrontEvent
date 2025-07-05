import SwiftUI

struct ChatView: View {
    let chatSummary: ChatRoomSummary
    let currentUserId: Int
    @State private var chatRoomId: Int? = nil

    @State private var messages: [ChatMessage] = []
    @State private var newMessage = ""
    @State private var isLoading = false
    
    @State private var showCustomActionSheet = false
    @State private var showImagePicker = false
    @State private var useCamera = false
    @State private var showCounterOfferPrompt = false

    var body: some View {
        VStack {
            // 🔘 Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(chatSummary.title)
                        .font(.title3.bold())
                        .foregroundColor(.white)
                    Text("Talking with \(chatSummary.sellerName)")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
                Spacer()
            }
            .padding()
            .background(Color.black.opacity(0.7))

            Divider()

            // 💬 Chat messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            HStack {
                                if message.senderId == currentUserId {
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(message.content)
                                            .padding()
                                            .background(Color.neonGreen.opacity(0.9))
                                            .cornerRadius(16)
                                            .foregroundColor(.black)
                                            .frame(maxWidth: 250, alignment: .trailing)

                                        Text(formattedTime(message.timestamp))
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                            .padding(.trailing, 6)
                                    }
                                } else {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(message.content)
                                            .padding()
                                            .background(Color.white.opacity(0.1))
                                            .cornerRadius(16)
                                            .foregroundColor(.white)
                                            .frame(maxWidth: 250, alignment: .leading)

                                        Text(formattedTime(message.timestamp))
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                            .padding(.leading, 6)
                                    }
                                    Spacer()
                                }
                            }
                            .padding(.horizontal)
                            .id(message.id)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                }
                .onChange(of: messages.count) { _ in
                    withAnimation {
                        proxy.scrollTo(messages.last?.id, anchor: .bottom)
                    }
                }
            }

            // ✏️ Input field
            HStack(spacing: 10) {
                Button {
                    showCustomActionSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                }

                TextField("Type a message...", text: $newMessage)
                    .padding(12)
                    .background(Color.white.opacity(0.1))
                    .foregroundColor(.white)
                    .cornerRadius(10)

                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.neonGreen)
                        .padding(10)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(10)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .background(
            LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .onAppear {
            self.chatRoomId = chatSummary.chatRoomId
              fetchMessages()

              Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
                fetchMessages()
              }
        }
        .fullScreenCover(isPresented: $showCustomActionSheet) {
            ZStack {
                Color.black.opacity(0.6).ignoresSafeArea()
                
                VStack(spacing: 24) {
                    Text("More Options")
                        .font(.title2.bold())
                        .foregroundColor(.white)

                    Button {
                        useCamera = true
                        showImagePicker = true
                        showCustomActionSheet = false
                    } label: {
                        Text("📷 Take Photo")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.white.opacity(0.08))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }

                    Button {
                        useCamera = false
                        showImagePicker = true
                        showCustomActionSheet = false
                    } label: {
                        Text("🖼️ Choose from Library")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.white.opacity(0.08))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }

                    Button {
                        showCounterOfferPrompt = true
                        showCustomActionSheet = false
                    } label: {
                        Text("💲 Send Counteroffer")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.neonGreen.opacity(0.9))
                            .foregroundColor(.black)
                            .cornerRadius(12)
                    }

                    Button {
                        showCustomActionSheet = false
                    } label: {
                        Text("Cancel")
                            .foregroundColor(.gray)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.deepNavy)
                        .shadow(color: Color.neonGreen.opacity(0.3), radius: 10, x: 0, y: 4)
                )
                .padding(.horizontal, 30)
            }
        }
        .alert("Send Counteroffer", isPresented: $showCounterOfferPrompt) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This will let you propose a new price.")
        }
    }

    // MARK: - API Actions

    func startChatIfNeeded() {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "http://localhost:8080/chat/start") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["resalePostId": chatSummary.resalePostId]
        request.httpBody = try? JSONEncoder().encode(body)

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data else { return }
            if let decoded = try? JSONDecoder().decode(ChatRoom.self, from: data) {
                DispatchQueue.main.async {
                    self.chatRoomId = decoded.id
                    fetchMessages()
                }
            }
        }.resume()
    }

    func fetchMessages() {
        guard let token = TokenManager.shared.getAccessToken(),
              let chatRoomId = chatRoomId,
              let url = URL(string: "http://localhost:8080/chat/\(chatRoomId)/messages") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data else { return }
            if let decoded = try? JSONDecoder().decode([ChatMessage].self, from: data) {
                DispatchQueue.main.async {
                    self.messages = decoded
                }
            }
        }.resume()
    }
    
    private func formattedTime(_ timestamp: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS" // Handles microseconds
        formatter.timeZone = TimeZone.current
        formatter.locale = Locale(identifier: "en_US_POSIX")

        if let date = formatter.date(from: timestamp) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "h:mm a"
            displayFormatter.locale = Locale.current

            let result = displayFormatter.string(from: date)
            print("📩 Message time raw: \(timestamp) | Parsed: \(result)")
            return result
        }

        print("⚠️ Failed to parse timestamp: \(timestamp)")
        return "..."
    }



    func sendMessage() {
        guard !newMessage.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard let token = TokenManager.shared.getAccessToken(),
              let chatRoomId = chatRoomId,
              let url = URL(string: "http://localhost:8080/chat/\(chatRoomId)/send") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct SendMessageRequest: Codable {
            let content: String
        }

        let payload = SendMessageRequest(content: newMessage)
        request.httpBody = try? JSONEncoder().encode(payload)

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let decoded = try? JSONDecoder().decode(ChatMessage.self, from: data) else {
                print("❌ Failed to send message or decode response")
                return
            }

            DispatchQueue.main.async {
                messages.append(decoded)
                newMessage = ""
            }
        }.resume()
    }
    
    

    // MARK: - Models

    struct ChatMessage: Identifiable, Codable {
        var id: Int
        var senderId: Int
        var content: String
        var timestamp: String
    }

    struct ChatRoom: Codable {
        var id: Int
    }
}
