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
                    // 🏷 Title
                    Text(lang == "es" ? "Eventos en \(city)" : "\(city) Events")
                        .font(.largeTitle.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal)
                        .padding(.top)

                    // 📍 Event List
                    VStack(spacing: 16) {
                        ForEach(cityEvents) { event in
                            EventCardView(event: event)
                                .padding(.horizontal)
                                .onTapGesture {
                                    selectedEvent = event
                                }
                        }
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .sheet(item: $selectedEvent) { event in
            EventDetailView(event: event, allEvents: $allEvents)
                .environmentObject(userSession) // pass env object if needed
        }
    }

    var cityEvents: [Event] {
        allEvents.filter { $0.location.lowercased() == city.lowercased() }
    }
}
