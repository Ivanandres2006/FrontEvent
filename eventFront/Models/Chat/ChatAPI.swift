//
//  ChatAPI.swift
//  eventFront
//

import Foundation
import UIKit

// MARK: - Helpers

private extension JSONDecoder {
        /// Same as chatISO, exposed as a cached/ready-to-use decoder for lists/wrappers.
    static let wkndFlexible: JSONDecoder = {
        // You already defined `chatISO`; reuse it so the date strategy stays in sync.
        return JSONDecoder.chatISO
    }()
    /// Accepts: "yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssZ",
    ///          "yyyy-MM-dd'T'HH:mm:ss.SSS",   "yyyy-MM-dd'T'HH:mm:ss"
    static var chatISO: JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)

            // Try ISO8601 with fraction first
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: s) { return d }
            // Then ISO8601 without fraction
            iso.formatOptions = [.withInternetDateTime]
            if let d = iso.date(from: s) { return d }

            // Fallback plain formatters (no timezone provided by BE LocalDateTime)
            let fmts = [
                "yyyy-MM-dd'T'HH:mm:ss.SSS",
                "yyyy-MM-dd'T'HH:mm:ss"
            ]
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(secondsFromGMT: 0)
            for fmt in fmts {
                f.dateFormat = fmt
                if let d = f.date(from: s) { return d }
            }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Bad date \(s)")
        }
        return dec
    }
}

private extension Data {
    mutating func appendString(_ s: String) { append(Data(s.utf8)) }
}

// MARK: - ChatAPI

final class ChatAPI {
    static let shared = ChatAPI()
    private init() {}

    // BE base URLs
    private let baseHTTP = URL(string: "https://backendevent-etce.onrender.com/api/chat")!
    private let wsURL    = URL(string: "wss://backendevent-etce.onrender.com/ws")!

    private var tokenProvider: (() -> String?)?
    func setTokenProvider(_ provider: @escaping () -> String?) { tokenProvider = provider }

    // Exposed for your external StompClient if needed
    var baseURL: URL { URL(string: "https://backendevent-etce.onrender.com")! }
    
