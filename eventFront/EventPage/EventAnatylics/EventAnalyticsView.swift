import SwiftUI
import Charts

// MARK: - Event Analytics

struct EventAnalyticsView: View {
    @AppStorage("selectedLanguage") var lang: String = "en"
    let eventId: Int

    @State private var analytics: EventAnalyticsDTO?
    @State private var isLoading = true
    @State private var errorMessage: String?

    enum Tab { case overview, sales, tiers }
    @State private var selectedTab: Tab = .overview

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
                        ProgressView(lang == "es" ? "Cargando..." : "Loading...")
                            .tint(.white)
                            .foregroundColor(.white)
                            .padding(.top, 40)
                    } else if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .padding(.top, 40)
                    }
                }
                .padding()
            }
        }
        .onAppear { fetchAnalytics() }
    }

    // MARK: - Top Card
    private func topEventCard(_ data: EventAnalyticsDTO) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(data.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)

                HStack(spacing: 10) {
                    Capsule()
                        .fill(Color.green.opacity(0.14))
                        .overlay(
                            HStack(spacing: 6) {
                                Circle().fill(Color.green).frame(width: 8, height: 8)
                                Text("Active")
                                    .foregroundColor(.green)
                                    .font(.caption.bold())
                            }
                            .padding(.horizontal, 10)
                        )
                        .frame(height: 24)

                    Text(lang == "es" ? "Estadísticas en vivo" : "Live analytics")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - Tabs
    private var segmentedTabs: some View {
        HStack(spacing: 8) {
            segBtn(.overview, lang == "es" ? "Resumen" : "Overview")
            segBtn(.sales,    lang == "es" ? "Ventas"  : "Sales")
            segBtn(.tiers,    lang == "es" ? "Niveles" : "Tiers")
        }
        .padding(4)
        .background(Color.white.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.10), lineWidth: 1))
        .cornerRadius(12)
    }

    private func segBtn(_ tab: Tab, _ label: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
        } label: {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(selectedTab == tab ? .black : .white.opacity(0.9))
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(selectedTab == tab ? Color.gold : Color.clear)
                .cornerRadius(8)
        }
    }

    // MARK: - Overview
    private func overviewTab(_ d: EventAnalyticsDTO) -> some View {
        let total = d.totalTicketsSold + d.totalTicketsAvailable
        let sold = d.totalTicketsSold
        let remaining = max(total - sold, 0)
        let sellThrough = total == 0 ? 0 : (Double(sold) / Double(total)) * 100
        let avgPrice = sold > 0 ? d.revenue / Double(sold) : 0

        return VStack(spacing: 16) {
            HStack(spacing: 12) {
                MetricCard(icon: "ticket",
                           title: lang == "es" ? "Entradas vendidas" : "Tickets Sold",
                           value: "\(sold)",
                           subtitle: "\(lang == "es" ? "de" : "of") \(total)",
                           tint: .blue)
                MetricCard(icon: "dollarsign",
                           title: lang == "es" ? "Ingresos" : "Revenue",
                           value: formatCurrency(d.revenue),
                           subtitle: lang == "es" ? "hoy a la fecha" : "to date",
                           tint: .green)
            }
            HStack(spacing: 12) {
                MetricCard(icon: "chart.bar",
                           title: lang == "es" ? "Capacidad" : "Capacity",
                           value: "\(String(format: "%.1f", sellThrough))%",
                           subtitle: "\(remaining) \(lang == "es" ? "restantes" : "remaining")",
                           tint: .purple)
                MetricCard(icon: "rectangle.3.group",
                           title: lang == "es" ? "Niveles activos" : "Tiers Active",
                           value: "\(d.ticketTierBreakdown.count)",
                           subtitle: lang == "es" ? "tipos de ticket" : "ticket types",
                           tint: .orange)
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 14) {
                    sectionHeader(title: lang == "es" ? "Panorama de ventas" : "Sales Overview",
                                  subtitle: lang == "es" ? "Métricas clave" : "Key performance metrics")

                    HStack(spacing: 12) {
                        PillStat(title: lang == "es" ? "Vendidas" : "Total Sold", value: "\(sold)")
                        PillStat(title: lang == "es" ? "Disponibles" : "Available", value: "\(total)")
                    }

                    HStack {
                        Text(lang == "es" ? "Uso de capacidad" : "Capacity utilization")
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
                        Text(lang == "es" ? "Ingreso por ticket" : "Revenue per ticket")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.gold)
                        Text(formatCurrency(avgPrice))
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

    // MARK: - Sales
    private func salesTab(_ data: EventAnalyticsDTO) -> some View {
        // Convert backend strings to Dates
        let series: [DatePoint] = data.salesOverTime.compactMap { row in
            guard let d = parseDate(row.date) else { return nil }
            return DatePoint(date: d, sold: row.sold)
        }

        return VStack(spacing: 22) {
            header("Sales Over Time", "Daily ticket sales performance")
            if series.isEmpty {
                emptyChartPlaceholder()
            } else {
                SalesAreaChartView(series: series) // line + area + 7d MA + crosshair (iOS16-safe)
            }

            header("Daily Sales", "Breakdown by date")
            if series.isEmpty {
                emptyChartPlaceholder()
            } else {
                SalesBarsChartView(series: series) // horizontal-scrollable bars
            }
        }
    }

    // MARK: - Tiers (iOS16-safe: custom stacked strip + rows)
    private func tiersTab(_ d: EventAnalyticsDTO) -> some View {
        let tiers = d.ticketTierBreakdown
        let total = max(d.totalTicketsSold, 1)

        return VStack(spacing: 22) {
            header("Ticket Tier Breakdown", "Sales by ticket type")

            if tiers.isEmpty {
                emptyChartPlaceholder()
            } else {
                // Stacked distribution strip (100%)
                TierDistributionStrip(items: tiers.map { ($0.tier, $0.sold) })

                // List with percentages
                VStack(spacing: 10) {
                    ForEach(Array(tiers.enumerated()), id: \.element.tier) { idx, t in
                        let pct = Double(t.sold) / Double(total) * 100
                        HStack {
                            Circle().fill(paletteColor(idx)).frame(width: 10, height: 10)
                            Text(t.tier).foregroundColor(.white)
                            Spacer()
                            Text("\(t.sold) • \(String(format: "%.1f", pct))%")
                                .foregroundColor(.white.opacity(0.75))
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal, 10)
                .background(Color.white.opacity(0.03))
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Components
    private func header(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(lang == "es" ? localized(title) : title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            Text(lang == "es" ? localized(subtitle) : subtitle)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    struct SectionCard<Content: View>: View {
        var content: () -> Content
        var body: some View {
            VStack(alignment: .leading, spacing: 0) { content() }
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
                HStack {
                    Circle()
                        .fill(tint.opacity(0.2))
                        .frame(width: 28, height: 28)
                        .overlay(Image(systemName: icon).foregroundColor(tint).font(.callout.weight(.bold)))
                    Spacer()
                }
                Text(title).foregroundColor(.white.opacity(0.8)).font(.footnote)
                Text(value).foregroundColor(.white).font(.title3.weight(.bold))
                Text(subtitle).foregroundColor(.white.opacity(0.6)).font(.caption)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 1))
            .cornerRadius(16)
        }
    }

    private func emptyChartPlaceholder() -> some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.white.opacity(0.03))
            .overlay(
                VStack(spacing: 6) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.6))
                    Text(lang == "es" ? "Sin datos suficientes" : "Not enough data yet")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.caption)
                }
            )
            .frame(height: 180)
    }

    // MARK: - Helpers / Data
    struct DatePoint: Identifiable {
        let id = UUID()
        let date: Date
        let sold: Int
    }

    private func parseDate(_ s: String) -> Date? {
        // yyyy-MM-dd
        let d1 = DateFormatter()
        d1.locale = Locale(identifier: "en_US_POSIX")
        d1.dateFormat = "yyyy-MM-dd"
        if let d = d1.date(from: s) { return d }
        // ISO8601 fallback
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFrac.date(from: s) { return d }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: s)
    }

    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.dateFormat = "MMM d"
        return f.string(from: d)
    }

    private func formatCurrency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = Locale.current.currency?.identifier ?? "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }

    private func localized(_ s: String) -> String {
        switch s {
        case "Sales Over Time": return "Ventas a lo largo del tiempo"
        case "Daily ticket sales performance": return "Rendimiento diario de ventas"
        case "Daily Sales": return "Ventas diarias"
        case "Breakdown by date": return "Desglose por fecha"
        case "Ticket Tier Breakdown": return "Desglose por tipo de ticket"
        case "Sales by ticket type": return "Ventas por tipo de ticket"
        default: return s
        }
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundColor(.white).font(.headline)
            Text(subtitle).foregroundColor(.white.opacity(0.65)).font(.caption)
        }
    }

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
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, resp, error in
            DispatchQueue.main.async { isLoading = false }
            if let error = error { DispatchQueue.main.async { self.errorMessage = error.localizedDescription }; return }
            guard let http = resp as? HTTPURLResponse, let data = data else {
                DispatchQueue.main.async { self.errorMessage = "No response" }; return
            }
            guard (200...299).contains(http.statusCode) else {
                let msg: String
                switch http.statusCode {
                case 401: msg = "Unauthorized (401). Please sign in again."
                case 403: msg = "Forbidden (403). You don’t have access."
                default:  msg = "Server error \(http.statusCode)"
                }
                DispatchQueue.main.async { self.errorMessage = msg }
                return
            }
            do {
                let decoded = try JSONDecoder().decode(EventAnalyticsDTO.self, from: data)
                DispatchQueue.main.async { self.analytics = decoded }
            } catch {
                DispatchQueue.main.async { self.errorMessage = "Decode error: \(error.localizedDescription)" }
            }
        }.resume()
    }
}

