//
//  StompClient.swift
//  eventFront
//
//  Created by Ivan Andres Madriz on 15/9/25.
//


import Foundation

@MainActor
final class StompClient: ObservableObject {
    private var task: URLSessionWebSocketTask?
    private var url: URL
    private var subscriptions: Set<String> = []
    private var isConnected = false
    private var reconnectDelay: TimeInterval = 1

    var onMessage: ((ChatMessageDTO) -> Void)?

    init(baseURL: URL) {
        var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        comps.scheme = (comps.scheme == "https") ? "wss" : "ws"
        comps.path = "/ws"
        self.url = comps.url!
    }

    func connect() {
        disconnect()
        let session = URLSession(configuration: .default)
        task = session.webSocketTask(with: url)
        task?.resume()
        listen()
        sendFrame(command: "CONNECT",
                  headers: ["accept-version":"1.2","host":"ios"]) { [weak self] in
            guard let self else { return }
            isConnected = true
            reconnectDelay = 1
            for d in subscriptions { subscribe(destination: d) }
        }
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isConnected = false
    }

    private func backoffReconnect() {
        guard task != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + reconnectDelay) { [weak self] in self?.connect() }
        reconnectDelay = min(reconnectDelay * 2, 30)
    }

    func subscribeToRoom(_ roomId: Int) { subscribe(destination: "/topic/chat/\(roomId)") }

    private func subscribe(destination: String) {
        subscriptions.insert(destination)
        guard isConnected else { return }
        let subId = "sub-" + UUID().uuidString
        sendFrame(command: "SUBSCRIBE",
                  headers: ["id": subId, "destination": destination, "ack":"auto"],
                  completion: nil)
    }

    func sendText(roomId: Int, text: String) {
        let body = (try? JSONSerialization.data(withJSONObject: ["text": text])) ?? Data()
        sendFrame(command: "SEND",
                  headers: ["destination":"/app/chat/\(roomId)/send-text","content-type":"application/json"],
                  dataBody: body, completion: nil)
    }

    private func listen() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                isConnected = false
                backoffReconnect()
            case .success(let msg):
                switch msg {
                case .string(let text): handleFrame(text)
                case .data(let data):
                    if let s = String(data: data, encoding: .utf8) { handleFrame(s) }
                @unknown default: break
                }
                listen()
            }
        }
    }

    private func handleFrame(_ raw: String) {
        guard let range = raw.range(of: "\n\n") else { return }
        let body = String(raw[range.upperBound...]).trimmingCharacters(in: .controlCharacters)
        guard raw.starts(with: "MESSAGE") else { return }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        if let data = body.data(using: .utf8),
           let dto = try? dec.decode(ChatMessageDTO.self, from: data) {
            onMessage?(dto)
        }
    }

    private func sendFrame(command: String,
                           headers: [String:String] = [:],
                           dataBody: Data? = nil,
                           completion: (() -> Void)?) {
        var frame = "\(command)\n"
        headers.forEach { frame += "\($0):\($1)\n" }
        frame += "\n"
        var payload = frame.data(using: .utf8)!
        if let dataBody { payload.append(dataBody) }
        payload.append(0) // NULL
        task?.send(.data(payload)) { _ in completion?() }
    }
}
