import SwiftUI

struct OwnerPromotersView: View {
    @AppStorage("selectedLanguage") var lang: String = "en"
    let eventId: Int
    @State private var promoters: [PromoterEvent] = []

    var body: some View {
        List {
            ForEach(promoters, id: \.id) { pe in
                VStack(alignment: .leading, spacing: 4) {
                    Text(pe.promoter?.user.fullName ?? (lang == "es" ? "Promotor" : "Promoter"))
                        .font(.headline)


                    Text(
                        lang == "es"
                            ? "Usuario: \(pe.promoter?.user.username ?? "-")"
                            : "Username: \(pe.promoter?.user.username ?? "-")"
                    )
                    .font(.subheadline)
                        .foregroundColor(.gray)


                    Text(
                        lang == "es"
                            ? "Entradas Vendidas: \(pe.ticketsSold)"
                            : "Tickets Sold: \(pe.ticketsSold)"
                    )
                    .font(.footnote)
                        .foregroundColor(.gold)
                }
                .padding(.vertical, 6)
            }
        }
        .navigationTitle("Promoters")
        .onAppear {
            fetchPromoters()
        }
    }

    func fetchPromoters() {
        guard let token = TokenManager.shared.getAccessToken() else { return }

        var request = URLRequest(url: URL(string: "https://backendevent-etce.onrender.com/api/promoters/event/\(eventId)/dashboard")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let decoded = try? JSONDecoder().decode([PromoterEvent].self, from: data) else { return }

            DispatchQueue.main.async {
                self.promoters = decoded
            }
        }.resume()
    }
}
