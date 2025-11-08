import SwiftUI
import PhotosUI
import UIKit

struct ChatRoomView: View {
    @AppStorage("selectedLanguage") var lang: String = "en"
    @Environment(\.dismiss) private var dismiss
    
    let room: ChatRoomSummaryDTO
    let myUserId: Int
    
    @StateObject private var store: ChatStore
    @State private var draft = ""
    @State private var photoItem: PhotosPickerItem? = nil
    
    @State private var showOfferSheet = false
    @State private var offerAmountText = ""
    
    @State private var buyCtx: BuyFromOfferContext?
    
    enum ImagePrep {
        static func prepareForUpload(_ data: Data,
                                     maxDimension: CGFloat = 1024,   // smaller target
                                     jpegQuality: CGFloat = 0.65) -> Data? {
            guard let ui = UIImage(data: data) else { return nil }

            // Work in pixels, not points
            let inW = CGFloat(ui.cgImage?.width  ?? Int(ui.size.width  * ui.scale))
            let inH = CGFloat(ui.cgImage?.height ?? Int(ui.size.height * ui.scale))

            let scale = min(1, maxDimension / max(inW, inH))
            let outW  = floor(inW * scale)
            let outH  = floor(inH * scale)
            let outSizePx = CGSize(width: outW, height: outH)

            // Render at scale = 1 so size = pixel size
            let fmt = UIGraphicsImageRendererFormat()
            fmt.scale  = 1
            fmt.opaque = true

            let img = UIGraphicsImageRenderer(size: outSizePx, format: fmt).image { _ in
                ui.draw(in: CGRect(origin: .zero, size: outSizePx))
            }

            var jpeg = img.jpegData(compressionQuality: jpegQuality)

            // Safety valve: if still big, compress a bit more
            if let j = jpeg, j.count > 600_000 { // ~600 KB cap
                jpeg = img.jpegData(compressionQuality: 0.55)
            }
            return jpeg
        }
    }

    
    private var isGroupRoom: Bool {
        // treat anything that isn't a 1:1 chat as group
        room.type != .DIRECT && room.type != .RESALE
    }
    
    
    init(room: ChatRoomSummaryDTO, myUserId: Int) {
        self.room = room
        self.myUserId = myUserId
        _store = StateObject(wrappedValue: ChatStore(roomId: room.id, myUserId: myUserId))
    }

