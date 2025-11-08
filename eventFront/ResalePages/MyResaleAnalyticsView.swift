//
//  MyResaleAnalyticsView.swift
//  eventFront
//
//  Created by Ivan Andres Madriz on 1/9/25.
//


// eventFront/Resale/MyResaleAnalyticsView.swift
import SwiftUI

struct MyResaleAnalyticsView: View {
    @State private var rows: [ResaleAnalyticsDTO] = []
    @State private var loading = true
    @AppStorage("selectedLanguage") var lang: String = "en"

    var body: some View {
        List {
            ForEach(rows, id: \.postId) { r in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(r.title ?? "—").font(.headline)
                        if r.sold == true {
                            Text(lang == "es" ? "Vendido" : "Sold").font(.caption2).padding(4).background(Color.green.opacity(0.2)).cornerRadius(6)
                        }
                    }
                    HStack(spacing: 18) {
                        Label("\(r.views ?? 0)", systemImage: "eye")
                        Label("\(r.chatOpens ?? 0)", systemImage: "bubble.left.and.bubble.right")
                        if let secs = r.timeToSellSeconds {
                            Label(formatTTS(secs), systemImage: "hourglass")
                        }
                    }.font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .overlay { if loading { ProgressView().controlSize(.large) } }
        .navigationTitle(lang == "es" ? "Analítica" : "Analytics")
        .onAppear { fetch() }
    }

    func formatTTS(_ s: Int) -> String {
        let h = s / 3600; let m = (s % 3600) / 60
        return "\(h)h \(m)m"
    }

    func fetch() {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/api/resale/my/analytics") else { return }
        var r = URLRequest(url: url)
        r.httpMethod = "GET"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: r) { data, _, _ in
            DispatchQueue.main.async { loading = false }
            guard let data = data else { return }
            if let arr = try? JSONDecoder().decode([ResaleAnalyticsDTO].self, from: data) {
                DispatchQueue.main.async { rows = arr }
            }
        }.resume()
    }
}

struct ResaleAnalyticsDTO: Codable {
    let postId: Int
    let title: String?
    let price: Double?
    let sold: Bool?
    let createdAt: String?
    let soldAt: String?
    let views: Int?
    let chatOpens: Int?
    let timeToSellSeconds: Int?
}