// MARK: - iOS16-safe Sales Charts

private struct SalesAreaChartView: View {
    let series: [EventAnalyticsView.DatePoint]
    @State private var selected: Date? = nil

    var body: some View {
        let avg7 = movingAverage(series, window: 7)

        Chart {
            // Area
            ForEach(series) { p in
                AreaMark(x: .value("Date", p.date), y: .value("Sold", p.sold))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(colors: [Color.gold.opacity(0.35), Color.gold.opacity(0.05)],
                                       startPoint: .top, endPoint: .bottom)
                    )
            }

            // Line
            ForEach(series) { p in
                LineMark(x: .value("Date", p.date), y: .value("Sold", p.sold))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(.init(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Color.gold)
            }

            // 7-day moving average (dashed)
            if avg7.count > 1 {
                ForEach(avg7) { p in
                    LineMark(x: .value("Date", p.date), y: .value("7d Avg", p.sold))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(.init(lineWidth: 1.6, dash: [6,6]))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
            }

            // Last point highlight
            if let last = series.last {
                PointMark(x: .value("Date", last.date), y: .value("Sold", last.sold))
                    .symbol(.circle)
                    .foregroundStyle(Color.gold)
            }
        }
        .chartXAxis {
            AxisMarks(position: .bottom) {
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                AxisTick().foregroundStyle(.white.opacity(0.25))
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .foregroundStyle(.white.opacity(0.7))
                    .font(.system(size: 11))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) {
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                AxisTick().foregroundStyle(.white.opacity(0.25))
                AxisValueLabel()
                    .foregroundStyle(.white.opacity(0.7))
                    .font(.system(size: 11))
            }
        }
        .frame(height: 230)
        .background(Color.white.opacity(0.03))
        .cornerRadius(14)
        .modifier(CrosshairOverlay(selected: $selected, series: series))
        .padding(.top, 2)
    }

    // helpers
    private func movingAverage(_ pts: [EventAnalyticsView.DatePoint], window: Int) -> [EventAnalyticsView.DatePoint] {
        guard window > 1, pts.count >= window else { return [] }
        var out: [EventAnalyticsView.DatePoint] = []
        var sum = 0
        for i in pts.indices {
            sum += pts[i].sold
            if i >= window { sum -= pts[i - window].sold }
            if i >= window - 1 {
                out.append(.init(date: pts[i].date, sold: Int(round(Double(sum)/Double(window)))))
            }
        }
        return out
    }
}

private struct SalesBarsChartView: View {
    let series: [EventAnalyticsView.DatePoint]

