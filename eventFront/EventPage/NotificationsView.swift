import SwiftUI
import Foundation

struct ActivityItem: Codable, Identifiable, Hashable {
    let id: String
    let type: String        // e.g. FOLLOWED_YOU, ACCEPTED_REQUEST, LIKE, COMMENT
    let actorId: Int
    let username: String
    let displayName: String?
    let avatarUrl: String?
    let createdAt: String?  // ISO8601
    let entityId: Int?
    let entityThumb: String?

    enum CodingKeys: String, CodingKey {
      case id, type, actorId, userId, username, handle, displayName, name, avatarUrl, avatar, createdAt, ts
      case entityId, targetId, photoId, eventId
      case entityThumb, thumbUrl, coverUrl, imageUrl
    }

    // Custom decoder — accepts multiple possible JSON field names
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func str(_ keys: CodingKeys...) -> String? {
            for k in keys {
                if let v = try? c.decode(String.self, forKey: k) { return v }
            }
            return nil
        }
        func int(_ keys: CodingKeys...) -> Int? {
            for k in keys {
                if let v = try? c.decode(Int.self, forKey: k) { return v }
            }
            return nil
        }

        id          = str(.id) ?? UUID().uuidString
        type        = str(.type) ?? "ACTIVITY"
        actorId     = int(.actorId, .userId) ?? -1
        username    = str(.username, .handle) ?? "user"
        displayName = str(.displayName, .name)
        avatarUrl   = str(.avatarUrl, .avatar)
        createdAt   = str(.createdAt, .ts)
        entityId    = int(.entityId, .targetId, .photoId, .eventId)
        entityThumb = str(.entityThumb, .thumbUrl, .coverUrl, .imageUrl)
    }

    // add this right under your init(from:)
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(type, forKey: .type)
        try c.encode(actorId, forKey: .actorId)
        try c.encode(username, forKey: .username)
        try c.encodeIfPresent(displayName, forKey: .displayName)
        try c.encodeIfPresent(avatarUrl, forKey: .avatarUrl)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(entityId, forKey: .entityId)
        try c.encodeIfPresent(entityThumb, forKey: .entityThumb)
    }
}

extension ActivityItem {
    init(id: String = UUID().uuidString,
         type: String,
         actorId: Int,
         username: String,
         displayName: String? = nil,
         avatarUrl: String? = nil,
         createdAt: String? = ISO8601DateFormatter().string(from: Date()),
         entityId: Int? = nil,
         entityThumb: String? = nil) {
        self.id = id
        self.type = type
        self.actorId = actorId
        self.username = username
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.createdAt = createdAt
        self.entityId = entityId
        self.entityThumb = entityThumb
    }
}


private enum NotificationsAPI {
    private static let base = URL(string: "https://backendevent-etce.onrender.com")!
    private static func bearer() -> String? { TokenManager.shared.getAccessToken() }

    static func fetchActivity(limit: Int = 50) async throws -> [ActivityItem] {
        for path in ["/api/notifications", "/api/social/activity"] {
            var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
            comps.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
            var req = URLRequest(url: comps.url!)
            if let t = bearer() { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { continue }
                let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
                return try dec.decode([ActivityItem].self, from: data)
            } catch { continue }
        }
        return []
    }
}

// MARK: - Sticky accepted requests (persist locally so they stay after Accept)
private struct AcceptedStickyStore {
    static func key(meId: Int) -> String { "accepted_requests:v1:\(meId)" }

    static func load(meId: Int) -> [FollowRequest] {
        guard let data = UserDefaults.standard.data(forKey: key(meId: meId)) else { return [] }
        return (try? JSONDecoder().decode([FollowRequest].self, from: data)) ?? []
    }

    static func upsert(_ req: FollowRequest, meId: Int) {
        var cur = load(meId: meId)
        if !cur.contains(where: { $0.followerId == req.followerId }) { cur.insert(req, at: 0) }
        save(cur, meId: meId)
    }

    static func remove(followerId: Int, meId: Int) {
        var cur = load(meId: meId)
        cur.removeAll { $0.followerId == followerId }
        save(cur, meId: meId)
    }

