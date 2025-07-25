import SwiftUI

struct PromoterAnalyticsView: View {
    @AppStorage("selectedLanguage") var lang: String = "en"
    let eventId: Int
    @Environment(\.dismiss) var dismiss

    @State private var promoterEvent: PromoterEvent?
    @State private var buyers: [ReferredBuyerDTO] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [.black, .deepNavy], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()

                VStack {
                    HStack {
                        Button(lang == "es" ? "Cerrar" : "Close") {
                            dismiss()
                        }
                        .foregroundColor(.neonGreen)
                        .padding(.leading)

                        Spacer()
                    }
                    .padding(.top, 12)

                    if isLoading {
                        Spacer()
                        ProgressView(lang == "es" ? "Cargando estadísticas..." : "Loading stats...")
                            .tint(.neonGreen)
                            .padding()
                        Spacer()
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 28) {
                                if let p = promoterEvent {
                                    // Stats Card
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(lang == "es" ? "🎯 Tus Estadísticas como Promotor" : "🎯 Your Promoter Stats")
                                            .font(.title.bold())
                                            .foregroundColor(.white)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(lang == "es" ? "Usuario" : "Username")
                                                .font(.caption)
                                                .foregroundColor(.gray)

                                            Text(p.promoter?.user.username ?? "-")
                                                .font(.title2.monospacedDigit())
                                                .foregroundColor(.neonGreen)
                                            
                                            
                                            
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(lang == "es" ? "Enlace de Referencia" : "Referral Link")
                                                .font(.caption)
                                                .foregroundColor(.gray)

                                            let username = p.promoter?.user.username ?? "-"
                                            let referralURL = "http://localhost:3000/events/\(eventId)?ref=\(username)"

                                            Text(referralURL)
                                                .font(.caption2)
                                                .foregroundColor(.blue)
                                                .lineLimit(1)
                                                .truncationMode(.middle)

                                            Button(action: {
                                                UIPasteboard.general.string = referralURL
                                            }) {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "doc.on.doc")
                                                    Text(lang == "es" ? "Copiar Enlace" : "Copy Link")
                                                }
                                                .font(.footnote)
                                                .foregroundColor(.neonGreen)
                                            }
                                        }

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(lang == "es" ? "Entradas Vendidas" : "Tickets Sold")
                                                .font(.caption)
                                                .foregroundColor(.gray)

                                            Text("\(p.ticketsSold)")
                                                .font(.title2.bold())
                                                .foregroundColor(.neonGreen)
                                        }
                                    }
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 18)
                                            .fill(Color.white.opacity(0.05))
                                            .shadow(color: .neonGreen.opacity(0.2), radius: 12, x: 0, y: 6)
                                    )

                                    // Buyers
                                    if buyers.isEmpty {
                                        Text(lang == "es" ? "Aún no hay compradores referidos." : "No referred buyers yet.")
                                            .foregroundColor(.gray)
                                            .padding(.top, 12)
                                            .frame(maxWidth: .infinity, alignment: .center)
                                    } else {
                                        Text(lang == "es" ? "🧾 Compradores Referidos" : "🧾 Referred Buyers")
                                            .font(.headline)
                                            .foregroundColor(.white)

                                        ForEach(buyers) { buyer in
                                            VStack(alignment: .leading, spacing: 6) {
                                                HStack {
                                                    Text(buyer.username)
                                                        .font(.subheadline.bold())
                                                        .foregroundColor(.white)
                                                    Spacer()
                                                    Text(formatTimestamp(buyer.timestamp))
                                                        .font(.caption2)
                                                        .foregroundColor(.gray)
                                                }

                                                Text(buyer.email)
                                                    .font(.footnote)
                                                    .foregroundColor(.gray)
                                            }
                                            .padding()
                                            .background(Color.white.opacity(0.04))
                                            .cornerRadius(12)
                                            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                                        }
                                    }

                                } else {
                                    Text(lang == "es" ? "No hay estadísticas disponibles." : "No stats available.")
                                        .foregroundColor(.gray)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .onAppear {
                fetchStats()
            }
        }
    }

    func fetchStats() {
        guard let token = TokenManager.shared.getAccessToken() else { return }

        let url = URL(string: "https://backendevent-etce.onrender.com/api/promoters/my-stats")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data else { return }

            do {
                let allStats = try JSONDecoder().decode([PromoterEvent].self, from: data)
                if let match = allStats.first(where: { $0.event?.id == eventId }) {
                    DispatchQueue.main.async {
                        self.promoterEvent = match
                        fetchBuyers(promoterId: match.promoter?.id ?? -1)
                    }
                }
            } catch {
                print("Decode failed: \(error)")
                isLoading = false
            }
        }.resume()
    }

    func fetchBuyers(promoterId: Int) {
        guard let token = TokenManager.shared.getAccessToken() else { return }

        let url = URL(string: "https://backendevent-etce.onrender.com/api/promoters/event/\(eventId)/promoter/\(promoterId)/buyers")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data else { return }

            do {
                let decoded = try JSONDecoder().decode([ReferredBuyerDTO].self, from: data)
                DispatchQueue.main.async {
                    self.buyers = decoded
                    self.isLoading = false
                }
            } catch {
                print("Decode buyers failed: \(error)")
                isLoading = false
            }
        }.resume()
    }

    func formatTimestamp(_ timestamp: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: timestamp) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        return timestamp
    }
}
