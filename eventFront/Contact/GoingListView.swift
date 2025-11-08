import SwiftUI

struct GoingListView: View {
    let eventId: Int
    let lang: String
    let initial: [Attendee]

    @State private var attendees: [Attendee] = []
    @State private var filtered: [Attendee] = []
    @State private var searchText: String = ""
    @State private var loading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                // Search bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundColor(.white.opacity(0.7))
                    TextField(lang == "es" ? "Buscar asistentes…" : "Search people…", text: $searchText)
                        .textInputAutocapitalization(.none)
                        .disableAutocorrection(true)
                        .foregroundColor(.white)
                    if !searchText.isEmpty {
                        Button(lang == "es" ? "Limpiar" : "Clear") { searchText = "" }
                            .font(.caption.bold())
                            .foregroundColor(.black)
                            .padding(.vertical, 6).padding(.horizontal, 10)
                            .background(Color.gold).clipShape(Capsule())
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)

                if loading {
                    ProgressView().tint(.gold).padding(.top, 6)
                }

                List {
                    ForEach(filtered) { u in
                        NavigationLink {
                            // 👉 Push to the public profile
                            PublicProfileView(userId: u.id, usernameOrId: u.username)
                        } label: {
                            HStack(spacing: 12) {
                                SmallAvatar(url: u.avatarUrl, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("@\(u.username ?? "user\(u.id)")")
                                        .foregroundColor(.white)
                                        .font(.subheadline.bold())
                                    Text(lang == "es" ? "Asistente" : "Attendee")
                                        .foregroundColor(.white.opacity(0.6))
                                        .font(.caption)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle()) // full-row hit target
                        }
                        .buttonStyle(.plain) // remove default link styling
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .background(
                LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            )
            .navigationTitle(lang == "es" ? "Asistentes" : "Going")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            attendees = initial
            applyFilter()
            Task { await refetch() } // refresh from network
        }
        .onChange(of: searchText) { _ in applyFilter() }
    }

    private func applyFilter() {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { filtered = attendees; return }
        filtered = attendees.filter { ($0.username ?? "").lowercased().contains(q) }
    }

    private func refetch() async {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/api/attendance/events/\(eventId)/going")
        else { return }

        await MainActor.run { loading = true }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
               let decoded = try? JSONDecoder().decode([Attendee].self, from: data) {
                await MainActor.run {
                    attendees = decoded
                    applyFilter()
                    loading = false
                }
            } else {
                await MainActor.run { loading = false }
            }
        } catch {
            await MainActor.run { loading = false }
        }
    }
}

// Unchanged
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
