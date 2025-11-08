import SwiftUI
import UIKit

// MARK: - Lightweight models / helpers used here

struct CounterOffer: Identifiable { let id = UUID(); var amount: Double }
struct UploadResponse: Codable { let filename: String }

extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) { append(data) }
    }
}

// MARK: - ChatView

struct ChatView: View {
    @AppStorage("selectedLanguage") var lang: String = "en"
    let chatSummary: ChatRoomSummary
    let currentUserId: Int

    @State private var chatRoomId: Int? = nil
    @State private var messages: [ChatMessage] = []
    @State private var newMessage = ""
    @State private var showCustomActionSheet = false
    @State private var showImagePicker = false
    @State private var useCamera = false
    @State private var showCounterOfferPrompt = false
    @State private var counterOfferText = ""
    @State private var selectedImageURL: IdentifiableURL? = nil
    @State private var activeAcceptedOffer: AcceptedOffer? = nil

    @State private var loadedEvent: Event? = nil
    @EnvironmentObject var userSession: UserSession

    @State private var paymentComplete = false
    @State private var resalePostSold = false
    @State private var fullResalePost: ResalePostDTO? = nil
    @State private var renderTrigger = UUID()
    @State private var isSendingCounterOffer = false

    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            messagesScrollView
            if showCustomActionSheet { actionSheet }

