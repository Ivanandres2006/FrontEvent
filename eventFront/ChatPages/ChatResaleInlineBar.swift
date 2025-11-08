//
//  ChatResaleInlineBar.swift
//  eventFront
//
//  Created by Ivan Andres Madriz on 1/9/25.
//


import SwiftUI

struct ChatResaleInlineBar: View {
    @AppStorage("selectedLanguage") var lang: String = "en"
    @EnvironmentObject var userSession: UserSession

    let resalePostId: Int
    let isSeller: Bool
    var onAction: () -> Void = {}

    @State private var pendingOrders: [ResaleOrderDTO] = []
    @State private var loading = false
    @State private var showConfirmSheet = false
    @State private var chosenOrder: ResaleOrderDTO? = nil
    @State private var showCancelSheet = false
    @State private var cancelReason = ""
    @State private var error = ""

    var body: some View {
        VStack(spacing: 10) {
            if isSeller, !pendingOrders.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "ticket.fill")
                        .foregroundColor(.black)
                        .padding(6)
                        .background(Color.gold)
                        .clipShape(Circle())

                    Text(lang == "es" ? "Pedido manual pendiente" : "Pending manual order")
                        .foregroundColor(.white)
                        .font(.subheadline.bold())
                    Spacer()
                    Button {
                        chosenOrder = pendingOrders.first
                        showConfirmSheet = true
                    } label: {
                        Text(lang == "es" ? "Confirmar" : "Confirm")
                            .font(.caption.bold())
                            .padding(.vertical, 6).padding(.horizontal, 10)
                            .background(Color.gold)
                            .foregroundColor(.black)
                            .cornerRadius(8)
                    }
                    Button {
                        chosenOrder = pendingOrders.first
                        showCancelSheet = true
                    } label: {
                        Text(lang == "es" ? "Cancelar" : "Cancel")
                            .font(.caption.bold())
                            .padding(.vertical, 6).padding(.horizontal, 10)
                            .background(Color.white.opacity(0.12))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.06), lineWidth: 1))
            }
        }
        .onAppear { loadPending() }
        .sheet(isPresented: $showConfirmSheet) {
            if let ord = chosenOrder {
                InlineConfirmSheet(orderId: ord.id, onDone: {
                    showConfirmSheet = false
                    onAction()
                    loadPending()
                })
            }
        }
        .sheet(isPresented: $showCancelSheet) {
            VStack(spacing: 14) {
                Text(lang == "es" ? "Cancelar pedido" : "Cancel order")
                    .font(.headline)
                TextField(lang == "es" ? "Motivo (opcional)" : "Reason (optional)", text: $cancelReason)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                HStack {
                    Button(lang == "es" ? "Cerrar" : "Close") { showCancelSheet = false }
                    Spacer()
                    Button(lang == "es" ? "Cancelar Pedido" : "Cancel Order") {
                        cancel()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                if !error.isEmpty {
                    Text(error).foregroundColor(.red)
                }
            }
            .presentationDetents([.height(240)])
        }
    }

    func loadPending() {
        guard isSeller,
              let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/api/resale/manual/pending?postId=\(resalePostId)")
        else { return }
        loading = true
        var r = URLRequest(url: url)
        r.httpMethod = "GET"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: r) { data, _, _ in
            DispatchQueue.main.async { loading = false }
            guard let data = data else { return }
            if let arr = try? JSONDecoder().decode([ResaleOrderDTO].self, from: data) {
                DispatchQueue.main.async { pendingOrders = arr }
            }
        }.resume()
    }

    func cancel() {
        guard let ord = chosenOrder,
              let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/api/resale/manual/cancel/\(ord.id)")
        else { return }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["reason": cancelReason])
        URLSession.shared.dataTask(with: r) { data, resp, _ in
            guard let http = resp as? HTTPURLResponse else { return }
            if http.statusCode != 200 {
                DispatchQueue.main.async { error = "Server error: \(http.statusCode)" }
                return
            }
            DispatchQueue.main.async {
                showCancelSheet = false
                onAction()
                loadPending()
            }
        }.resume()
    }
}

private struct InlineConfirmSheet: View {
    @AppStorage("selectedLanguage") var lang: String = "en"
    let orderId: Int
    var onDone: () -> Void

    @State private var loading = false
    @State private var error = ""

    var body: some View {
        VStack(spacing: 12) {
            Text(lang == "es" ? "Confirmar y Transferir" : "Confirm & Transfer")
                .font(.headline)
            Text(lang == "es"
                 ? "Esto transferirá la entrada al comprador y marcará la publicación como vendida."
                 : "This will transfer the ticket to the buyer and mark the listing as sold.")
                .multilineTextAlignment(.center)
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            if !error.isEmpty { Text(error).foregroundColor(.red) }

            HStack {
                Button(lang == "es" ? "Cerrar" : "Close") { onDone() }
                Spacer()
                Button {
                    confirm()
                } label: {
                    if loading { ProgressView() } else { Text(lang == "es" ? "Confirmar" : "Confirm") }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
        }
        .presentationDetents([.height(220)])
    }

    func confirm() {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/api/resale/manual/confirm/\(orderId)")
        else { return }
        loading = true; error = ""
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: r) { data, resp, _ in
            DispatchQueue.main.async { loading = false }
            guard let http = resp as? HTTPURLResponse else { return }
            if http.statusCode != 200 {
                DispatchQueue.main.async { error = "Server error: \(http.statusCode)" }
                return
            }
            DispatchQueue.main.async { onDone() }
        }.resume()
    }
}
