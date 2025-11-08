import SwiftUI

// MARK: - PeopleListView (direct endpoint + tolerant mapping into your UserSummary)
struct PeopleListView: View {
    enum Mode { case followers, following, friends }

    let mode: Mode
    let userId: Int
    @AppStorage("selectedLanguage") private var lang: String = "en"

    // Data
    @State private var people: [UserSummary] = []
    @State private var filtered: [UserSummary] = []

    // UI
    @State private var searchText = ""
    @State private var loading = false
    @State private var error: String?

    private var title: String {
        switch mode {
        case .followers: return lang == "es" ? "Seguidores" : "Followers"
        case .following: return lang == "es" ? "Siguiendo"  : "Following"
        case .friends:   return lang == "es" ? "Amigos"     : "Friends"
        }
    }
    private var subtitle: String {
        switch mode {
        case .followers: return lang == "es" ? "Seguidor" : "Follower"
        case .following: return lang == "es" ? "Siguiendo" : "Following"
        case .friends:   return lang == "es" ? "Amigo" : "Friend"
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Search (WKND style)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(.white.opacity(0.7))
                TextField(lang == "es" ? "Buscar personas…" : "Search people…", text: $searchText)
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

            if loading { ProgressView().tint(.gold).padding(.top, 6) }

            // Error pill
            if let error {
                HStack(spacing: 10) {
                    Text(error)
                        .foregroundColor(.white)
                        .font(.footnote.weight(.semibold))
                    Button(lang == "es" ? "Reintentar" : "Retry") { Task { await load() } }
                        .font(.footnote.bold())
                        .foregroundColor(.black)
                        .padding(.vertical, 6).padding(.horizontal, 10)
                        .background(Color.gold).clipShape(Capsule())
                }
                .padding(.vertical, 10).padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gold, lineWidth: 2)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
                )
                .padding(.horizontal)
            }