            Group {
                if loadedEvent != nil || chatSummary.type == "DIRECT" || chatSummary.type == "PROMOTER_GROUP" {
                    if isEventInPast {
                        if chatSummary.type != "DIRECT" && chatSummary.type != "PROMOTER_GROUP" {
                            pastEventNotice
                        } else {
                            messageInputBar
                        }
                    } else {
                        messageInputBar
                    }
                }
            }
        }
        .background(LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .onAppear {
            chatRoomId = chatSummary.chatRoomId
            fetchMessages()

            if let resalePostId = chatSummary.resalePostId {
                // 🔧 FIX: use local helper implemented below
                fetchPostById(postId: resalePostId) { post in
                    if let post = post {
                        self.fullResalePost = post
                        self.paymentComplete = post.sold
                        if let eventId = post.eventId { self.fetchEventDetails(eventId: eventId) }
                    }
                }
            } else {
                self.paymentComplete = true
                if let eventId = chatSummary.eventId {
                    self.fetchEventDetails(eventId: Int(eventId))
                } else {
                    self.loadedEvent = Event(id: -1, title: "Direct Chat") // dummy to show input bar
                }
            }

            // refresh every 5s
            Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in fetchMessages() }
        }
        .sheet(item: $selectedImageURL) { viewer in fullScreenImage(url: viewer.url) }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(sourceType: useCamera ? .camera : .photoLibrary) { image in
                if let image = image { uploadImage(image) }
            }
        }
        .sheet(item: $activeAcceptedOffer) { offer in
            if let event = loadedEvent, let post = fullResalePost {
                BuyNowView(
                    resalePost: post,
                    event: .constant(event),
                    userEmail: userSession.email,
                    onComplete: {
                        // 🔧 FIX: use local helper implemented below
                        fetchPostById(postId: offer.resalePostId) { latest in
                            if let latest = latest {
                                self.fullResalePost = latest
                                self.paymentComplete = latest.sold
                                self.renderTrigger = UUID()
                            }
                        }
                    }
                )
            } else {
                Text(lang == "es" ? "Cargando..." : "Loading...")
            }
        }
        
        .alert(lang == "es" ? "Enviar Contraoferta" : "Send Counteroffer", isPresented: $showCounterOfferPrompt) {
            let hasPending = messages.contains { $0.senderId == currentUserId && $0.offerId != nil && $0.status == "PENDING" }
            if !hasPending {
                TextField(lang == "es" ? "Tu precio (ej. 15)" : "Your price (e.g. 15)", text: $counterOfferText)
                Button(lang == "es" ? "Enviar" : "Send") { sendCounterOffer() }
                .disabled(isSendingCounterOffer)
            } else {
                Button("OK", role: .cancel) { }
            }
        } message: {
            let hasPending = messages.contains { $0.senderId == currentUserId && $0.offerId != nil && $0.status == "PENDING" }
            Text(
                hasPending
                ? (lang == "es" ? "Ya enviaste una contraoferta. Espera a que sea aceptada o rechazada."
                                 : "You already sent a counteroffer. Please wait.")
                : (lang == "es" ? "Propón un nuevo precio al vendedor." : "Propose a new price to the seller.")
            )
        }
    }

    // MARK: Header

    var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(chatSummary.title)
                    .font(.title3.bold())
                    .foregroundColor(.white)

                Text(getSubtitleText())
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
            Spacer()
        }
        .padding(.top, 60)
        .padding(.horizontal)
        .padding(.bottom, 12)
        .background(Color.black.opacity(0.7))
    }

    // MARK: Messages

    var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(messages) { msg in messageView(msg) }
                }
                .padding(.top, 10)
            }
            .onChange(of: messages.count) { _ in
                withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
            }
        }
    }

    var pastEventNotice: some View {
        Text(
            lang == "es"
            ? "⚠️ Este evento ya ocurrió. Inicia un nuevo chat para un evento futuro."
            : "⚠️ This event has already happened. Start a new chat for a future event."
        )
        .multilineTextAlignment(.center)
        .foregroundColor(.white.opacity(0.7))
        .padding()
        .background(Color.black.opacity(0.3))
        .cornerRadius(12)
        .padding(.horizontal)
        .padding(.bottom, 12)
    }

    func messageView(_ msg: ChatMessage) -> some View {
        HStack {
            if msg.senderId == currentUserId {
                Spacer()
                messageBubble(msg, isCurrentUser: true)
            } else {
                messageBubble(msg, isCurrentUser: false)
                Spacer()
            }
        }
        .padding(.horizontal)
        .id(msg.id)
    }

    func getSubtitleText() -> String {
        if chatSummary.type == "RESALE" {
            return lang == "es"
                ? "Hablando con \(chatSummary.sellerName ?? "usuario")"
                : "Talking with \(chatSummary.sellerName ?? "user")"
        } else if chatSummary.type == "DIRECT" {
            if userSession.role == "ADMIN" {
                return lang == "es"
                    ? "Hablando con \(chatSummary.otherUsername ?? "usuario")"
                    : "Talking with \(chatSummary.otherUsername ?? "user")"
            } else {
                return lang == "es" ? "Hablando con Admin" : "Talking with Admin"
            }
        } else {
            return lang == "es" ? "Chat" : "Chat"
        }
    }

    func isLastPendingOffer(_ msg: ChatMessage) -> Bool {
        guard let id = msg.offerId else { return false }
        return messages.last(where: {
            $0.offerId != nil && $0.status == "PENDING" && $0.senderId == currentUserId
        })?.offerId == id
    }

    // MARK: Bubble

    @ViewBuilder
    func messageBubble(_ msg: ChatMessage, isCurrentUser: Bool) -> some View {
        VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 6) {

            // Image message
            if let imageName = extractImageFilename(msg.content),
               let url = URL(string: "https://backendevent-etce.onrender.com/api/chat/image/\(imageName)") {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty: ProgressView()
                    case .success(let image): imageBubble(image: image, url: url)
                    case .failure: Image(systemName: "photo.fill").foregroundColor(.gray)
                    @unknown default: EmptyView()
                    }
                }

            // Accepted offer
            } else if let offer = parseAcceptedOffer(msg.content) {
                VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 8) {
                    if currentUserId == chatSummary.buyerId {
                        Text(
                            lang == "es"
                            ? "✅ Oferta Aceptada por $\(String(format: "%.2f", offer.price))"
                            : "✅ Offer Accepted for $\(String(format: "%.2f", offer.price))"
                        )
                        .foregroundColor(.white)
                        .font(.subheadline)

                        if paymentComplete {
                            HStack {
                                Image(systemName: "ticket.fill")
                                Text(lang == "es" ? "¡El boleto es tuyo!" : "Ticket is yours!")
                            }
                            .font(.subheadline)
                            .foregroundColor(.green)
                        } else {
                            Button(lang == "es" ? "Comprar Ahora" : "Buy Now") {
                                fetchFullResalePost(postId: offer.resalePostId) { post in
                                    if let post = post {
                                        self.fullResalePost = post
                                        self.activeAcceptedOffer = offer
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.gold)
                            .foregroundColor(.black)
                            .cornerRadius(10)
                        }

                    } else {
                        HStack {
                            Image(systemName: "checkmark.square.fill").foregroundColor(.green)
                            Text(
                                lang == "es"
                                ? "Aceptaste la oferta: $\(String(format: "%.2f", offer.price))"
                                : "You accepted the offer: $\(String(format: "%.2f", offer.price))"
                            )
                        }
                        .font(.subheadline)
                        .foregroundColor(.green)
                    }
                }
                .padding()
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
                .frame(maxWidth: 280, alignment: isCurrentUser ? .trailing : .leading)

            // Counteroffer
            } else if let amount = msg.amount, let offerId = msg.offerId {
                VStack(alignment: .leading, spacing: 8) {
                    // amount card
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "tag.fill").foregroundColor(.gold)
                            Text(
                                lang == "es"
                                ? "Contraoferta: $\(String(format: "%.2f", amount))"
                                : "Counteroffer: $\(String(format: "%.2f", amount))"
                            )
                            .font(.subheadline.bold())
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(isCurrentUser ? Color.neonGreen : Color.white.opacity(0.08))
                        )
                        .foregroundColor(isCurrentUser ? .black : .white)
                    }

                    switch msg.status {
                    case "PENDING":
                        if !isCurrentUser && currentUserId != chatSummary.buyerId {
                            HStack(spacing: 12) {
                                Button(lang == "es" ? "Aceptar" : "Accept") { acceptCounterOffer(offerId: offerId) }
                                    // 🔧 FIX: pass explicit Color.* here (resolves inference error)
                                    .buttonStyleSmall(color: Color.gold, textColor: Color.black)

                                Button(lang == "es" ? "Rechazar" : "Decline") { declineCounterOffer(offerId: offerId) }
                                    .buttonStyleSmall(color: Color.red, textColor: Color.white)
                            }
                        } else if isCurrentUser && isLastPendingOffer(msg) {
                            HStack(spacing: 4) {
                                Image(systemName: "hourglass"); Text(lang == "es" ? "Esperando..." : "Waiting...")
                            }
                            .font(.caption2).foregroundColor(.gray)
                        }

                    case "ACCEPTED":
                        Text(lang == "es" ? "✅ Tu oferta fue aceptada." : "✅ Your offer was accepted.")
                            .font(.caption2).foregroundColor(.green)

                    case "DECLINED":
                        Text(lang == "es" ? "❌ Tu oferta fue rechazada." : "❌ Your offer was declined.")
                            .font(.caption2).foregroundColor(.red)

                    default: EmptyView()
                    }
                }
                .frame(maxWidth: 280, alignment: isCurrentUser ? .trailing : .leading)

            // Plain text
            } else {
                VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                    if chatSummary.title == "Promoter Group Chat", let name = msg.senderName, !isCurrentUser {
                        Text(name).font(.caption2).foregroundColor(.gray).padding(.horizontal, 8)
                    }

                    Text(msg.content)
                        .padding()
                        .background(isCurrentUser ? Color.gold.opacity(0.9) : Color.white.opacity(0.1))
                        .cornerRadius(16)
                        .foregroundColor(isCurrentUser ? .black : .white)
                        .frame(maxWidth: 250, alignment: isCurrentUser ? .trailing : .leading)
                }
            }

            Text(formattedTime(msg.timestamp))
                .font(.caption2)
                .foregroundColor(.gray)
                .padding(isCurrentUser ? .trailing : .leading, 6)
        }
        .id(renderTrigger)
    }

    // MARK: Networking helpers used by this view only

    /// 🔧 FIX: add single-post fetcher used in onAppear and BuyNow completion
    func fetchPostById(postId: Int, completion: @escaping (ResalePostDTO?) -> Void) {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/resale/\(postId)") else {
            completion(nil); return
        }
        var r = URLRequest(url: url)
        r.httpMethod = "GET"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: r) { data, _, _ in
            guard let data = data,
                  let post = try? JSONDecoder().decode(ResalePostDTO.self, from: data) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            DispatchQueue.main.async { completion(post) }
        }.resume()
    }

    /// Existing “list then match” fetch (kept for the BuyNow quick-open path)
    func fetchFullResalePost(postId: Int, completion: @escaping (ResalePostDTO?) -> Void) {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/resale/available") else {
            completion(nil); return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let decoded = try? JSONDecoder().decode([ResalePostDTO].self, from: data) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let match = decoded.first { $0.id == postId }
            DispatchQueue.main.async { completion(match) }
        }.resume()
    }

    func imageBubble(image: Image, url: URL) -> some View {
        image.resizable()
            .scaledToFill()
            .frame(width: 200, height: 160)
            .clipped()
            .cornerRadius(12)
            .onTapGesture { selectedImageURL = IdentifiableURL(url: url) }
    }

    func fetchEventDetails(eventId: Int) {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/events/\(eventId)") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data = data,
               let fetchedEvent = try? JSONDecoder().decode(Event.self, from: data) {
                DispatchQueue.main.async { self.loadedEvent = fetchedEvent }
            }
        }.resume()
    }

    // MARK: Input

    var messageInputBar: some View {
        HStack(spacing: 10) {
            Button { withAnimation { showCustomActionSheet.toggle() } } label: {
                Image(systemName: "plus.circle.fill").font(.title2).foregroundColor(.white)
            }

            TextField(lang == "es" ? "Escribe un mensaje..." : "Type a message...", text: $newMessage)
                .padding(12)
                .background(Color.white.opacity(0.1))
                .foregroundColor(.white)
                .cornerRadius(10)

            Button { sendMessage(content: newMessage) } label: {
                Image(systemName: "paperplane.fill")
                    .foregroundColor(.gold)
                    .padding(10)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(10)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
    }

    // MARK: Actions

    var actionSheet: some View {
        VStack(spacing: 12) {
            HStack {
                actionButton(lang == "es" ? "📷 Tomar Foto" : "📷 Take Photo") {
                    useCamera = true; showImagePicker = true; showCustomActionSheet = false
                }
                actionButton(lang == "es" ? "🖼️ Biblioteca" : "🖼️ Library") {
                    useCamera = false; showImagePicker = true; showCustomActionSheet = false
                }
                if chatSummary.resalePostId != nil {
                    actionButton(lang == "es" ? "💲 Oferta" : "💲 Offer", color: .gold, textColor: .black) {
                        showCounterOfferPrompt = true
                        showCustomActionSheet = false
                    }
                }
            }

            // Admin utility
            if userSession.role == "ADMIN" {
                actionButton("✅ Grant Event Permission", color: .gold, textColor: .black) {
                    if let otherUserId = chatSummary.otherUserId {
                        grantEventPermission(to: otherUserId)
                        if otherUserId != currentUserId {
                            sendMessage(content: "✅ You now have permission to create events.")
                        }
                    }
                    showCustomActionSheet = false
                }
            }

        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color.deepNavy)
        .transition(.move(edge: .bottom))
    }

    var isEventInPast: Bool {
        if chatSummary.type.uppercased() == "DIRECT" || chatSummary.type.uppercased() == "PROMOTER_GROUP" { return false }
        guard let eventDate = loadedEvent?.dateAsDate else { return false }
        return eventDate < Date()
    }

    func actionButton(_ title: String, color: Color = Color.white.opacity(0.08), textColor: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.bold())
                .foregroundColor(textColor)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(color)
                .cornerRadius(10)
        }
    }

    func grantEventPermission(to userId: Int) {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/admin/user/\(userId)/permission?allow=true") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request) { _, _, _ in
            print("✅ Granted permission to user \(userId)")
        }.resume()
    }

    func fullScreenImage(url: URL) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty: ProgressView()
                case .success(let image): image.resizable().scaledToFit()
                case .failure:
                    Text(lang == "es" ? "Error al cargar la imagen" : "Failed to load image").foregroundColor(.white)
                @unknown default: EmptyView()
                }
            }
            VStack {
                HStack {
                    Spacer()
                    Button { selectedImageURL = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                            .padding()
                    }
                }
                Spacer()
            }
        }
    }

    // MARK: Networking

    func sendMessage(content: String) {
        guard !content.trimmingCharacters(in: .whitespaces).isEmpty,
              let chatRoomId = chatRoomId,
              let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/chat/\(chatRoomId)/send") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = MessagePayload(content: content)
        request.httpBody = try? JSONEncoder().encode(payload)

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let decoded = try? JSONDecoder().decode(ChatMessage.self, from: data) else { return }
            DispatchQueue.main.async {
                messages.append(decoded)
                newMessage = ""
            }
        }.resume()
    }

    func uploadImage(_ image: UIImage) {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/api/chat/upload-image") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let filename = "photo_\(UUID().uuidString).jpg"
        let imageData = image.jpegData(compressionQuality: 0.8) ?? Data()

        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: image/jpeg\r\n\r\n")
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n")
        request.httpBody = body

        URLSession.shared.uploadTask(with: request, from: body) { data, _, _ in
            guard let data = data,
                  let response = try? JSONDecoder().decode(UploadResponse.self, from: data) else { return }
            DispatchQueue.main.async {
                sendMessage(content: "[img]\(response.filename)")
            }
        }.resume()
    }

    func sendCounterOffer() {
        guard !isSendingCounterOffer,
              let price = Double(counterOfferText.trimmingCharacters(in: .whitespaces)),
              price > 0,
              let chatRoomId = chatRoomId,
              let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/chat/\(chatRoomId)/counteroffer") else { return }

        isSendingCounterOffer = true
        counterOfferText = ""

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["amount": price])

        URLSession.shared.dataTask(with: request) { _, _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                isSendingCounterOffer = false
                fetchMessages()
            }
        }.resume()
    }

    func acceptCounterOffer(offerId: Int) { sendOfferAction(endpoint: "accept", offerId: offerId) }
    func declineCounterOffer(offerId: Int) { sendOfferAction(endpoint: "decline", offerId: offerId) }

    func sendOfferAction(endpoint: String, offerId: Int) {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/chat/counteroffer/\(offerId)/\(endpoint)") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { _, _, _ in
            fetchMessages()
        }.resume()
    }

    func fetchMessages() {
        guard let chatRoomId = chatRoomId,
              let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/chat/\(chatRoomId)/messages") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data else { return }
            if let decoded = try? JSONDecoder().decode([ChatMessage].self, from: data) {
                DispatchQueue.main.async { self.messages = decoded }
            }
        }.resume()
    }

    // MARK: Utility

    func formattedTime(_ timestamp: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        if let date = formatter.date(from: timestamp) {
            let display = DateFormatter()
            display.dateFormat = "h:mm a"
            return display.string(from: date)
        }
        return "..."
    }

    func extractImageFilename(_ content: String) -> String? {
        guard content.starts(with: "[img]") else { return nil }
        return String(content.dropFirst(5))
    }

    func parseAcceptedOffer(_ content: String) -> AcceptedOffer? {
        guard content.starts(with: "[acceptedOffer]:") else { return nil }
        let parts = content.replacingOccurrences(of: "[acceptedOffer]:", with: "").split(separator: ":")
        guard parts.count == 2,
              let postId = Int(parts[0]),
              let price = Double(parts[1]) else { return nil }
        return AcceptedOffer(resalePostId: postId, price: price)
    }

    struct IdentifiableURL: Identifiable { let id = UUID(); let url: URL }
    struct AcceptedOffer: Identifiable { let id = UUID(); let resalePostId: Int; let price: Double }

    struct ChatMessage: Identifiable, Codable {
        var id: Int
        var senderId: Int
        var content: String
        var timestamp: String
        var offerId: Int?
        var amount: Double?
        var status: String?
        var senderName: String?
    }

    struct MessagePayload: Codable { let content: String }
}

// MARK: - Small button style (🔧 re-added)

extension View {
    func buttonStyleSmall(color: Color, textColor: Color) -> some View {
        self.padding(.horizontal)
            .padding(.vertical, 6)
            .background(color)
            .foregroundColor(textColor)
            .cornerRadius(8)
    }
}