    private var isShowingError: Binding<Bool> {
        Binding(get: { store.errorText != nil }, set: { _ in store.errorText = nil })
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                MessageList(
                    messages: store.messages,
                    isLoading: store.isLoading,
                    hasMore: store.hasMore,
                    myUserId: myUserId,
                    lang: lang,
                    isGroup: isGroupRoom,
                    soldIds: store.locallySoldOfferIds,        // ✅ add
                    onLoadMore: { Task { await store.loadMore() } }
                )
                

                ComposeBar(
                    text: $draft,
                    photoItem: $photoItem,
                    isSending: store.isSending,
                    lang: lang,
                    onSend: { text in
                        Task { await store.sendText(text); draft = "" }
                    },
                    onOffer: { showOfferSheet = true }         // ← add
                )
                .background(.ultraThinMaterial)
                .overlay(Divider().opacity(0.12), alignment: .top)
            }
        }
        .navigationTitle(room.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                        Text(lang == "es" ? "Atrás" : "Back").font(.subheadline.weight(.semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: ChatSettingsView(room: room)) {
                    Image(systemName: "ellipsis.circle").foregroundColor(.white.opacity(0.9))
                }
            }
        }
        .sheet(isPresented: $showOfferSheet) {
            OfferSheet(lang: lang,
                       amountText: $offerAmountText,
                       onCancel: { showOfferSheet = false },
                       onSend: {
                           if let amt = Double(offerAmountText) {
                               Task { await store.sendOffer(amount: amt) }
                               offerAmountText = ""
                               showOfferSheet = false
                           }
                       })
        }
        .task { await store.connectAndLoad() }
        .task(id: photoItem) {
            guard let item = photoItem else { return }
            defer { photoItem = nil }

            if let raw = try? await item.loadTransferable(type: Data.self),
               let prepared = ImagePrep.prepareForUpload(raw, maxDimension: 1024, jpegQuality: 0.65) {
                await store.sendImage(prepared, caption: nil)
            } else if let raw = try? await item.loadTransferable(type: Data.self) {
                await store.sendImage(raw, caption: nil) // fallback
            }
        }
        .alert(isPresented: isShowingError) {
            Alert(title: Text("Error"),
                  message: Text(store.errorText ?? ""),
                  dismissButton: .default(Text("OK")))
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .offerMarkedSold)
                .receive(on: RunLoop.main)                // 👈 add this
        ) { n in
            if let mid = n.userInfo?["messageId"] as? Int {
                print("🔄 markOfferSold for messageId:", mid)
                store.markOfferSold(messageId: mid)
            }
        }
        // In ChatRoomView body chain
        .onReceive(
            NotificationCenter.default.publisher(for: .openBuyFromOffer)
                .receive(on: RunLoop.main)     // <- ensure main thread
        ) { n in
            let postId   = n.userInfo?["resalePostId"] as? Int   // optional
            guard
                let offerId  = n.userInfo?["offerMessageId"] as? Int,
                let amount   = n.userInfo?["amount"] as? Double,
                let currency = n.userInfo?["currency"] as? String
            else { return }

            buyCtx = .init(
                resalePostId: postId,
                offerMessageId: offerId,
                amount: amount,
                currency: currency
            )
        }
        .sheet(item: $buyCtx) { ctx in
            BuyFromOfferLauncher(
                ctx: ctx,
                onSold: { mid in
                    Task { @MainActor in
                        store.markOfferSold(messageId: mid)   // ✅ update local state immediately
                    }
                },
                onDismiss: { buyCtx = nil }
            )
        }
    }
}

// MARK: - Subviews

private struct MessageList: View {
    let messages: [ChatMessageDTO]
    let isLoading: Bool
    let hasMore: Bool
    let myUserId: Int
    let lang: String
    let isGroup: Bool
    let soldIds: Set<Int>
    let onLoadMore: () -> Void
    

    // show header at the start, when sender changes, or after 2 min gap
    private func shouldShowSenderHeader(at i: Int) -> Bool {
        guard isGroup else { return false }
        let cur = messages[i]
        // don't show my own name
        if (cur.senderId ?? -1) == myUserId { return false }
        if i == 0 { return true }
        let prev = messages[i - 1]
        if prev.senderId != cur.senderId { return true }
        return abs(cur.createdAt.timeIntervalSince(prev.createdAt)) > 120
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {

                    if hasMore {
                        HStack {
                            Spacer()
                            Button(action: onLoadMore) {
                                HStack(spacing: 6) {
                                    if isLoading { ProgressView().tint(.gold) }
                                    Text(lang == "es" ? "Cargar más" : "Load more")
                                        .font(.footnote.weight(.semibold))
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                            }
                            .disabled(isLoading)
                            Spacer()
                        }
                        .padding(.top, 8)
                    }

                    if messages.isEmpty && !isLoading {
                        EmptyStater().padding(.top, 40)
                    }

                    // Use indices so we can compare with previous message
                    ForEach(messages.indices, id: \.self) { i in
                        let msg = messages[i]
                        ChatMessageBubble(
                            msg: msg,
                            myUserId: myUserId, // 👈 NEW
                            isMe: (msg.senderId ?? -1) == myUserId,
                            showSenderHeader: shouldShowSenderHeader(at: i),
                            locallySold: soldIds.contains(msg.id)
                        )
                        .id(msg.id)
                        .padding(.horizontal, 12)
                    }

                    Color.clear.frame(height: 6)
                }
                .padding(.top, 6)
            }
            .onChange(of: messages.last?.id) { last in
                if let last { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last, anchor: .bottom) } }
            }
        }
    }
}