            List {
                if !loading && error == nil && filtered.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 34))
                            .foregroundColor(.gold)
                        Text(lang == "es" ? "Aún no hay \(title.lowercased())." : "No \(title.lowercased()) yet.")
                            .foregroundColor(.white.opacity(0.85))
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                ForEach(filtered) { u in
                    NavigationLink {
                        PublicProfileView(userId: u.id, usernameOrId: u.username)
                    } label: {
                        HStack(spacing: 12) {
                            PeopleAvatar(url: u.avatarUrl, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("@\(u.username)")
                                    .foregroundColor(.white)
                                    .font(.subheadline.bold())
                                Text(subtitle)
                                    .foregroundColor(.white.opacity(0.6))
                                    .font(.caption)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await load() }
        }
        .background(
            LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            applyFilter()
            Task { await load() }
        }
        .onChange(of: searchText) { _ in applyFilter() }
    }

    // MARK: - Filter
    private func applyFilter() {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { filtered = people; return }
        filtered = people.filter {
            $0.username.lowercased().contains(q) || ($0.displayName ?? "").lowercased().contains(q)
        }
    }

    // MARK: - Load (direct endpoints + tolerant decode -> your UserSummary)
    private func load() async {
        guard userId > 0 else { return }
        await MainActor.run { loading = true; error = nil }

        let base = "https://backendevent-etce.onrender.com"
        let path: String = {
            switch mode {
            case .followers: return "/api/social/followers/\(userId)"
            case .following: return "/api/social/following/\(userId)"
            case .friends:   return "/api/social/friends/\(userId)"
            }
        }()

        guard let url = URL(string: base + path) else {
            await MainActor.run { loading = false; error = "Bad URL" }
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let t = TokenManager.shared.getAccessToken() {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }

            switch http.statusCode {
            case 200...299:
                let list = Self.decodeToUserSummaryList(from: data)
                await MainActor.run {
                    people = list
                    applyFilter()
                    loading = false
                }

            case 401:
                await MainActor.run {
                    loading = false
                    error = lang == "es" ? "Sesión expirada. Inicia sesión." : "Session expired. Please sign in."
                }
            case 403:
                await MainActor.run {
                    loading = false
                    error = lang == "es" ? "No tienes permiso para ver esto." : "You don’t have permission to view this."
                }
            default:
                await MainActor.run {
                    loading = false
                    error = (lang == "es")
                        ? "No se pudo cargar \(title.lowercased())."
                        : "Failed to load \(title.lowercased())."
                }
            }
        } catch {
            await MainActor.run {
                loading = false
                self.error = (lang == "es")
                    ? "No se pudo cargar \(title.lowercased())."
                    : "Failed to load \(title.lowercased())."
            }
        }
    }

    // MARK: - Decoding shim → maps any reasonable JSON into YOUR UserSummary
    private static func decodeToUserSummaryList(from data: Data) -> [UserSummary] {
        if data.isEmpty { return [] }

        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase

        // 1) Try decoding directly as your UserSummary array
        if let arr = try? dec.decode([UserSummary].self, from: data) { return arr }

        // 2) Try common wrappers
        struct Wrap<T: Decodable>: Decodable {
            let followers: [T]?
            let following: [T]?
            let friends:   [T]?
            let content:   [T]?
            let data:      [T]?
            let items:     [T]?
        }
        if let w = try? dec.decode(Wrap<UserSummary>.self, from: data) {
            return w.followers ?? w.following ?? w.friends ?? w.content ?? w.data ?? w.items ?? []
        }

        // 3) Decode a "loose" version and map → your UserSummary (defaults for counts)
        if let loose = try? dec.decode([LooseUser].self, from: data) {
            return loose.map { $0.toUserSummary() }
        }
        if let w = try? dec.decode(Wrap<LooseUser>.self, from: data) {
            let arr = w.followers ?? w.following ?? w.friends ?? w.content ?? w.data ?? w.items ?? []
            return arr.map { $0.toUserSummary() }
        }

        // 4) Last resort: JSONSerialization
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return [] }
        if let arr = obj as? [[String: Any]] {
            return arr.compactMap(LooseUser.fromDict).map { $0.toUserSummary() } ?? []
        }
        if let dict = obj as? [String: Any] {
            for key in ["followers", "following", "friends", "content", "data", "items"] {
                if let arr = dict[key] as? [[String: Any]] {
                    return (arr.compactMap(LooseUser.fromDict) ?? []).map { $0.toUserSummary() }
                }
            }
        }
        return []
    }

    // A tolerant decoder that doesn't require followers/following keys.
    private struct LooseUser: Decodable {
        let id: Int?
        let username: String?
        let handle: String?
        let userName: String?
        let displayName: String?
        let name: String?
        let firstName: String?
        let lastName: String?
        let avatarUrl: String?
        let imageUrl: String?
        let avatar: String?
        let photo: String?
        let picture: String?
        let followers: Int?
        let following: Int?

        func toUserSummary() -> UserSummary {
            let uid = id ?? 0
            let uname = username ?? handle ?? userName ?? "user\(uid)"
            let dn = displayName ?? name ?? {
                let first = firstName ?? ""
                let last  = lastName ?? ""
                let full = [first, last].filter{ !$0.isEmpty }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                return full.isEmpty ? nil : full
            }()
            let avatar = avatarUrl ?? imageUrl ?? avatar ?? photo ?? picture
            return UserSummary(
                id: uid,
                username: uname,
                displayName: dn,
                avatarUrl: avatar,
                followers: followers ?? 0,
                following: following ?? 0
            )
        }

        static func fromDict(_ d: [String: Any]) -> LooseUser? {
            func intVal(_ v: Any?) -> Int? {
                if let i = v as? Int { return i }
                if let s = v as? String, let i = Int(s) { return i }
                if let d = v as? Double { return Int(d) }
                return nil
            }
            return LooseUser(
                id: intVal(d["id"]),
                username: d["username"] as? String,
                handle: d["handle"] as? String,
                userName: d["userName"] as? String,
                displayName: d["displayName"] as? String,
                name: d["name"] as? String,
                firstName: d["firstName"] as? String,
                lastName: d["lastName"] as? String,
                avatarUrl: d["avatarUrl"] as? String,
                imageUrl: d["imageUrl"] as? String,
                avatar: d["avatar"] as? String,
                photo: d["photo"] as? String,
                picture: d["picture"] as? String,
                followers: intVal(d["followers"]),
                following: intVal(d["following"])
            )
        }
    }
}

// MARK: - Avatar (WKND style)
private struct PeopleAvatar: View {
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
                    case .empty:   ProgressView().tint(.gold)
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

// Resolve whatever the backend sends (relative paths, //cdn, http, etc.) to a safe absolute URL
public func resolveAvatarURL(_ raw: String?) -> URL? {
    guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }

    // Prefer HTTPS
    if s.hasPrefix("http://") { s = "https://" + s.dropFirst("http://".count) }

    if s.hasPrefix("https://") { return URL(string: s) }
    if s.hasPrefix("//")      { return URL(string: "https:\(s)") }
    if s.hasPrefix("/")       { return URL(string: "https://backendevent-etce.onrender.com\(s)") }
    if s.contains(".") && !s.contains("://") { return URL(string: "https://\(s)") } // bare host

    return URL(string: s) // data: or anything else
}

// Use this Avatar everywhere (Notifications, People lists, Profile headers, etc.)
public struct Avatar: View {
    public let url: String?
    public let size: CGFloat

    public init(url: String?, size: CGFloat) {
        self.url = url
        self.size = size
    }

    public var body: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.08)).frame(width: size, height: size)
            if let u = resolveAvatarURL(url) {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                    case .empty:
                        ProgressView().tint(.white).frame(width: size, height: size)
                    case .failure:
                        Image(systemName: "person.fill")
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: size, height: size)
                    @unknown default:
                        EmptyView().frame(width: size, height: size)
                    }
                }
            } else {
                Image(systemName: "person.fill")
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: size, height: size)
            }
        }
        .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
        .frame(width: size, height: size)
    }
}
