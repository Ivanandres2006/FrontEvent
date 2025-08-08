import SwiftUI
import Charts

struct EventAnalyticsView: View {
    @AppStorage("selectedLanguage") var lang: String = "en"
    let eventId: Int
    @State private var analytics: EventAnalyticsDTO?
    @State private var isLoading = true
    @State private var errorMessage: String?

    enum Tab { case overview, sales, tiers }
    @State private var selectedTab: Tab = .overview

    // animation state
    @State private var animateCharts = true

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    if let data = analytics {
                        topEventCard(data)

                        segmentedTabs

                        switch selectedTab {
                        case .overview: overviewTab(data)
                        case .sales:    salesTab(data)
                        case .tiers:    tiersTab(data)
                        }
                    } else if isLoading {
                        ProgressView(lang == "es" ? "Cargando..." : "Loading...").foregroundColor(.white)
                    } else if let error = errorMessage {
                        Text(error).foregroundColor(.red)
                    }
                }
                .padding()
            }
        }
        .onAppear { fetchAnalytics() }
    }

    // MARK: - Top Card (matches screenshot structure)
    private func topEventCard(_ data: EventAnalyticsDTO) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(data.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)

                HStack(spacing: 10) {
                    Capsule()
                        .fill(Color.green.opacity(0.15))
                        .overlay(
                            HStack(spacing: 6) {
                                Circle().fill(Color.green).frame(width: 8, height: 8)
                                Text("Active").foregroundColor(.green).font(.caption.bold())
                            }.padding(.horizontal, 8)
                        )
                        .frame(height: 24)
                    Text("Aug 8, 2025")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - Segmented control (Overview / Sales / Tiers)
    private var segmentedTabs: some View {
        HStack(spacing: 8) {
            segBtn(.overview, "Overview")
            segBtn(.sales, "Sales")
            segBtn(.tiers, "Tiers")
        }
        .padding(4)
        .background(Color.white.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.10), lineWidth: 1))
        .cornerRadius(12)
    }

    private func segBtn(_ tab: Tab, _ label: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { selectedTab = tab }
        } label: {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(selectedTab == tab ? .black : .white.opacity(0.85))
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(selectedTab == tab ? Color.gold : Color.clear)
                .cornerRadius(8)
        }
    }

    // MARK: - Overview Tab (4 metric cards + capacity + revenue per ticket)
    private func overviewTab(_ data: EventAnalyticsDTO) -> some View {
        let total = data.totalTicketsSold + data.totalTicketsAvailable
        let sold = data.totalTicketsSold
        let sellThrough = total == 0 ? 0 : (Double(sold) / Double(total)) * 100
        let avgPrice = sold > 0 ? data.revenue / Double(sold) : 0

        return VStack(spacing: 16) {
            // two rows of two small metric cards
            HStack(spacing: 12) {
                MetricCard(icon: "ticket",        title: "Tickets Sold", value: "\(sold)", subtitle: "of \(total)", tint: .blue)
                MetricCard(icon: "dollarsign",    title: "Revenue",      value: "$\(Int(data.revenue))", subtitle: "+8% this week", tint: .green)
            }
            HStack(spacing: 12) {
                MetricCard(icon: "chart.bar",     title: "Capacity",     value: "\(String(format: "%.1f", sellThrough))%", subtitle: "\(total - sold) remaining", tint: .purple)
                MetricCard(icon: "rectangle.3.group", title: "Tiers Active", value: "\(data.ticketTierBreakdown.count)", subtitle: "ticket types", tint: .orange)
            }

            // Sales Overview card
            SectionCard {
                VStack(alignment: .leading, spacing: 14) {
                    sectionHeader(title: "Sales Overview", subtitle: "Key performance metrics")

                    HStack(spacing: 12) {
                        PillStat(title: "Total Sold", value: "\(sold)")
                        PillStat(title: "Available",  value: "\(total)")
                    }

                    HStack {
                        Text("Capacity utilization")
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.75))
                        Spacer()
                        Text("\(String(format: "%.1f", sellThrough))%")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.white.opacity(0.9))
                    }

                    ProgressView(value: sellThrough / 100)
                        .tint(.gold)
                        .frame(height: 6)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Revenue per ticket")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.gold)
                        Text("$\(String(format: "%.2f", avgPrice))")
                            .font(.title3.weight(.bold))
                            .foregroundColor(.gold)
                    }
                    .padding()
                    .background(Color.gold.opacity(0.12))
                    .cornerRadius(12)
                }
            }
        }
    }

    // MARK: - Sales Tab (Improved UI)
    private func salesTab(_ data: EventAnalyticsDTO) -> some View {
        let series = data.salesOverTime

        return VStack(spacing: 20) {
            
            // --- Sales Over Time ---
            VStack(alignment: .leading, spacing: 4) {
                Text("Sales Over Time")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                Text("Daily ticket sales performance")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Chart(series, id: \.date) { point in
                let y: Int = animateCharts ? point.sold : 0
                
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("Sold", y)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.gold.opacity(0.35), Color.gold.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Sold", y)
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .foregroundStyle(Color.gold)
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { value in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                        .foregroundStyle(.white.opacity(0.6))
                        .font(.system(size: 11))
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic) { value in
                    AxisValueLabel()
                        .foregroundStyle(.white.opacity(0.6))
                        .font(.system(size: 11))
                }
            }
            .frame(height: 200)
            .background(Color.white.opacity(0.03))
            .cornerRadius(12)

            // --- Daily Sales ---
            VStack(alignment: .leading, spacing: 4) {
                Text("Daily Sales")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                Text("Breakdown by date")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Chart(series, id: \.date) { point in
                let y: Int = animateCharts ? point.sold : 0
                BarMark(
                    x: .value("Date", point.date),
                    y: .value("Sold", y)
                )
                .cornerRadius(4)
                .foregroundStyle(Color.blue)
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { value in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                        .foregroundStyle(.white.opacity(0.6))
                        .font(.system(size: 11))
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic) { value in
                    AxisValueLabel()
                        .foregroundStyle(.white.opacity(0.6))
                        .font(.system(size: 11))
                }
            }
            .frame(height: 180)
            .background(Color.white.opacity(0.03))
            .cornerRadius(12)
        }
    }

    // MARK: - Tiers Tab (Improved UI)
    private func tiersTab(_ data: EventAnalyticsDTO) -> some View {
        let tiers = data.ticketTierBreakdown
        let total = max(data.totalTicketsSold, 1)

        return VStack(spacing: 20) {

            // --- Ticket Tier Breakdown ---
            VStack(alignment: .leading, spacing: 4) {
                Text("Ticket Tier Breakdown")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                Text("Sales by ticket type")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 10) {
                ForEach(Array(tiers.enumerated()), id: \.element.tier) { idx, t in
                    let pct = Double(t.sold) / Double(total) * 100
                    HStack {
                        Circle()
                            .fill(paletteColor(idx))
                            .frame(width: 12, height: 12)
                        Text(t.tier)
                            .foregroundColor(.white)
                            .font(.system(size: 14))
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(t.sold)")
                                .foregroundColor(.white)
                                .font(.system(size: 15, weight: .semibold))
                            Text("\(String(format: "%.1f", pct))%")
                                .foregroundColor(.white.opacity(0.6))
                                .font(.system(size: 12))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.03))
            .cornerRadius(12)

            // --- Tier Distribution ---
            VStack(alignment: .leading, spacing: 4) {
                Text("Tier Distribution")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                Text("Visual breakdown")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Chart(tiers, id: \.tier) { t in
                let sold: Int = animateCharts ? t.sold : 0
                SectorMark(
                    angle: .value("Sold", sold),
                    innerRadius: .ratio(0.6)
                )
                .foregroundStyle(by: .value("Tier", t.tier))
            }
            .frame(height: 200)
            .background(Color.white.opacity(0.03))
            .cornerRadius(12)
        }
    }


    // MARK: - Components
    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundColor(.white).font(.headline)
            Text(subtitle).foregroundColor(.white.opacity(0.65)).font(.caption)
        }
    }

    struct SectionCard<Content: View>: View {
        var content: () -> Content
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(16)
            .background(Color.white.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 1))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
        }
    }

    struct PillStat: View {
        let title: String
        let value: String
        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.footnote).foregroundColor(.white.opacity(0.7))
                Text(value).font(.title3.weight(.semibold)).foregroundColor(.white)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.10), lineWidth: 1))
            .cornerRadius(12)
        }
    }

    struct MetricCard: View {
        let icon: String
        let title: String
        let value: String
        let subtitle: String
        let tint: Color

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(tint.opacity(0.2))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: icon)
                                .foregroundColor(tint)
                                .font(.callout.weight(.bold))
                        )
                    Spacer()
                }
                Text(title)
                    .foregroundColor(.white.opacity(0.8))
                    .font(.footnote)
                Text(value)
                    .foregroundColor(.white)
                    .font(.title3.weight(.bold))
                Text(subtitle)
                    .foregroundColor(.white.opacity(0.6))
                    .font(.caption)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .cornerRadius(16)
        }
    }


    // MARK: - Palette
    private func paletteColor(_ index: Int) -> Color {
        let palette: [Color] = [.blue, .orange, .green, .purple, .red, .pink, .yellow, .teal]
        return palette[index % palette.count]
    }

    // MARK: - Networking
    private func fetchAnalytics() {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/events/\(eventId)/analytics") else {
            self.errorMessage = "Invalid URL or token"
            self.isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                isLoading = false
                if let error = error { self.errorMessage = error.localizedDescription; return }
                guard let data = data else { self.errorMessage = "No data"; return }
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
