//
//  ChatLauncher.swift
//  eventFront
//

import SwiftUI
import Foundation

@MainActor
final class ChatLauncher: ObservableObject {
    @Published var activeRoom: ChatRoomSummaryDTO? = nil

    private func fetchSummary(roomId: Int) async throws -> ChatRoomSummaryDTO {
        let list = try await ChatAPI.shared.myRooms()
        if let found = list.first(where: { $0.id == roomId }) { return found }
        return ChatRoomSummaryDTO(
            id: roomId, type: .DIRECT, displayName: "Chat",
            iconUrl: nil, lastMessagePreview: nil, lastMessageAt: nil, unreadCount: 0
        )
    }

    func openDirect(eventId: Int, otherUserId: Int) async {
        do {
            let id = try await ChatAPI.shared.startDirect(eventId: eventId, otherUserId: otherUserId)
            activeRoom = try await fetchSummary(roomId: id)
        } catch { print("openDirect error", error.localizedDescription) }
    }

    func openResale(resalePostId: Int, sellerId: Int) async {
        do {
            let id = try await ChatAPI.shared.startResale(resalePostId: resalePostId, sellerId: sellerId)
            activeRoom = try await fetchSummary(roomId: id)
        } catch { print("openResale error", error.localizedDescription) }
    }

    func openPromoterGroup(eventId: Int, promoterIds: [Int]) async {
        do {
            let id = try await ChatAPI.shared.promoterGroup(eventId: eventId, promoterUserIds: promoterIds)
            activeRoom = try await fetchSummary(roomId: id)
        } catch { print("openPromoterGroup error", error.localizedDescription) }
    }
}

struct ChatLauncherHost<Content: View>: View {
    @StateObject var launcher = ChatLauncher()
    @EnvironmentObject var session: UserSession
    @StateObject private var stomp = StompClient(baseURL: ChatAPI.shared.baseURL)

    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack { content() }
            .sheet(item: $launcher.activeRoom) { room in
                NavigationStack {
                    ChatRoomView(room: room, myUserId: Int(session.userId))
                        .environmentObject(stomp)
                }
            }
            .environmentObject(launcher)
            .task {
                ChatAPI.shared.setTokenProvider { TokenManager.shared.getAccessToken() }
                stomp.connect()
            }
    }
}

