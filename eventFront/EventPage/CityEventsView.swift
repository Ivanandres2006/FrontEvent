import SwiftUI

struct CityEventsView: View {
    @AppStorage("selectedLanguage") var lang: String = "en"
    let city: String
    @Binding var allEvents: [Event]

    @EnvironmentObject var userSession: UserSession
    @State private var selectedEvent: Event? = nil

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(lang == "es" ? "Eventos en \(city)" : "\(city) Events")
                        .font(.largeTitle.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal)
                        .padding(.top)

                    if cityEvents.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "calendar.badge.exclamationmark")
                                .font(.system(size: 44))
                                .foregroundColor(.white.opacity(0.6))
                            Text(lang == "es" ? "No hay futuros eventos" : "No upcoming events")
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity).padding(.top, 8)
                    } else {
                        VStack(spacing: 16) {
                            ForEach(cityEvents) { event in
                                EventCardView(event: event)
                                    .padding(.horizontal)
                                    .onTapGesture { selectedEvent = event }
                            }
                        }
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .sheet(item: $selectedEvent) { event in
            EventDetailView(event: event, allEvents: $allEvents)
                .environmentObject(userSession)
        }
    }

    // MARK: - Filters (same behavior as EventListView)

    /// Parse multiple common ISO-like formats
    private func parseEventDate(_ s: String) -> Date? {
        struct DF {
            static let plain: DateFormatter = {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.timeZone = .current
                f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                return f
            }()
            static let millis: DateFormatter = {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.timeZone = .current
                f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
                return f
            }()
            static let zulu: DateFormatter = {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.timeZone = TimeZone(secondsFromGMT: 0)
                f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
                return f
            }()
        }
        if let d = DF.plain.date(from: s) { return d }
        if let d = DF.millis.date(from: s) { return d }
        if s.hasSuffix("Z"), let d = DF.zulu.date(from: s) { return d }
        return nil
    }

    /// Same reunion visibility rule used in EventListView
    private func isReunionVisible(_ event: Event) -> Bool {
        guard event.type == "reunion" else { return true }
        if let ownerId = event.createdBy?.id, ownerId == userSession.userId { return true }
        if let ownerEmailLegacy = event.createdByEmail,
           ownerEmailLegacy.lowercased() == userSession.email.lowercased() { return true }
        if let guests = event.reunionGuests,
           guests.contains(where: { $0.email.lowercased() == userSession.email.lowercased() }) { return true }
        return false
    }

    /// City events that are in the future and visible, sorted by soonest first
    var cityEvents: [Event] {
        let now = Date()
        return allEvents.compactMap { e -> (Event, Date)? in
            guard e.location.lowercased() == city.lowercased(),
                  let d = parseEventDate(e.dateTime) else { return nil }
            return (d >= now && isReunionVisible(e)) ? (e, d) : nil
        }
        .sorted { $0.1 < $1.1 }
        .map { $0.0 }
    }
}
