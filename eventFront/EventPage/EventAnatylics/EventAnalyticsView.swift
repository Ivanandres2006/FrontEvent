import SwiftUI
import Charts

struct EventAnalyticsView: View {
    let eventId: Int
    @State private var analytics: EventAnalyticsDTO?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    if let data = analytics {
                        Text("Analytics for \(data.title)")
                            .font(.title)
                            .bold()
                            .foregroundColor(.white)

                        statsSection(data)
                        salesChart(data)
                        tierPieChart(data)
                    } else if isLoading {
                        ProgressView("Loading analytics...")
                            .foregroundColor(.white)
                    } else if let error = errorMessage {
                        Text("Error: \(error)")
                            .foregroundColor(.red)
                    }
                }
                .padding()
            }
        }
        .onAppear {
            fetchAnalytics()
        }
    }

    @ViewBuilder
    private func statsSection(_ data: EventAnalyticsDTO) -> some View {
        HStack(spacing: 16) {
            statCard(title: "Sold", value: "\(data.totalTicketsSold)")
            statCard(title: "Left", value: "\(data.totalTicketsAvailable)")
            statCard(title: "Revenue", value: "$\(Int(data.revenue))")
        }
    }

    private func statCard(title: String, value: String) -> some View {
        VStack {
            Text(value)
                .font(.title)
                .bold()
                .foregroundColor(.white)
            Text(title)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.08))
        .cornerRadius(12)
    }

    private func salesChart(_ data: EventAnalyticsDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sales Over Time")
                .foregroundColor(.white)
                .font(.headline)

            Chart(data.salesOverTime, id: \.date) {
                LineMark(x: .value("Date", $0.date),
                         y: .value("Tickets", $0.sold))
            }
            .frame(height: 180)
            .chartXAxis {
                AxisMarks(preset: .aligned)
            }
        }
    }

    private func tierPieChart(_ data: EventAnalyticsDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ticket Tier Breakdown")
                .foregroundColor(.white)
                .font(.headline)

            Chart(data.ticketTierBreakdown, id: \.tier) {
                SectorMark(angle: .value("Sold", $0.sold))
                    .foregroundStyle(by: .value("Tier", $0.tier))
            }
            .frame(height: 200)
        }
    }

    private func fetchAnalytics() {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "http://localhost:8080/events/\(eventId)/analytics") else {
            self.errorMessage = "Invalid URL or token"
            self.isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                isLoading = false
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    return
                }

                guard let data = data else {
                    self.errorMessage = "No data"
                    return
                }

                do {
                    let decoded = try JSONDecoder().decode(EventAnalyticsDTO.self, from: data)
                    self.analytics = decoded
                } catch {
                    self.errorMessage = "Decode error: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
}