private struct EmptyStater: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.bubble")
                .font(.system(size: 30))
                .foregroundColor(.white.opacity(0.35))
            Text("No messages yet")
                .foregroundColor(.white.opacity(0.6))
                .font(.footnote)
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }
}

private struct ComposeBar: View {
    @Binding var text: String
    @Binding var photoItem: PhotosPickerItem?
    let isSending: Bool
    let lang: String
    let onSend: (String) -> Void
    let onOffer: (() -> Void)?

    init(text: Binding<String>,
             photoItem: Binding<PhotosPickerItem?>,
             isSending: Bool,
             lang: String,
             onSend: @escaping (String) -> Void,
         onOffer: (() -> Void)? = nil) {
        self._text = text
        self._photoItem = photoItem
        self.isSending = isSending
        self.lang = lang
        self.onSend = onSend
        self.onOffer = onOffer
    }
    
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                Image(systemName: "photo")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.gold)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
            
            if let onOffer = onOffer {
                Button(action: onOffer) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.gold)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 1))
                }
            }

            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(lang == "es" ? "Mensaje…" : "Message…")
                        .foregroundColor(.white.opacity(0.45))
                        .padding(.horizontal, 14)
                }
                TextField("", text: $text, axis: .vertical)
                    .textInputAutocapitalization(.sentences)
                    .disableAutocorrection(false)
                    .foregroundColor(.white)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .lineLimit(1...5)
            }
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))

            if isSending {
                ProgressView().tint(.gold).padding(.horizontal, 4)
            }

            Button {
                guard !trimmed.isEmpty else { return }
                onSend(trimmed)
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(trimmed.isEmpty ? .white.opacity(0.4) : .black)
                    .frame(width: 36, height: 36)
                    .background(trimmed.isEmpty ? Color.white.opacity(0.08) : Color.gold)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
            .disabled(trimmed.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - Bubble
// MARK: - Bubble

private struct ChatMessageBubble: View {
    let msg: ChatMessageDTO
    let myUserId: Int
    let isMe: Bool
    let showSenderHeader: Bool
    let locallySold: Bool

    // Viewer uses item: to avoid blank cover
    private struct ViewerItem: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let caption: String?
    }
    @State private var viewerItem: ViewerItem?

    @State private var showCounterSheet = false
    @State private var counterText = ""

    // Tuning
    private let maxBubbleWidth = min(UIScreen.main.bounds.width * 0.70, 340)
    private let corner: CGFloat = 16

    private var bubbleBG: LinearGradient {
        isMe
        ? LinearGradient(colors: [Color.gold.opacity(0.95), Color.gold.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)
        : LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    private var bubbleStroke: Color { isMe ? Color.black.opacity(0.10) : Color.white.opacity(0.10) }
    private var textColor: Color { isMe ? .black : .white }
    private var timeColor: Color { isMe ? .black.opacity(0.55) : .white.opacity(0.55) }

    private var offer: OfferMeta? {
        guard msg.type == .OFFER, let s = msg.metaJson, let d = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(OfferMeta.self, from: d)
    }

    private var effectiveStatus: String {
        if locallySold { return "SOLD" }
        return (offer?.status ?? "PENDING").uppercased()
    }
    private var isOfferPending:  Bool { effectiveStatus == "PENDING" }
    private var isOfferAccepted: Bool { effectiveStatus == "ACCEPTED" }
    private var isOfferSold:     Bool { effectiveStatus == "SOLD" }
    private var buyerIsMe:       Bool { (offer?.authorId ?? -1) == myUserId }
    private var showBuyButton:   Bool { isOfferAccepted && buyerIsMe && !isOfferSold }

    private var hasImage: Bool { msg.attachmentUrl != nil }
    private var hasText: Bool {
        guard let t = msg.text?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return !t.isEmpty
    }
    private var isMediaOnly: Bool { hasImage && !hasText && offer == nil }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if isMe { Spacer(minLength: 40) }

            // CONTENT
            VStack(alignment: .leading, spacing: 8) {
                if showSenderHeader, !isMe, let name = msg.senderUsername, !name.isEmpty {
                    Text(name)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.65))
                        .padding(.leading, 4)
                }

                // ----- OFFER CARD -----
                if let off = offer {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("💸 Offer").font(.headline).foregroundColor(textColor)
                        HStack {
                            Text("\(off.currency ?? "USD") \(String(format: "%.2f", off.amount ?? 0))")
                                .font(.title3.bold()).foregroundColor(textColor)
                            Spacer()
                            StatusPill(status: effectiveStatus)
                        }

                        if isOfferPending {
                            HStack(spacing: 8) {
                                if !isMe {
                                    Button("Accept") {
                                        Task { try? await ChatAPI.shared.acceptOffer(roomId: msg.chatId, messageId: msg.id) }
                                    }
                                    .buttonStyle(AccentCapsule(good: true))

                                    Button("Decline") {
                                        Task { try? await ChatAPI.shared.declineOffer(roomId: msg.chatId, messageId: msg.id) }
                                    }
                                    .buttonStyle(AccentCapsule(good: false))
                                }
                                Button("Counter") { showCounterSheet = true }
                                    .buttonStyle(PlainCapsule())
                            }
                        } else if isOfferSold {
                            Text("Sold")
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(textColor.opacity(0.75))
                        } else if showBuyButton {
                            let amt = off.amount ?? 0
                            Button("Buy for \(off.currency ?? "USD") \(String(format: "%.2f", amt))") {
                                var info: [String: Any] = [
                                    "offerMessageId": msg.id,
                                    "amount": amt,
                                    "currency": off.currency ?? "USD"
                                ]
                                if let pid = off.resalePostId { info["resalePostId"] = pid }
                                NotificationCenter.default.post(name: .openBuyFromOffer, object: nil, userInfo: info)
                            }
                            .buttonStyle(AccentCapsule(good: true))
                        }
                    }
                    .sheet(isPresented: $showCounterSheet) {
                        CounterSheet(text: $counterText) {
                            showCounterSheet = false
                        } onSend: {
                            if let amt = Double(counterText) {
                                Task {
                                    _ = try? await ChatAPI.shared.sendOffer(
                                        roomId: msg.chatId,
                                        amount: amt,
                                        currency: offer?.currency ?? "USD",
                                        parentId: msg.id
                                    )
                                }
                                counterText = ""
                                showCounterSheet = false
                            }
                        }
                    }

                // ----- IMAGE / TEXT -----
                } else {
                    // IMAGE
                    if let urlStr = msg.attachmentUrl, let url = URL(string: urlStr) {
                        Group {
                            if isMediaOnly {
                                // MEDIA BUBBLE (edge-to-edge image)
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .empty:
                                        ZStack {
                                            Rectangle().fill(Color.white.opacity(0.06))
                                            ProgressView().tint(.gold)
                                        }
                                        .frame(maxWidth: maxBubbleWidth, minHeight: 160, maxHeight: 320)

                                    case .success(let img):
                                        img.resizable()
                                            .scaledToFit()                     // preserve aspect ratio
                                            .frame(maxWidth: maxBubbleWidth)   // natural height
                                            .frame(maxHeight: 320)             // cap tall images
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                viewerItem = .init(url: url, caption: msg.text)
                                            }

                                    case .failure:
                                        ZStack {
                                            Rectangle().fill(Color.white.opacity(0.06))
                                            Image(systemName: "photo")
                                                .font(.title2)
                                                .foregroundColor(.white.opacity(0.6))
                                        }
                                        .frame(maxWidth: maxBubbleWidth, minHeight: 160, maxHeight: 320)
                                    @unknown default:
                                        EmptyView()
                                    }
                                }

                            } else {
                                // IMAGE CARD inside a regular bubble (has caption text)
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .empty:
                                        ZStack {
                                            RoundedRectangle(cornerRadius: corner)
                                                .fill(Color.white.opacity(0.06))
                                            ProgressView().tint(.gold)
                                        }
                                        .frame(maxWidth: maxBubbleWidth, minHeight: 160, maxHeight: 260)

                                    case .success(let img):
                                        img.resizable()
                                            .scaledToFit()                     // avoid awkward crop
                                            .frame(maxWidth: maxBubbleWidth)   // natural height
                                            .frame(maxHeight: 260)             // keep bubble compact
                                            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: corner)
                                                    .stroke(Color.white.opacity(isMe ? 0.10 : 0.15), lineWidth: 1)
                                            )
                                            .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                viewerItem = .init(url: url, caption: msg.text)
                                            }

                                    case .failure:
                                        RoundedRectangle(cornerRadius: corner)
                                            .fill(Color.white.opacity(0.06))
                                            .overlay(
                                                Image(systemName: "photo")
                                                    .font(.title2)
                                                    .foregroundColor(.white.opacity(0.6))
                                            )
                                            .frame(maxWidth: maxBubbleWidth, minHeight: 160, maxHeight: 260)
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                            }
                        }
                    }

                    // TEXT (for non-image or image+caption)
                    if let t = msg.text, !t.isEmpty, (msg.attachmentUrl == nil || !isMediaOnly) {
                        Text(t)
                            .foregroundColor(textColor)
                            .font(.body)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // TIME
                HStack {
                    Spacer()
                    Text(msg.createdAt, style: .time)
                        .font(.caption2)
                        .foregroundColor(timeColor)
                        .padding(.horizontal, isMediaOnly ? 8 : 0)
                        .padding(.bottom,   isMediaOnly ? 8 : 0)
                }
            }
            // Remove padding when the bubble is a pure image so the image hits the rounded edges
            .padding(.vertical, isMediaOnly ? 0 : 10)
            .padding(.horizontal, isMediaOnly ? 0 : 14)
            .frame(maxWidth: maxBubbleWidth, alignment: .leading)
            // For media-only, the image itself is the bubble; otherwise draw the regular bubble bg
            .background(alignment: .center) {
                if !isMediaOnly { bubbleBG }   // else it's empty (no background)
            }
                    .clipShape(
                RoundedCorner(
                    radius: corner,
                    corners: isMe ? [.topLeft, .topRight, .bottomLeft] : [.topLeft, .topRight, .bottomRight]
                )
            )
            .overlay(
                Group {
                    if !isMediaOnly {
                        RoundedCorner(
                            radius: corner,
                            corners: isMe ? [.topLeft, .topRight, .bottomLeft] : [.topLeft, .topRight, .bottomRight]
                        )
                        .stroke(bubbleStroke, lineWidth: 1)
                    }
                }
            )
            .shadow(color: .black.opacity(isMe ? 0.15 : 0.12), radius: 5, x: 0, y: 3)
            .fullScreenCover(item: $viewerItem) { item in
                PhotoViewer(url: item.url, caption: item.caption)
            }

            if !isMe { Spacer(minLength: 40) }
        }
        .padding(.vertical, 2)
    }
}