    private static func save(_ arr: [FollowRequest], meId: Int) {
        if let data = try? JSONEncoder().encode(Array(arr.prefix(200))) {
            UserDefaults.standard.set(data, forKey: key(meId: meId))
        }
    }
}

// Persist acceptance timestamps (so "Accepted • 2m" survives reloads)
private struct AcceptedMetaStore {
    static func key(meId: Int) -> String { "accepted_meta:v1:\(meId)" }

    static func load(meId: Int) -> [Int: String] {
        guard let data = UserDefaults.standard.data(forKey: key(meId: meId)) else { return [:] }
        return (try? JSONDecoder().decode([Int: String].self, from: data)) ?? [:]
    }

    static func save(_ map: [Int: String], meId: Int) {
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: key(meId: meId))
        }
    }
}

// ✅ Persist “followed back” so the UI stays in “Following” across reloads
private struct FollowedBackStickyStore {
    static func key(meId: Int) -> String { "followed_back:v1:\(meId)" }

    static func load(meId: Int) -> Set<Int> {
        guard let data = UserDefaults.standard.array(forKey: key(meId: meId)) as? [Int] else { return [] }
        return Set(data)
    }
    static func save(_ set: Set<Int>, meId: Int) {
        UserDefaults.standard.set(Array(set), forKey: key(meId: meId))
    }
    static func insert(_ userId: Int, meId: Int) {
        var cur = load(meId: meId); cur.insert(userId); save(cur, meId: meId)
    }
    static func remove(_ userId: Int, meId: Int) {
        var cur = load(meId: meId); cur.remove(userId); save(cur, meId: meId)
    }
}

// MARK: - Local bridge to notify the *sender* ("accepted your request") without backend
private struct AcceptedEchoBridge {
    struct Echo: Codable, Hashable {
        let targetUserId: Int   // the user who should receive the activity (the sender)
        let actorId: Int        // the user who accepted (the one tapping Accept)
        let actorUsername: String
        let actorDisplayName: String?
        let createdAt: String   // ISO8601 string
    }
    private static let key = "accepted_echo_bridge:v1"

    private static func loadAll() -> [Echo] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Echo].self, from: data)) ?? []
    }
    private static func saveAll(_ arr: [Echo]) {
        if let data = try? JSONEncoder().encode(arr) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func enqueue(targetUserId: Int, actorId: Int, actorUsername: String, actorDisplayName: String?) {
        var all = loadAll()
        let echo = Echo(targetUserId: targetUserId,
                        actorId: actorId,
                        actorUsername: actorUsername,
                        actorDisplayName: actorDisplayName,
                        createdAt: ISO8601DateFormatter().string(from: Date()))
        all.insert(echo, at: 0)
        saveAll(Array(all.prefix(200)))
    }

    /// Pull and remove any echoes addressed to the current user.
    static func consume(for currentUserId: Int) -> [Echo] {
        var all = loadAll()
        let mine = all.filter { $0.targetUserId == currentUserId }
        if !mine.isEmpty {
            all.removeAll { $0.targetUserId == currentUserId }
            saveAll(all)
        }
        return mine
    }
}

// MARK: - Avatar resolver (we don't change FollowRequest; fetch avatar by id)
private enum AvatarResolver {
    private static let base = URL(string: "https://backendevent-etce.onrender.com")!
    private static func bearer() -> String? { TokenManager.shared.getAccessToken() }

    static func fetchAvatarURL(userId: Int) async -> String? {
        let paths = [
            "/api/users/\(userId)",
            "/api/user/\(userId)",
            "/api/profile/\(userId)"
        ]
        for p in paths {
            var req = URLRequest(url: base.appendingPathComponent(p))
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            if let t = bearer() { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { continue }
                if let url = extractAvatar(from: data) { return url }
            } catch { continue }
        }
        return nil
    }

    private static func extractAvatar(from data: Data) -> String? {
        let keys = ["avatarUrl","imageUrl","avatar","photo","picture"]
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for k in keys where (obj[k] as? String)?.isEmpty == false { return obj[k] as? String }
            for child in ["user","data","profile"] {
                if let inner = obj[child] as? [String: Any] {
                    for k in keys where (inner[k] as? String)?.isEmpty == false { return inner[k] as? String }
                }
            }
        }
        return nil
    }
}