    var body: some View {
        Chart(series) { p in
            BarMark(x: .value("Date", p.date),
                    y: .value("Sold", p.sold))
                .cornerRadius(3)
                .foregroundStyle(Color.blue)
        }
        .chartXAxis {
            AxisMarks(position: .bottom) {
                AxisGridLine().foregroundStyle(.white.opacity(0.05))
                AxisTick().foregroundStyle(.white.opacity(0.25))
                AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                    .foregroundStyle(.white.opacity(0.7))
                    .font(.system(size: 11))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) {
                AxisGridLine().foregroundStyle(.white.opacity(0.05))
                AxisTick().foregroundStyle(.white.opacity(0.25))
                AxisValueLabel().foregroundStyle(.white.opacity(0.7))
                    .font(.system(size: 11))
            }
        }
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: 12 * 24 * 60 * 60) // ~12 days
        .frame(height: 220)
        .background(Color.white.opacity(0.03))
        .cornerRadius(14)
    }
}

// MARK: - Crosshair overlay (iOS16)

private struct CrosshairOverlay: ViewModifier {
    @Binding var selected: Date?
    let series: [EventAnalyticsView.DatePoint]

    func body(content: Content) -> some View {
        content.chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let plot = proxy.plotAreaFrame
                                let origin = geo[plot].origin
                                let x = value.location.x - origin.x
                                if let d: Date = proxy.value(atX: x) {
                                    // Snap to nearest data point
                                    selected = series.min { abs($0.date.timeIntervalSince(d)) < abs($1.date.timeIntervalSince(d)) }?.date ?? d
                                }
                            }
                            .onEnded { _ in selected = nil }
                    )

                if let sel = selected, let posX = proxy.position(forX: sel) {
                    let plotRect = geo[proxy.plotAreaFrame]
                    // vertical guide
                    Rectangle()
                        .fill(Color.white.opacity(0.6))
                        .frame(width: 1)
                        .position(x: posX + plotRect.origin.x, y: plotRect.midY)

                    if let p = series.min(by: { abs($0.date.timeIntervalSince(sel)) < abs($1.date.timeIntervalSince(sel)) }) {
                        VStack(spacing: 4) {
                            Text(shortDate(p.date))
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.85))
                            Text("\(p.sold) sold")
                                .font(.caption2.bold())
                                .foregroundColor(.white)
                        }
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                        .position(x: posX + plotRect.origin.x, y: plotRect.origin.y - 18)
                    }
                }
            }
        }
    }

    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.dateFormat = "MMM d"
        return f.string(from: d)
    }
}

