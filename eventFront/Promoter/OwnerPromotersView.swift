import SwiftUI

struct OwnerPromotersView: View {
    let eventId: Int
    @State private var promoters: [PromoterEvent] = []

    var body: some View {
        List {
            ForEach(promoters, id: \.id) { pe in
                VStack(alignment: .leading, spacing: 4) {
                    Text(pe.promoter?.user.fullName ?? "Promoter")
                        .font(.headline)

                    Text("Username: \(pe.promoter?.user.username ?? "-")")
                        .font(.subheadline)
                        .foregroundColor(.gray)

                    Text("Tickets Sold: \(pe.ticketsSold)")
                        .font(.footnote)
                        .foregroundColor(.neonGreen)
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

        var request = URLRequest(url: URL(string: "http://localhost:8080/api/promoters/event/\(eventId)/dashboard")!)
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
