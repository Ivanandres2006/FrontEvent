import SwiftUI

struct FollowRequestsView: View {
    @State private var requests: [FollowRequest] = []
    @State private var loading = true
    @State private var error: String?
    @State private var working: Int?

    var body: some View {
        List {
            LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            ForEach(requests) { r in
                HStack(spacing: 12) {
                    Circle().fill(.gray.opacity(0.2)).frame(width: 40, height: 40) // avatar placeholder
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.displayName ?? r.username).font(.headline)
                        Text("@\(r.username)").foregroundStyle(.secondary).font(.subheadline)
                    }
                    Spacer()
                    HStack {
                        Button("Accept") { Task { await accept(r) } }
                            .buttonStyle(.borderedProminent)
                            .disabled(working == r.followerId)
                        Button("Ignore") { Task { await reject(r) } }
                            .buttonStyle(.bordered)
                            .disabled(working == r.followerId)
                    }
                }
            }
        }
        .navigationTitle("Follow Requests")
        .overlay {
            if loading { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
            if !loading && requests.isEmpty && error == nil {
                ContentUnavailableView("No requests", systemImage: "person.crop.circle.badge.questionmark")
            }
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do { requests = try await SocialAPI.fetchRequests(limit: 100) }
        catch { self.error = "Failed to load requests." }
    }

    private func accept(_ r: FollowRequest) async {
        working = r.followerId
        defer { working = nil }
        do {
            try await SocialAPI.acceptRequest(from: r.followerId)
            requests.removeAll { $0.followerId == r.followerId }
        } catch { self.error = "Failed to accept." }
    }

    private func reject(_ r: FollowRequest) async {
        working = r.followerId
        defer { working = nil }
        do {
            try await SocialAPI.rejectRequest(from: r.followerId)
            requests.removeAll { $0.followerId == r.followerId }
        } catch { self.error = "Failed to ignore." }
    }
}