// MARK: - Tier Distribution (SwiftUI only, iOS16-safe)

private struct TierDistributionStrip: View {
    let items: [(label: String, value: Int)]

    private var total: Double {
        max(Double(items.map { $0.value }.reduce(0,+)), 1)
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, it in
                    let w = CGFloat(Double(it.value) / total) * width
                    Rectangle()
                        .fill(paletteColor(idx))
                        .frame(width: max(w, it.value == 0 ? 0 : 1), height: 14)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .frame(height: 14)
        .padding(12)
        .background(Color.white.opacity(0.03))
        .cornerRadius(12)
    }

    private func paletteColor(_ index: Int) -> Color {
        let palette: [Color] = [.blue, .orange, .green, .purple, .red, .pink, .yellow, .teal]
        return palette[index % palette.count]
    }
}



/**
 private func sectionHeader(title: String, subtitle: String) -> some View {
     VStack(alignment: .leading, spacing: 2) {
         Text(title).foregroundColor(.white).font(.headline)
         Text(subtitle).foregroundColor(.white.opacity(0.65)).font(.caption)
     }
 }
 
 private func paletteColor(_ index: Int) -> Color {
     let palette: [Color] = [.blue, .orange, .green, .purple, .red, .pink, .yellow, .teal]
     return palette[index % palette.count]
 }

 */
