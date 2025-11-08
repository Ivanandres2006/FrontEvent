import Foundation

@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var messages: [ChatMessageDTO] = []  // oldest → newest
    @Published var isLoading = false
    @Published var isSending = false
    @Published var errorText: String?
    @Published var hasMore = false
    
    @Published var locallySoldOfferIds: Set<Int> = []
    @Published var locallyTransferredOfferIds: Set<Int> = []

    let roomId: Int
    let myUserId: Int

    private var oldestId: Int?
    private var subscription: StompSession?
    private let pageSize = 30                         // <— NEW: consistent page size

    init(roomId: Int, myUserId: Int) {
        self.roomId = roomId
        self.myUserId = myUserId
    }

    func connectAndLoad() async {
        subscription = ChatAPI.shared.subscribe(roomId: roomId) { [weak self] dto in
            guard let self else { return }
            Task { @MainActor in
                if let idx = self.messages.firstIndex(where: { $0.id == dto.id }) {
                    self.messages[idx] = dto               // <- update in place (status changes)
                } else {
                    self.messages.append(dto)              // <- new message
                }
            }
        }

        await refresh()
        try? await ChatAPI.shared.markRead(roomId: roomId)
    }
    
    func markOfferSold(messageId: Int) {
        // re-assign to trigger @Published
        var s = locallySoldOfferIds
        s.insert(messageId)
        locallySoldOfferIds = s
        upsertLocalStatus(messageId: messageId, to: "SOLD")
    }

    func markOfferTransferred(messageId: Int) {
        var t = locallyTransferredOfferIds
        t.insert(messageId)
        locallyTransferredOfferIds = t
        upsertLocalStatus(messageId: messageId, to: "TRANSFERRED")
    }

    private func upsertLocalStatus(messageId: Int, to newStatus: String) {
        guard let i = messages.firstIndex(where: { $0.id == messageId }) else { return }
        var obj: [String: Any] = [:]
        if let s = messages[i].metaJson,
           let existing = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any] {
            obj = existing
        }
        obj["status"] = newStatus
        if let data = try? JSONSerialization.data(withJSONObject: obj),
           let newJson = String(data: data, encoding: .utf8) {
            messages[i] = messages[i].replacing(metaJson: newJson)
        }
    }
    
    func disconnect() {
        subscription?.disconnect()
        subscription = nil
    }

    deinit { subscription?.disconnect() }

    // MARK: - Pagination / Loading

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let page = try await ChatAPI.shared.getMessages(
                roomId: roomId,
                limit: pageSize,
                beforeId: nil
            )
            messages = page
            oldestId = page.first?.id
            hasMore = page.count == pageSize          // <— if page filled, probably more exists
        } catch {
            errorText = error.localizedDescription
        }
    }

    func loadMore() async {
        guard !isLoading, hasMore, let before = oldestId else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let page = try await ChatAPI.shared.getMessages(
                roomId: roomId,
                limit: pageSize,
                beforeId: before
            )
            if page.isEmpty {
                hasMore = false                        // <— nothing else
                return
            }
            messages.insert(contentsOf: page, at: 0)
            oldestId = page.first?.id
            hasMore = page.count == pageSize          // <— still more if filled
        } catch {
            errorText = error.localizedDescription
        }
    }

    // MARK: - Sending

    func sendText(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSending = true
        defer { isSending = false }

        do {
            _ = try await ChatAPI.shared.sendText(roomId: roomId, text: trimmed)
        } catch {
            errorText = error.localizedDescription
        }
    }
    
    @MainActor func sendOffer(amount: Double, currency: String = "USD", parentId: Int? = nil) async {
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            _ = try await ChatAPI.shared.sendOffer(roomId: roomId, amount: amount, currency: currency, parentId: parentId)
            // messages will arrive via STOMP; or you can optimistically append a local stub
        } catch {
            errorText = error.localizedDescription
        }
    }

    func sendImage(_ imageData: Data, caption: String?) async {
        isSending = true
        defer { isSending = false }

        do {
            _ = try await ChatAPI.shared.sendImage(roomId: roomId, imageData: imageData, caption: caption)
        } catch {
            errorText = error.localizedDescription
        }
    }
}