    private var tokenRefresher: (() async -> Void)?
    func setTokenRefresher(_ refresher: @escaping () async -> Void) {
        tokenRefresher = refresher
    }

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.waitsForConnectivity = true
        cfg.timeoutIntervalForRequest  = 120   // each request
        cfg.timeoutIntervalForResource = 600   // whole transfer (big uploads)
        cfg.allowsConstrainedNetworkAccess = true
        cfg.allowsExpensiveNetworkAccess  = true
        return URLSession(configuration: cfg)
    }()

    // MARK: REST core

    private func makeRequest(
        _ path: String,
        method: String = "GET",
        query: [URLQueryItem]? = nil,
        body: Data? = nil,
        contentType: String? = nil
    ) -> URLRequest {
        var comps = URLComponents(url: baseHTTP.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        comps.queryItems = query
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method

        if var t = tokenProvider?(), !t.isEmpty {
            // Normalize token so we never send "Bearer Bearer ..."
            if t.lowercased().hasPrefix("bearer ") {
                t = String(t.dropFirst("bearer ".count)).trimmingCharacters(in: .whitespaces)
            }
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }

        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let contentType { req.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        req.httpBody = body
        return req
    }
    
    /// Send a request. If we get 401 once, run tokenRefresher (if set) and retry once.
    // ✅ REPLACE your current sendWithAuthRetry with this
    private func sendWithAuthRetry(build: @escaping () -> URLRequest) async throws -> (Data, URLResponse) {
        let transient: Set<URLError.Code> = [
            .timedOut, .cannotFindHost, .cannotConnectToHost,
            .networkConnectionLost, .dnsLookupFailed, .notConnectedToInternet
        ]

        var lastError: Error?
        for attempt in 0..<3 { // try up to 3 times
            var req = build()
            #if DEBUG
            let hasAuth = req.value(forHTTPHeaderField: "Authorization") != nil
            print("➡️ \(req.httpMethod ?? "GET") \(req.url?.absoluteString ?? "")  auth:\(hasAuth ? "yes" : "no")  attempt:\(attempt+1)")
            #endif
            do {
                var (data, resp) = try await session.data(for: req)

                if let http = resp as? HTTPURLResponse, http.statusCode == 401, let refresh = tokenRefresher {
                    #if DEBUG
                    print("🔁 401 → refreshing token")
                    #endif
                    await refresh()
                    req = build()
                    (data, resp) = try await session.data(for: req)
                }
                return (data, resp)
            } catch {
                lastError = error
                if let u = error as? URLError, transient.contains(u.code), attempt < 2 {
                    let delay = 0.6 * pow(2, Double(attempt)) // ~0.6s then 1.2s
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                break
            }
        }
        throw lastError ?? ChatErr.badResponse
    }

    
    // MARK: - Unread count

    func fetchUnreadCount(completion: @escaping (Int) -> Void) {
        let req = makeRequest("unread-count")
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            guard let data,
                  let resp = resp as? HTTPURLResponse,
                  (200...299).contains(resp.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String:Any],
                  let total = json["total"] as? Int else {
                completion(0)
                return
            }
            completion(total)
        }.resume()
    }


    private func ensureOK(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { throw ChatErr.badResponse }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 { throw ChatErr.notAuthorized }
            var msg: String? = nil
            if let j = try? JSONSerialization.jsonObject(with: data) as? [String:Any] {
                msg = (j["message"] as? String) ?? (j["error"] as? String)
            } else if let s = String(data: data, encoding: .utf8), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                msg = s
            }
            throw ChatErr.server(http.statusCode, msg)
        }
    }

    enum ChatErr: Error { case badResponse, server(Int, String?), notAuthorized, badPayload }

    // MARK: Rooms

    func myRooms() async throws -> [ChatRoomSummaryDTO] {
        let (data, resp) = try await sendWithAuthRetry {
            self.makeRequest("rooms/my", method: "GET")   // <-- matches backend
        }
        try ensureOK(resp, data)

        let dec = JSONDecoder.wkndFlexible
        // Try plain array first
        if let arr = try? dec.decode([ChatRoomSummaryDTO].self, from: data) { return arr }

        // Then try common wrappers
        struct Wrapper: Decodable {
            let rooms: [ChatRoomSummaryDTO]?
            let data:  [ChatRoomSummaryDTO]?
            let result:[ChatRoomSummaryDTO]?
        }
        let w = try dec.decode(Wrapper.self, from: data)
        if let a = w.rooms ?? w.data ?? w.result { return a }
        throw APIError.decoding
    }


    func startDirect(eventId: Int, otherUserId: Int) async throws -> Int {
        let req = makeRequest(
            "start-direct", method: "POST",
            query: [
                .init(name: "eventId", value: String(eventId)),
                .init(name: "otherUserId", value: String(otherUserId))
            ]
        )
        let (data, resp) = try await session.data(for: req)
        try ensureOK(resp, data)
        return try parseId(from: data)
    }

    func startResale(resalePostId: Int, sellerId: Int) async throws -> Int {
        let req = makeRequest(
            "start-resale", method: "POST",
            query: [
                .init(name: "resalePostId", value: String(resalePostId)),
                .init(name: "sellerId", value: String(sellerId))
            ]
        )
        let (data, resp) = try await session.data(for: req)
        try ensureOK(resp, data)
        return try parseId(from: data)
    }
    
    @discardableResult
    func promoterGroup(eventId: Int, promoterUserIds: [Int]) async throws -> Int {
        // BE expects a raw JSON array body
        let body = try JSONSerialization.data(withJSONObject: promoterUserIds, options: [])

        let (data, resp) = try await sendWithAuthRetry {
            self.makeRequest(
                "promoter-group",
                method: "POST",
                query: [URLQueryItem(name: "eventId", value: String(eventId))],
                body: body,
                contentType: "application/json"
            )
        }
        try ensureOK(resp, data)
        return try parseIdOrRoomId(from: data)  // <-- updated helper below
    }

    private func parseIdOrRoomId(from data: Data) throws -> Int {
        if let n = try? JSONDecoder().decode(Int.self, from: data) { return n }
        struct R: Decodable { let id: Int?; let roomId: Int? }
        let r = try JSONDecoder().decode(R.self, from: data)
        if let id = r.id ?? r.roomId { return id }
        throw APIError.decoding
    }


    // MARK: Messages

    func getMessages(roomId: Int, limit: Int = 50, beforeId: Int? = nil) async throws -> [ChatMessageDTO] {
        var q = [URLQueryItem(name: "limit", value: String(limit))]
        if let b = beforeId { q.append(.init(name: "beforeId", value: String(b))) }
        let req = makeRequest("rooms/\(roomId)/messages", query: q)
        let (data, resp) = try await session.data(for: req)
        try ensureOK(resp, data)
        return try JSONDecoder.chatISO.decode([ChatMessageDTO].self, from: data)
    }

    @discardableResult
    func sendText(roomId: Int, text: String) async throws -> Int {
        let req = makeRequest(
            "rooms/\(roomId)/messages/text",
            method: "POST",
            query: [ .init(name: "text", value: text) ]
        )
        let (data, resp) = try await session.data(for: req)
        try ensureOK(resp, data)
        return try parseId(from: data)
    }

    // ✅ REPLACE the entire sendImage(...) with this version
    @discardableResult
    func sendImage(roomId: Int, imageData: Data, caption: String?) async throws -> Int {
        // Normalize to JPEG if HEIC/unknown, and compress a bit to avoid drops.
        var payload = imageData
        var (mime, filename) = imageMimeAndFilename(for: payload)
        if mime == "image/heic" || mime == "application/octet-stream" {
            if let ui = UIImage(data: payload), let jpg = ui.jpegData(compressionQuality: 0.82) {
                payload = jpg
                mime = "image/jpeg"
                filename = "image.jpg"
            }
        }
        

        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        func part(_ name: String, _ value: String) {
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.appendString("\(value)\r\n")
        }
        if let c = caption, !c.isEmpty { part("caption", c) }

        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        body.appendString("Content-Type: \(mime)\r\n\r\n")
        body.append(payload)
        body.appendString("\r\n--\(boundary)--\r\n")

        // ChatAPI.sendImage request builder:
        let (data, resp) = try await sendWithAuthRetry {
            var r = self.makeRequest(
                "rooms/\(roomId)/messages/image",
                method: "POST",
                body: body,
                contentType: "multipart/form-data; boundary=\(boundary)"
            )
            r.timeoutInterval = 120
            r.setValue("close", forHTTPHeaderField: "Connection")    // avoid flaky keep-alive
            r.setValue("100-continue", forHTTPHeaderField: "Expect") // preflight before body
            print("📤 payload=\(payload.count/1024)KB body=\(body.count/1024)KB mime=\(mime)")
            return r
        }
        try ensureOK(resp, data)
        return try parseId(from: data)
    }


    func markRead(roomId: Int) async throws {
        let req = makeRequest("rooms/\(roomId)/read", method: "POST")
        let (_, resp) = try await session.data(for: req)
        try ensureOK(resp, Data())
    }

    // Settings screen helpers (if you use them)
    func updateRoom(roomId: Int, name: String?, iconUrl: String?) async throws {
        struct Body: Codable { let name: String?; let iconUrl: String? }
        let body = try JSONEncoder().encode(Body(name: name, iconUrl: iconUrl))
        let (data, resp) = try await sendWithAuthRetry {
            self.makeRequest("rooms/\(roomId)", method: "PUT", body: body, contentType: "application/json")
        }
        try ensureOK(resp, data)
    }


    func uploadRoomIcon(roomId: Int, imageData: Data, fileName: String = "icon.jpg") async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        body.appendString("Content-Type: image/jpeg\r\n\r\n")
        body.append(imageData)
        body.appendString("\r\n--\(boundary)--\r\n")

        let req = makeRequest("rooms/\(roomId)/icon", method: "POST", body: body,
                              contentType: "multipart/form-data; boundary=\(boundary)")
        let (data, resp) = try await session.data(for: req)
        try ensureOK(resp, data)
        // Expecting { "url": "https://..." }
        let map = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let url = (map?["url"] as? String) else { throw ChatErr.badPayload }
        return url
    }

    // MARK: STOMP subscribe (realtime, /topic/chat/{roomId})

    func subscribe(roomId: Int, onMessage: @escaping (ChatMessageDTO) -> Void) -> StompSession {
        let session = StompSession(
            url: wsURL,
            token: tokenProvider?(),
            destination: "/topic/chat/\(roomId)",
            onJSON: { data in
                let dec = JSONDecoder.chatISO
                if let msg = try? dec.decode(ChatMessageDTO.self, from: data) {
                    onMessage(msg)
                }
            }
        )
        session.connectAndSubscribe()
        return session
    }
    
    @discardableResult
    func sendOffer(roomId: Int, amount: Double, currency: String = "USD", parentId: Int? = nil) async throws -> Int {
        struct Body: Encodable { let amount: Double; let currency: String; let parentId: Int? }
        let b = try JSONEncoder().encode(Body(amount: amount, currency: currency, parentId: parentId))
        let (data, resp) = try await sendWithAuthRetry {
            self.makeRequest("rooms/\(roomId)/offer", method: "POST", body: b, contentType: "application/json")
        }
        try ensureOK(resp, data)
        // returns { messageId: N }
        let map = (try? JSONSerialization.jsonObject(with: data) as? [String:Any]) ?? [:]
        if let n = map["messageId"] as? Int { return n }
        if let n = map["messageId"] as? NSNumber { return n.intValue }
        return try parseId(from: data)
    }

    func acceptOffer(roomId: Int, messageId: Int) async throws {
        let (data, resp) = try await sendWithAuthRetry {
            self.makeRequest("rooms/\(roomId)/offer/\(messageId)/accept", method: "PATCH")
        }
        try ensureOK(resp, data)
    }

    func declineOffer(roomId: Int, messageId: Int) async throws {
        let (data, resp) = try await sendWithAuthRetry {
            self.makeRequest("rooms/\(roomId)/offer/\(messageId)/decline", method: "PATCH")
        }
        try ensureOK(resp, data)
    }

    // MARK: utils

    private func parseId(from data: Data) throws -> Int {
        if let map = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let n = map["roomId"] as? NSNumber { return n.intValue }
            if let n = map["id"] as? NSNumber     { return n.intValue }
            if let n = map["messageId"] as? NSNumber { return n.intValue }
            if let v = map["roomId"] as? Int { return v }
            if let v = map["id"] as? Int     { return v }
            if let v = map["messageId"] as? Int { return v }
        }
        let trimmed = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if let n = Int(trimmed) { return n }
        throw ChatErr.badPayload
    }

    private func imageMimeAndFilename(for data: Data) -> (mime: String, filename: String) {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return ("image/png", "image.png") }    // PNG
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return ("image/jpeg", "image.jpg") }        // JPEG
        if data.starts(with: Array("GIF8".utf8)) { return ("image/gif", "image.gif") }         // GIF
        if let s = String(data: data.prefix(12), encoding: .ascii), s.contains("ftyp") {
            return ("image/heic", "image.heic")                                                // HEIC guess
        }
        return ("application/octet-stream", "upload.bin")
    }
}

