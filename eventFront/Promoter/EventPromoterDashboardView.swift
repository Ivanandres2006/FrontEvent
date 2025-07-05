import SwiftUI

struct EventPromoterDashboardView: View {
    let event: Event
    @Environment(\.dismiss) var dismiss

    @State private var promoters: [PromoterEvent] = []
    @State private var buyersByPromoter: [Int: [ReferredBuyerDTO]] = [:]
    @State private var expandedPromoterId: Int? = nil

    @State private var userIdInput = ""
    @State private var message = ""
    @State private var isLoading = true
    @State private var copiedMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    // Header
                    HStack {
                        Button("Close") { dismiss() }
                            .foregroundColor(.neonGreen)
                            .font(.headline)

                        Spacer()

                        Text("Promoters")
                            .font(.title2.bold())
                            .foregroundColor(.white)

                        Spacer().frame(width: 64)
                    }
                    .padding(.horizontal)
                    .padding(.top, 16)

                    ScrollView {
                        VStack(spacing: 24) {
                            if isLoading {
                                ProgressView("Loading...")
                                    .tint(.neonGreen)
                                    .padding(.top, 40)
                            } else if promoters.isEmpty {
                                Text("No promoters assigned to this event.")
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                                    .padding(.top, 60)
                            } else {
                                VStack(spacing: 16) {
                                    ForEach(promoters) { pe in
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(pe.promoter?.user.fullName ?? "Promoter")
                                                .font(.headline)
                                                .foregroundColor(.white)

                                            Text("Username: \(pe.promoter?.user.username ?? "-")")
                                                .font(.subheadline)
                                                .foregroundColor(.gray)

                                            Text("Tickets Sold: \(pe.ticketsSold)")
                                                .font(.footnote)
                                                .foregroundColor(.neonGreen)

                                            if let username = pe.promoter?.user.username {
                                                let link = "http://localhost:3000/events/\(event.id)?ref=\(pe.promoter?.user.username ?? "")"

                                                Button {
                                                    UIPasteboard.general.string = link
                                                    copiedMessage = "Link copied!"
                                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                                        copiedMessage = nil
                                                    }
                                                } label: {
                                                    HStack(spacing: 6) {
                                                        Image(systemName: "link")
                                                            .foregroundColor(.neonGreen)
                                                        Text("Copy Referral Link")
                                                            .foregroundColor(.neonGreen)
                                                            .font(.caption)
                                                    }
                                                }

                                                Text(link)
                                                    .font(.caption2)
                                                    .foregroundColor(.gray)
                                                    .lineLimit(1)
                                                    .truncationMode(.middle)
                                            }

                                            if copiedMessage != nil {
                                                Text(copiedMessage!)
                                                    .font(.caption)
                                                    .foregroundColor(.green)
                                            }

                                            Button(action: {
                                                if expandedPromoterId == pe.promoter?.id {
                                                    expandedPromoterId = nil
                                                } else {
                                                    fetchBuyers(for: pe)
                                                }
                                            }) {
                                                Text(expandedPromoterId == pe.promoter?.id ? "Hide Buyers" : "View Buyers")
                                                    .font(.caption)
                                                    .foregroundColor(.neonGreen)
                                            }

                                            if expandedPromoterId == pe.promoter?.id,
                                               let buyers = buyersByPromoter[pe.promoter!.id] {
                                                VStack(alignment: .leading, spacing: 8) {
                                                    ForEach(buyers) { buyer in
                                                        VStack(alignment: .leading, spacing: 2) {
                                                            Text(buyer.username)
                                                                .font(.subheadline.bold())
                                                                .foregroundColor(.white)
                                                            Text(buyer.email)
                                                                .font(.footnote)
                                                                .foregroundColor(.gray)
                                                            Text(formatTimestamp(buyer.timestamp))
                                                                .font(.caption)
                                                                .foregroundColor(.gray)
                                                        }
                                                        .padding(.vertical, 6)
                                                        Divider().background(Color.white.opacity(0.1))
                                                    }
                                                }
                                                .padding(.top, 8)
                                            }
                                        }
                                        .padding()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.white.opacity(0.05))
                                        .cornerRadius(12)
                                    }
                                }
                                .padding(.horizontal)
                            }

                            // Add promoter
                            VStack(spacing: 12) {
                                TextField("Enter Username to Add", text: $userIdInput)
                                    .keyboardType(.numberPad)
                                    .padding()
                                    .background(Color.white.opacity(0.08))
                                    .cornerRadius(10)
                                    .foregroundColor(.white)
                                    .padding(.horizontal)

                                Button("Assign Promoter") {
                                    assignPromoter()
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.neonGreen)
                                .foregroundColor(.black)
                                .cornerRadius(12)
                                .padding(.horizontal)

                                if !message.isEmpty {
                                    Text(message)
                                        .foregroundColor(.white)
                                        .font(.footnote)
                                        .padding(.horizontal)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .padding(.bottom, 40)
                        }
                        .padding(.top)
                    }
                }
            }
            .onAppear {
                fetchPromoters()
            }
        }
    }

    func fetchPromoters() {
        guard let token = TokenManager.shared.getAccessToken() else { return }

        var request = URLRequest(url: URL(string: "http://localhost:8080/api/promoters/event/\(event.id)/dashboard")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data else {
                DispatchQueue.main.async { isLoading = false }
                return
            }

            do {
                let decoded = try JSONDecoder().decode([PromoterEvent].self, from: data)
                DispatchQueue.main.async {
                    self.promoters = decoded
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.promoters = []
                }
            }
        }.resume()
    }

    func fetchBuyers(for promoter: PromoterEvent) {
        guard let promoterId = promoter.promoter?.id else { return }
        guard let token = TokenManager.shared.getAccessToken() else { return }

        let url = URL(string: "http://localhost:8080/api/promoters/event/\(event.id)/promoter/\(promoterId)/buyers")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data else { return }

            do {
                let decoded = try JSONDecoder().decode([ReferredBuyerDTO].self, from: data)
                DispatchQueue.main.async {
                    buyersByPromoter[promoterId] = decoded
                    expandedPromoterId = promoterId
                }
            } catch {
                print("❌ Failed to decode buyers: \(error.localizedDescription)")
            }
        }.resume()
    }

    func assignPromoter() {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "http://localhost:8080/api/promoters/\(event.id)/assign"),
              !userIdInput.isEmpty else {
            message = "Invalid username"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["username": userIdInput]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                DispatchQueue.main.async {
                    message = "✅ Promoter assigned!"
                    userIdInput = ""
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        fetchPromoters()
                    }
                }
            } else {
                DispatchQueue.main.async {
                    message = "❌ Failed to assign promoter."
                }
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
