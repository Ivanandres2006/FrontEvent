import SwiftUI

struct ChatListView: View {
    @AppStorage("selectedLanguage") var lang: String = "en"
    @EnvironmentObject var userSession: UserSession
    @Environment(\.dismiss) private var dismiss

    @State private var rooms: [ChatRoomSummaryDTO] = []
    @State private var loading = true
    @State private var error: String?
    @State private var selectedRoom: ChatRoomSummaryDTO?

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left").foregroundColor(.white)
                    }
                    Spacer()
                    Text(lang == "es" ? "Mensajes" : "Messages")
                        .font(.headline).foregroundColor(.white)
                    Spacer()
                    Button(action: { Task { await fetchRooms() } }) {
                        Image(systemName: "arrow.clockwise").foregroundColor(.white)
                    }
                }
                .padding()
                .background(Color.black.opacity(0.25))

                if loading {
                    ProgressView().tint(.gold).padding(.top, 12)
                } else if let error {
                    Text(error).foregroundColor(.red).padding()
                } else if rooms.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 36))
                            .foregroundColor(.white.opacity(0.65))
                        Text(lang == "es" ? "No hay chats aún" : "No chats yet")
                            .foregroundColor(.white.opacity(0.75))
                    }
                    .padding(.top, 28)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(rooms, id: \.id) { room in
                                Button {
                                    selectedRoom = room
                                } label: {
                                    HStack(spacing: 12) {
                                        avatar(room)
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack {
                                                Text(room.displayName)
                                                    .foregroundColor(.white)
                                                    .font(.headline)
                                                    .lineLimit(1)
                                                Spacer()
                                                if room.unreadCount > 0 {
                                                    Text("\(room.unreadCount)")
                                                        .font(.caption2.bold())
                                                        .foregroundColor(.black)
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(Color.gold)
                                                        .clipShape(Capsule())
                                                }
                                            }
                                            if let preview = room.lastMessagePreview, !preview.isEmpty {
                                                Text(preview)
                                                    .foregroundColor(.white.opacity(0.7))
                                                    .font(.caption)
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(12)
                                    .background(Color.white.opacity(0.05))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal)
                            }
                        }
                        .padding(.bottom, 12)
                    }
                }
            }
        }
        .refreshable { await fetchRooms() }
        .task { await fetchRooms() }
        .onChange(of: selectedRoom) { newValue in
            // When we dismiss the room, refresh the list (read markers, new threads, etc.)
            if newValue == nil { Task { await fetchRooms() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .chatListNeedsRefresh)) { _ in
            Task { await fetchRooms() }
        }
        .fullScreenCover(item: $selectedRoom) { room in
            NavigationStack {
                ChatRoomView(room: room, myUserId: Int(userSession.userId))
            }
        }
    }

    // MARK: - UI helpers
    private func avatar(_ room: ChatRoomSummaryDTO) -> some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.08)).frame(width: 44, height: 44)
            if let urlStr = room.iconUrl, let url = URL(string: urlStr) {
                AsyncImage(url: url) { ph in
                    switch ph {
                    case .success(let img): img.resizable().scaledToFill()
                    default: Text(initials(from: room.displayName)).foregroundColor(.white)
                } }
                .frame(width: 44, height: 44).clipShape(Circle())
            } else {
                Text(initials(from: room.displayName))
                    .font(.headline).foregroundColor(.white)
            }
        }
    }

    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? ""
        let second = parts.dropFirst().first?.first.map(String.init) ?? ""
        let both = (first + second)
        return both.isEmpty ? "•" : both.uppercased()
    }

    // MARK: - Data
    private func fetchRooms() async {
        await MainActor.run { loading = true; error = nil }

        // Provide JWT on demand
        ChatAPI.shared.setTokenProvider { TokenManager.shared.getAccessToken() }

        // Bridge completion-based refresh to async/await WITHOUT changing TokenManager
        ChatAPI.shared.setTokenRefresher {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                TokenManager.shared.refreshIfNeeded { _ in
                    cont.resume() // we don't care about the Bool here; ChatAPI will retry once
                }
            }
        }

        do {
            var list = try await ChatAPI.shared.myRooms()
            // newest activity first
            list.sort {
                switch ($0.lastMessageAt, $1.lastMessageAt) {
                case let (a?, b?): return a > b
                case (nil, _?):   return false
                case (_?, nil):   return true
                default:          return $0.id > $1.id
                }
            }
            await MainActor.run {
                self.rooms = list
                self.loading = false
            }
        } catch {
            await MainActor.run {
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.rooms = []
                self.loading = false
            }
        }
    }
}