// MARK: - View
struct NotificationsView: View {
    enum Tab: String, CaseIterable, Identifiable { case requests, activity; var id: String { rawValue } }

    @EnvironmentObject var userSession: UserSession
    @AppStorage("selectedLanguage") private var lang: String = "en"

    @State private var tab: Tab = .requests
    @State private var loading = false
    @State private var error: String?

    // Requests
    @State private var requests: [FollowRequest] = []
    @State private var accepted: Set<Int> = []      // followerId
    @State private var acceptedAt: [Int: Date] = [:]
    @State private var followedBack: Set<Int> = []  // followerId
    @State private var busyIds: Set<Int> = []

    // Activity
    @State private var activity: [ActivityItem] = []

    private var meId: Int { Int(userSession.userId) }
    
    // 👇 NEW: allow caller to choose initial tab (defaults to .requests)
    init(initialTab: Tab = .requests) {
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 0) {
                tabs
                Group {
                    switch tab {
                    case .requests: requestsList
                    case .activity: activityList
                    }
                }
                .transition(.opacity)
            }
            if loading { ProgressView().tint(.white) }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task { await load() }
            let locals = LocalActivityStore.load()
            if !locals.isEmpty {
                for item in locals {
                    if !activity.contains(where: { $0.id == item.id }) {
                        activity.insert(item, at: 0)
                    }
                }
            }
        }
        .refreshable { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .openNotificationsFromPush)) { _ in
            withAnimation(.easeInOut(duration: 0.18)) { tab = .activity }
            Task { await load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newActivitySaved)) { _ in
            // 👇 merge new local items into activity array
            let locals = LocalActivityStore.load()
            for item in locals {
                if !activity.contains(where: { $0.id == item.id }) {
                    activity.insert(item, at: 0)
                }
            }
        }
    }

    private var tabs: some View {
        HStack(spacing: 8) {
            pill(.requests, title: lang == "es" ? "Solicitudes" : "Requests", count: requestRows.count)
            pill(.activity, title: lang == "es" ? "Actividad" : "Activity", count: activity.count)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func pill(_ target: Tab, title: String, count: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { tab = target }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                if count > 0 {
                    Text("\(count)")
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.white.opacity(0.15)).clipShape(Capsule())
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(
                target == tab
                ? AnyView(LinearGradient(colors: [.neonCyan.opacity(0.55), .neonPurple.opacity(0.55)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                : AnyView(Color.white.opacity(0.10))
            )
            .clipShape(Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Split-row model (Instagram-style)
    private enum RequestCell: Identifiable, Hashable {
        case pending(FollowRequest)
        case accepted(FollowRequest, Date)
        case followBack(FollowRequest)

        var id: String {
            switch self {
            case .pending(let r):     return "p-\(r.followerId)"
            case .accepted(let r, _): return "a-\(r.followerId)"
            case .followBack(let r):  return "f-\(r.followerId)"
            }
        }
    }

    private var requestRows: [RequestCell] {
        var rows: [RequestCell] = []
        for req in requests {
            if accepted.contains(req.followerId) {
                let ts = acceptedAt[req.followerId] ?? Date()
                rows.append(.accepted(req, ts))     // Row 1: Accepted
                rows.append(.followBack(req))       // Row 2: Follow/Following
            } else {
                rows.append(.pending(req))
            }
        }
        return rows
    }

    // MARK: - Requests List (two rows after acceptance)
    private var requestsList: some View {
        Group {
            if requestRows.isEmpty {
                emptyState(icon: "person.crop.circle.badge.plus",
                           title: lang == "es" ? "Sin solicitudes" : "No requests",
                           message: lang == "es" ? "Aquí verás cuando alguien quiera seguirte."
                                                 : "When someone requests to follow you, it’ll show up here.")
            } else {
                List {
                    ForEach(requestRows) { row in
                        rowView(for: row)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func rowView(for row: RequestCell) -> some View {
        switch row {
        case .pending(let req):
            PendingRequestRow(
                request: req,
                isBusy: busyIds.contains(req.followerId),
                acceptAction: { Task { await accept(req) } },
                rejectAction: { Task { await reject(req.followerId) } }
            )

        case .accepted(let req, let at):
            AcceptedInfoRow(request: req, acceptedAt: at)

        case .followBack(let req):
            FollowBackRow(
                request: req,
                isFollowing: followedBack.contains(req.followerId),
                isBusy: busyIds.contains(req.followerId),
                followAction: { Task { await followBack(req.followerId) } }
            )
        }
    }

    // MARK: - Activity List
    private var activityList: some View {
        Group {
            if activity.isEmpty {
                emptyState(icon: "bell",
                           title: lang == "es" ? "Sin actividad reciente" : "No recent activity",
                           message: lang == "es" ? "Tus notificaciones aparecerán aquí."
                                                 : "Your notifications will show up here.")
            } else {
                List {
                    ForEach(activity) { item in
                        ActivityRow(item: item, lang: lang)
                            .contentShape(Rectangle()) // make the whole row tappable
                            .onTapGesture { handleTap(on: item) }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .padding(.horizontal)
    }

    private func handleTap(on item: ActivityItem) {
        let t = item.type.uppercased()

        // Prefer entityId for “where to go”
        if let entityId = item.entityId {
            switch t {
            case "CHAT", "CHAT_MESSAGE", "MESSAGE":
                NotificationCenter.default.post(name: .openChatFromPush, object: String(entityId))
                return

            case "EVENT", "EVENT_INVITE", "LIKE", "COMMENT":
                // Assuming likes/comments attach to an event/post id
                NotificationCenter.default.post(name: .openEventFromPush, object: String(entityId))
                return

            default:
                break
            }
        }

        // If we don’t have an entityId, fall back on the actor
        switch t {
        case "FOLLOWED_YOU", "ACCEPTED_REQUEST":
            // If you already have a profile routing notification, use it here.
            // Otherwise, land them on Requests tab as a reasonable fallback:
            withAnimation(.easeInOut(duration: 0.18)) { tab = .requests }
        case "PUSH":
            // A generic push with no target — stay here
            break
        default:
            break
        }
    }


    // MARK: - Actions
    @MainActor
    private func load() async {
        loading = true
        error = nil
        defer { loading = false }

        async let serverPending = SocialAPI.fetchRequests(limit: 100)
        async let act  = NotificationsAPI.fetchActivity(limit: 100)
        do {
            let (pending, a) = try await (serverPending, act)

            // Accepted rows we must keep visible
            let stickyAccepted = AcceptedStickyStore.load(meId: meId)
            accepted = Set(stickyAccepted.map { $0.followerId })

            // Load acceptance timestamps
            let meta = AcceptedMetaStore.load(meId: meId)
            var accMap: [Int: Date] = [:]
            let isoFmt = ISO8601DateFormatter()
            for (k, v) in meta { if let d = isoFmt.date(from: v) { accMap[k] = d } }
            acceptedAt = accMap

            // Merge sticky + current pending
            requests = mergeUnique(stickyAccepted + pending)
            activity = a

            // ⚡️Consume local echoes addressed to me (so the SENDER sees "accepted your request")
            let echoes = AcceptedEchoBridge.consume(for: meId)
            if !echoes.isEmpty {
                for e in echoes {
                    let item = ActivityItem(type: "ACCEPTED_REQUEST",
                                            actorId: e.actorId,
                                            username: e.actorUsername,
                                            displayName: e.actorDisplayName,
                                            avatarUrl: nil,
                                            createdAt: e.createdAt,
                                            entityId: nil,
                                            entityThumb: nil)
                    insertActivityIfMissing(item)
                }
            }

            // FOLLOWING STATE (server truth + sticky backup)
            var fb = FollowedBackStickyStore.load(meId: meId) // what we’ve followed locally
            do {
                let myFollowing = try await SocialAPI.fetch(.following(userId: meId), limit: 500)
                fb.formUnion(myFollowing.map { $0.id })
            } catch { /* non-fatal */ }

            // keep only ids present in the list
            let requestIds = Set(requests.map { $0.followerId })
            followedBack = fb.intersection(requestIds)
            FollowedBackStickyStore.save(followedBack, meId: meId)

            busyIds = busyIds.intersection(requestIds)
        } catch {
            self.error = error.localizedDescription
        }
    }

    
    private func mergeUnique(_ arr: [FollowRequest]) -> [FollowRequest] {
        var seen = Set<Int>(), out: [FollowRequest] = []
        for r in arr where seen.insert(r.followerId).inserted { out.append(r) }
        return out.sorted { $0.requestedAt > $1.requestedAt }
    }

    // Insert a local "activity" if backend hasn't sent one yet
    @MainActor
    private func insertActivityIfMissing(_ item: ActivityItem) {
        if !activity.contains(where: { $0.type.uppercased() == item.type.uppercased() && $0.actorId == item.actorId }) {
            activity.insert(item, at: 0)
        }
    }

    @MainActor
    private func accept(_ req: FollowRequest) async {
        let followerId = req.followerId
        guard !busyIds.contains(followerId) else { return }
        busyIds.insert(followerId)
        defer { busyIds.remove(followerId) }

        do {
            try await SocialAPI.acceptRequest(from: followerId)
            accepted.insert(followerId)

            let now = Date()
            acceptedAt[followerId] = now
            var meta = AcceptedMetaStore.load(meId: meId)
            meta[followerId] = ISO8601DateFormatter().string(from: now)
            AcceptedMetaStore.save(meta, meId: meId)

            AcceptedStickyStore.upsert(req, meId: meId)
            SocialBus.post(.init(kind: .requestAccepted(followerId: followerId)))

            // --- A) Recipient sees "started following you" immediately
            let iso = ISO8601DateFormatter().string(from: now)
            let synthetic = ActivityItem(
                type: "FOLLOWED_YOU",
                actorId: followerId,
                username: req.username,
                displayName: req.displayName,
                avatarUrl: nil,
                createdAt: iso
            )
            insertActivityIfMissing(synthetic)

            // --- B) Sender should see "accepted your request" when they open their Activity
            // Put a tiny echo into the local bridge for the sender's userId
            AcceptedEchoBridge.enqueue(
                targetUserId: followerId,
                actorId: meId,
                actorUsername: userSession.username,
                actorDisplayName: userSession.firstName.isEmpty && userSession.lastName.isEmpty
                    ? nil
                    : "\(userSession.firstName) \(userSession.lastName)".trimmingCharacters(in: .whitespaces)
            )

            // Resolve avatar asynchronously and update the inserted FOLLOWED_YOU row
            Task {
                if let url = await AvatarResolver.fetchAvatarURL(userId: followerId) {
                    if let idx = await MainActor.run(body: { activity.firstIndex(where: { $0.type.uppercased() == "FOLLOWED_YOU" && $0.actorId == followerId }) }) {
                        await MainActor.run {
                            let cur = activity[idx]
                            activity[idx] = ActivityItem(
                                id: cur.id,
                                type: cur.type,
                                actorId: cur.actorId,
                                username: cur.username,
                                displayName: cur.displayName,
                                avatarUrl: url,
                                createdAt: cur.createdAt,
                                entityId: cur.entityId,
                                entityThumb: cur.entityThumb
                            )
                        }
                    }
                }
            }
        } catch { }
    }

    @MainActor
    private func reject(_ followerId: Int) async {
        guard !busyIds.contains(followerId) else { return }
        busyIds.insert(followerId)
        defer { busyIds.remove(followerId) }

        do {
            try await SocialAPI.rejectRequest(from: followerId)
            requests.removeAll { $0.followerId == followerId }
            accepted.remove(followerId)
            followedBack.remove(followerId)

            var meta = AcceptedMetaStore.load(meId: meId)
            meta.removeValue(forKey: followerId)
            AcceptedMetaStore.save(meta, meId: meId)

            AcceptedStickyStore.remove(followerId: followerId, meId: meId)
            FollowedBackStickyStore.remove(followerId, meId: meId)

            SocialBus.post(.init(kind: .requestRejected(followerId: followerId)))
        } catch { }
    }

    @MainActor
    private func followBack(_ followerId: Int) async {
        guard !busyIds.contains(followerId) else { return }
        busyIds.insert(followerId)
        defer { busyIds.remove(followerId) }

        do {
            // Backend: creates/updates follow(me -> followerId). If reverse exists, it becomes ACCEPTED (mutual).
            _ = try await SocialAPI.follow(userId: followerId)

            // Front: mark as followed, persist so other screens & reloads see it as Following
            followedBack.insert(followerId)
            FollowedBackStickyStore.insert(followerId, meId: meId)

            // Optional: broadcast so profile/relationship headers update instantly
            SocialBus.post(.init(kind: .followed(userId: followerId)))
        } catch { }
    }

    // MARK: - Little helpers
    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title).foregroundStyle(.white.opacity(0.7))
            Text(title).font(.subheadline).foregroundStyle(.white)
            Text(message).font(.caption).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Separated Rows

// Wrapper that uses simple PeopleAvatar; resolves avatar from server.
private struct RequestAvatar: View {
    let request: FollowRequest
    let size: CGFloat
    @State private var resolved: String?

    var body: some View {
        PeopleAvatar(url: resolved, size: size)
            .task {
                if resolved == nil {
                    resolved = await AvatarResolver.fetchAvatarURL(userId: request.followerId)
                }
            }
    }
}

// 1) Pending request row
private struct PendingRequestRow: View {
    let request: FollowRequest
    let isBusy: Bool
    let acceptAction: () -> Void
    let rejectAction: () -> Void
    @AppStorage("selectedLanguage") private var lang: String = "en"

    var body: some View {
        HStack(spacing: 10) {
            RequestAvatar(request: request, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayNameOrUsername)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(lang == "es" ? "quiere seguirte" : "wants to follow you")
                    .font(.caption).foregroundStyle(.white.opacity(0.75))
                if !request.requestedAt.isEmpty {
                    Text(relativeShort(request.requestedAt))
                        .font(.caption2).foregroundStyle(.white.opacity(0.55))
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Button(action: rejectAction) {
                    Text(lang == "es" ? "Ignorar" : "Ignore")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .minimumScaleFactor(0.9)
                }
                .buttonStyle(.bordered)
                .tint(.white)
                .frame(minWidth: 72) // prevent wrap

                Button(action: acceptAction) {
                    if isBusy { ProgressView().tint(.white) }
                    else {
                        Text(lang == "es" ? "Aceptar" : "Accept")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .minimumScaleFactor(0.9)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .frame(minWidth: 84) // prevent wrap
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.10), lineWidth: 1))
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { acceptAction() } label: {
                Label(lang == "es" ? "Aceptar" : "Accept", systemImage: "checkmark")
            }.tint(.green)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button { rejectAction() } label: {
                Label(lang == "es" ? "Ignorar" : "Ignore", systemImage: "xmark")
            }
            .tint(.gray)
        }
    }

    private var displayNameOrUsername: String {
        if let d = request.displayName, !d.isEmpty { return d }
        return "@\(request.username)"
    }
}

// 2) Accepted info row
private struct AcceptedInfoRow: View {
    let request: FollowRequest
    let acceptedAt: Date
    @AppStorage("selectedLanguage") private var lang: String = "en"

    var body: some View {
        HStack(spacing: 10) {
            RequestAvatar(request: request, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayNameOrUsername)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                // Updated copy:
                Text(lang == "es" ? "Aceptaste su solicitud" : "You accepted their request")
                    .font(.caption).foregroundStyle(.white.opacity(0.75))
                Text(shortAgo(from: acceptedAt))
                    .font(.caption2).foregroundStyle(.white.opacity(0.55))
            }

            Spacer(minLength: 8)

            Text(lang == "es" ? "Aceptado" : "Accepted")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.white.opacity(0.14))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))
        }
        .padding(10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.10), lineWidth: 1))
    }

    private var displayNameOrUsername: String {
        if let d = request.displayName, !d.isEmpty { return d }
        return "@\(request.username)"
    }
}

// 3) Follow row
private struct FollowBackRow: View {
    let request: FollowRequest
    let isFollowing: Bool
    let isBusy: Bool
    let followAction: () -> Void
    @AppStorage("selectedLanguage") private var lang: String = "en"

    var body: some View {
        HStack(spacing: 10) {
            RequestAvatar(request: request, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayNameOrUsername)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(lang == "es" ? "¡Ahora puedes seguirle de vuelta!" : "You can follow back now")
                    .font(.caption).foregroundStyle(.white.opacity(0.75))
            }

            Spacer(minLength: 8)

            if isFollowing {
                Text(lang == "es" ? "Siguiendo" : "Following")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.white.opacity(0.14))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))
            } else {
                Button(action: followAction) {
                    if isBusy { ProgressView().tint(.white) }
                    else { Text(lang == "es" ? "Seguir" : "Follow").font(.caption.weight(.semibold)) }
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .clipShape(Capsule())
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.10), lineWidth: 1))
    }

    private var displayNameOrUsername: String {
        if let d = request.displayName, !d.isEmpty { return d }
        return "@\(request.username)"
    }
}

// Activity rows
private struct ActivityRow: View {
    let item: ActivityItem
    let lang: String

    @State private var resolvedAvatar: String?

    private var displayName: String {
        item.displayName?.isEmpty == false ? item.displayName! : "@\(item.username)"
    }
    private var messageText: String {
        switch item.type.uppercased() {
        case "FOLLOWED_YOU":     return lang == "es" ? "te ha seguido" : "started following you"
        case "ACCEPTED_REQUEST": return lang == "es" ? "aceptó tu solicitud" : "accepted your request"
        case "LIKE":             return lang == "es" ? "le gustó tu foto" : "liked your photo"
        case "COMMENT":          return lang == "es" ? "comentó tu publicación" : "commented on your post"
        case "PUSH":             return lang == "es" ? "nueva notificación" : "new notification"
        default:                 return lang == "es" ? "nueva actividad" : "new activity"
        }
    }
    private var timeAgo: String? {
        guard let ts = item.createdAt, let d = parseISOish(ts) else { return nil }
        return shortAgoGeneric(from: d)
    }

    var body: some View {
        HStack(spacing: 10) {
            PeopleAvatar(url: resolvedAvatar ?? nilIfBlank(item.avatarUrl), size: 40)
                .task {
                    if resolvedAvatar == nil, (item.avatarUrl?.isEmpty ?? true), item.actorId > 0 {
                        resolvedAvatar = await AvatarResolver.fetchAvatarURL(userId: item.actorId)
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(messageText)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let ago = timeAgo {
                    Text(ago)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }

            Spacer(minLength: 8)

            if let thumb = item.entityThumb, let url = URL(string: thumb) {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.18) }
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.2), lineWidth: 1))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.10), lineWidth: 1))
    }

    private func shortAgoGeneric(from date: Date) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.minute, .hour, .day, .weekOfMonth, .month, .year]
        f.maximumUnitCount = 1
        f.unitsStyle = .abbreviated
        return f.string(from: date, to: Date()) ?? ""
    }
    private func parseISOish(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        if let d = iso.date(from: s + "Z") { return d }
        return nil
    }
}