// MARK: - Minimal STOMP client

final class StompSession {
    private let url: URL
    private let token: String?
    private let destination: String
    private let onJSON: (Data) -> Void

    private var task: URLSessionWebSocketTask?
    private var pingTimer: Timer?
    private var subId = "sub-\(Int.random(in: 1000...9999))"

    init(url: URL, token: String?, destination: String, onJSON: @escaping (Data) -> Void) {
        self.url = url
        self.token = token
        self.destination = destination
        self.onJSON = onJSON
    }

    func connectAndSubscribe() {
        var req = URLRequest(url: url)
        // Ask Spring for STOMP subprotocol
        req.addValue("v12.stomp, v11.stomp, v10.stomp", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        if let token { req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        let session = URLSession(configuration: .default)
        task = session.webSocketTask(with: req)
        task?.resume()

        // 1) CONNECT
        let connectFrame = [
            "CONNECT",
            "accept-version:1.2",
            "heart-beat:10000,10000",
            "", "" // blank line + \0
        ].joined(separator: "\n") + "\0"

        task?.send(.string(connectFrame)) { _ in
            // 2) SUBSCRIBE
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self else { return }
                let frame = [
                    "SUBSCRIBE",
                    "id:\(self.subId)",
                    "destination:\(self.destination)",
                    "", ""
                ].joined(separator: "\n") + "\0"
                self.task?.send(.string(frame)) { _ in }
                self.startReceiveLoop()
                self.startPings()
            }
        }
    }

    private func startReceiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let msg):
                switch msg {
                case .string(let s): self.handleFrame(s)
                case .data(let d): if let s = String(data: d, encoding: .utf8) { self.handleFrame(s) }
                @unknown default: break
                }
            case .failure:
                break
            }
            self.startReceiveLoop()
        }
    }

    private func handleFrame(_ s: String) {
        guard s.contains("MESSAGE\n"), let range = s.range(of: "\n\n") else { return }
        let bodyWithNull = String(s[range.upperBound...])
        let body = bodyWithNull.hasSuffix("\0") ? String(bodyWithNull.dropLast()) : bodyWithNull
        if let data = body.data(using: .utf8) { onJSON(data) }
    }

    private func startPings() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.task?.sendPing { _ in }
        }
    }

    func disconnect() {
        pingTimer?.invalidate()
        pingTimer = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }

    deinit { disconnect() }
}