private struct StatusPill: View {
    let status: String
    var body: some View {
        let upper = status.uppercased()
        let bg: Color =
            upper == "ACCEPTED" ? Color.green.opacity(0.85) :
            upper == "DECLINED" ? Color.red.opacity(0.85) :
            upper == "SOLD"     ? Color.gray.opacity(0.9) : // 👈 new
            Color.white.opacity(0.18)

        Text(status.capitalized)
            .font(.caption.bold())
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(bg)
            .foregroundColor(.black)
            .clipShape(Capsule())
    }
}


private struct AccentCapsule: ButtonStyle {
    let good: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.bold())
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(good ? Color.gold : Color.white.opacity(0.10))
            .foregroundColor(good ? .black : .white)
            .clipShape(Capsule())
    }
}
private struct PlainCapsule: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.bold())
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.white.opacity(0.08))
            .foregroundColor(.white)
            .clipShape(Capsule())
    }
}
private struct CounterSheet: View {
    @Binding var text: String
    let onCancel: () -> Void
    let onSend: () -> Void
    var body: some View {
        NavigationStack {
            Form { TextField("New amount", text: $text).keyboardType(.decimalPad) }
            .navigationTitle("Counteroffer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) { Button("Send", action: onSend).disabled(Double(text) == nil) }
            }
        }
    }
}

