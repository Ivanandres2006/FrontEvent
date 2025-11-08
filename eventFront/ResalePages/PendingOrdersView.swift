//
//  PendingOrdersView.swift
//  eventFront
//
//  Created by Ivan Andres Madriz on 1/9/25.
//


import SwiftUI

struct PendingOrdersView: View {
    @AppStorage("selectedLanguage") var lang: String = "en"
    let postId: Int?

    @State private var orders: [ResaleOrderDTO] = []
    @State private var loading = true
    @State private var error = ""

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                HStack {
                    Text(lang == "es" ? "Pedidos Pendientes" : "Pending Orders")
                        .font(.largeTitle.bold())
                        .foregroundColor(.white)
                    Spacer()
                }.padding(.top)

                if loading {
                    ProgressView().tint(.white)
                    Spacer()
                } else if !error.isEmpty {
                    Text(error).foregroundColor(.red)
                    Spacer()
                } else if orders.isEmpty {
                    Text(lang == "es" ? "No hay pedidos pendientes." : "No pending orders.")
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                } else {
                    List {
                        ForEach(orders) { o in
                            OrderRow(order: o)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .padding()
        }
        .onAppear { load() }
    }

    func load() {
        guard let token = TokenManager.shared.getAccessToken() else { return }
        var urlStr = "https://backendevent-etce.onrender.com/api/resale/manual/pending"
        if let pid = postId { urlStr += "?postId=\(pid)" }
        guard let url = URL(string: urlStr) else { return }

        loading = true; error = ""
        var r = URLRequest(url: url)
        r.httpMethod = "GET"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: r) { data, resp, _ in
            DispatchQueue.main.async { loading = false }
            guard let http = resp as? HTTPURLResponse else { return }
            if http.statusCode != 200 {
                DispatchQueue.main.async { error = "Server error: \(http.statusCode)" }
                return
            }
            if let data = data, let arr = try? JSONDecoder().decode([ResaleOrderDTO].self, from: data) {
                DispatchQueue.main.async { orders = arr }
            }
        }.resume()
    }

    @ViewBuilder
    func OrderRow(order: ResaleOrderDTO) -> some View {
        NavigationLink {
            OrderReviewView(order: order) { // onConfirm
                // After confirm, refresh list
                load()
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(order.postTitle ?? "")
                        .foregroundColor(.white)
                        .font(.headline)
                    Spacer()
                    Text(String(format: "$%.2f", order.amount))
                        .foregroundColor(.gold)
                        .bold()
                }
                HStack {
                    Text((order.buyerUsername ?? order.buyerName) ?? "")
                        .foregroundColor(.white.opacity(0.85))
                    Spacer()
                    Text((order.method ?? "").uppercased())
                        .font(.caption2.bold())
                        .padding(.vertical, 4).padding(.horizontal, 8)
                        .background(Color.white.opacity(0.1))
                        .foregroundColor(.white)
                        .cornerRadius(6)
                }
                if let ref = order.reference, !ref.isEmpty {
                    Text((lang == "es" ? "Referencia: " : "Reference: ") + ref)
                        .foregroundColor(.white.opacity(0.7))
                        .font(.caption)
                }
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.06), lineWidth: 1))
        }
    }
}