// Small bits
private struct CapsuleLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundColor(.white)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color.white.opacity(0.14))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))
    }
}

private func nilIfBlank(_ s: String?) -> String? {
    guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
    return s
}

// Shared time helpers
private func relativeShort(_ iso: String) -> String {
    let isoFmt = ISO8601DateFormatter()
    guard let d = isoFmt.date(from: iso) ?? isoFmt.date(from: iso + "Z") else { return "" }
    let f = DateComponentsFormatter()
    f.allowedUnits = [.minute, .hour, .day, .weekOfMonth, .month, .year]
    f.maximumUnitCount = 1
    f.unitsStyle = .abbreviated
    return f.string(from: d, to: Date()) ?? ""
}
private func shortAgo(from date: Date) -> String {
    let f = DateComponentsFormatter()
    f.allowedUnits = [.second, .minute, .hour, .day, .weekOfMonth, .month, .year]
    f.maximumUnitCount = 1
    f.unitsStyle = .abbreviated
    return f.string(from: date, to: Date()) ?? ""
}

// MARK: - Avatar (simple, as requested)
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

struct LocalActivityStore {
    private static let key = "local_activity:v1"

    static func load() -> [ActivityItem] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([ActivityItem].self, from: data)) ?? []
    }

    static func save(_ items: [ActivityItem]) {
        if let data = try? JSONEncoder().encode(Array(items.prefix(300))) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func insert(_ item: ActivityItem) {
        var all = load()
        all.insert(item, at: 0)
        save(all)
    }
}