// Helper shape for per-corner rounding
private struct RoundedCorner: Shape {
    var radius: CGFloat = 16
    var corners: UIRectCorner = [.allCorners]
    func path(in rect: CGRect) -> Path {
        let p = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(p.cgPath)
    }
}

private struct OfferSheet: View {
    let lang: String
    @Binding var amountText: String
    let onCancel: () -> Void
    let onSend: () -> Void
    var body: some View {
        NavigationStack {
            Form {
                TextField(lang == "es" ? "Monto" : "Amount", text: $amountText)
                    .keyboardType(.decimalPad)
            }
            .navigationTitle(lang == "es" ? "Oferta" : "Offer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lang=="es" ? "Cancelar" : "Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(lang=="es" ? "Enviar" : "Send", action: onSend)
                        .disabled(Double(amountText) == nil)
                }
            }
        }
    }
}

struct BuyFromOfferLauncher: View {
    let ctx: BuyFromOfferContext
    let onSold: (Int) -> Void
    var onDismiss: () -> Void

    @State private var post: ResalePostDTO?
    @State private var event: Event?
    @State private var loadFailed = false

    @AppStorage("userEmail") private var userEmail: String = ""

    var body: some View {
        Group {
            if let post, let event {
                BuyNowView(
                    resalePost: post,
                    event: .constant(event),
                    userEmail: userEmail,
                    accepted: .init(
                        messageId: ctx.offerMessageId,
                        amount: ctx.amount,
                        currency: ctx.currency
                    ),
                    onComplete: {
                        onSold(ctx.offerMessageId)
                        onDismiss()
                    }
                )

            } else if ctx.resalePostId == nil || loadFailed {
                // Fallback: allow paying the accepted offer even if post/event failed to load
                QuickOfferPayView(
                    accepted: .init(
                        messageId: ctx.offerMessageId,
                        amount: ctx.amount,
                        currency: ctx.currency
                    ),
                    resalePostId: ctx.resalePostId,
                    onDone: {
                        onSold(ctx.offerMessageId)
                        onDismiss()
                    }
                )

            } else {
                ZStack {
                    LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading offer…").foregroundColor(.white.opacity(0.8))
                        Button("Pay anyway") { loadFailed = true }
                            .padding(.top, 8)
                            .foregroundColor(.gold)
                    }
                }
                .task { await load() }
            }
        }
    }

    private func load() async {
        guard let postId = ctx.resalePostId else {
            loadFailed = true
            return
        }
        do {
            async let p = fetchResalePost(id: postId)
            let post = try await p
            guard let eventId = post.eventId else {
                throw URLError(.badServerResponse)
            }
            async let e = fetchEvent(id: eventId)
            let event = try await e
            await MainActor.run {
                self.post = post
                self.event = event
            }
        } catch {
            await MainActor.run {
                self.loadFailed = true
            }
        }
    }

    private func fetchResalePost(id: Int) async throws -> ResalePostDTO {
        guard
            let token = TokenManager.shared.normalizedAccessToken(),
            let url = URL(string: "https://backendevent-etce.onrender.com/api/resale/\(id)")
        else { throw URLError(.badURL) }

        var r = URLRequest(url: url)
        r.httpMethod = "GET"
        r.timeoutInterval = 10
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: r)
        return try JSONDecoder().decode(ResalePostDTO.self, from: data)
    }

    private func fetchEvent(id: Int) async throws -> Event {
        guard
            let token = TokenManager.shared.normalizedAccessToken(),
            let url = URL(string: "https://backendevent-etce.onrender.com/api/events/\(id)")
        else { throw URLError(.badURL) }

        var r = URLRequest(url: url)
        r.httpMethod = "GET"
        r.timeoutInterval = 10
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: r)
        return try JSONDecoder().decode(Event.self, from: data)
    }
}


