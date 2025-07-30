import SwiftUI
import Stripe
import StripePaymentSheet

struct ReunionDashboardView: View {
    @AppStorage("selectedLanguage") var lang: String = "en"
    @EnvironmentObject var userSession: UserSession
    var budgetGoal: Double
    var attendees: [ReunionGuest]
    var isOwner: Bool
    var eventId: Int

    @State private var isLoading = false
    @State private var message = ""
    @State private var paymentSheet: PaymentSheet?
    @State private var guests: [ReunionGuest] = []
    
    @State private var showAddGuestSheet = false


    var body: some View {
        VStack(spacing: 24) {
            Text(lang == "es" ? "📊 Panel de la Reunión" : "📊 Reunion Dashboard")
                .font(.largeTitle.bold())
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Summary Section
            VStack(alignment: .leading, spacing: 14) {
                Text(lang == "es" ? "💰 Resumen del Presupuesto" : "💰 Budget Summary")
                    .font(.headline)
                    .foregroundColor(.white)

                HStack {
                    summaryCard(
                        title: lang == "es" ? "Total" : "Total",
                        value: String(format: "$%.2f", budgetGoal),
                        icon: "dollarsign.circle.fill",
                        color: .mint
                    )

                    summaryCard(
                        title: lang == "es" ? "Por Persona" : "Per Person",
                        value: String(format: "$%.2f", budgetPerGuest()),
                        icon: "person.fill",
                        color: .gold
                    )

                    summaryCard(
                        title: lang == "es" ? "Pagado" : "Paid",
                        value: "\(paidCount())/\(guests.count)",
                        icon: "checkmark.seal.fill",
                        color: .green
                    )
                }
            }

            Divider().background(Color.white.opacity(0.2))

            // Guest List Section
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(lang == "es" ? "👥 Contribuciones de los Invitados" : "👥 Guest Contributions")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Spacer()

                    if isOwner {
                        Button {
                            showAddGuestSheet = true
                        } label: {
                            Label("Edit", systemImage: "pencil.circle")
                                .foregroundColor(.gold)
                                .font(.body)
                        }
                    }
                }

                if guests.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.4))
                        Text(lang == "es" ? "👥 Contribuciones de los Invitados" : "👥 Guest Contributions")
                            .foregroundColor(.white.opacity(0.5))
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(guests.indices, id: \.self) { i in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(guests[i].name)
                                            .font(.headline)
                                            .foregroundColor(.white)
                                        Text(guests[i].email)
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.5))
                                    }

                                    Spacer()

                                    if isOwner {
                                        Button {
                                                guests[i].paid.toggle()
                                                updatePaidStatus(email: guests[i].email, paid: guests[i].paid)
                                            } label: {
                                                Image(systemName: guests[i].paid ? "checkmark.circle.fill" : "xmark.circle")
                                                    .foregroundColor(guests[i].paid ? .green : .red)
                                                    .font(.title3)
                                            }
                                    } else {
                                        if guests[i].email == userSession.email {
                                            if guests[i].paid {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.green)
                                                    .font(.title3)
                                            } else {
                                                Button {
                                                    startCheckout()
                                                } label: {
                                                    Text(lang == "es" ? "Pagar" : "Pay")
                                                        .font(.caption)
                                                        .padding(.horizontal, 10)
                                                        .padding(.vertical, 6)
                                                        .background(Color.gold)
                                                        .foregroundColor(.black)
                                                        .cornerRadius(8)
                                                }
                                            }
                                        } else {
                                            Image(systemName: guests[i].paid ? "checkmark.circle.fill" : "circle")
                                                .foregroundColor(guests[i].paid ? .green : .gray)
                                                .font(.title3)
                                        }
                                    }
                                }
                                .padding()
                                .listRowBackground(Color.clear)
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(12)
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 30)
        }
        .padding()
        .background(LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .onAppear {
            fetchUpdatedGuests()
        }
        .sheet(isPresented: $showAddGuestSheet, onDismiss: {
            fetchUpdatedGuests() // ✅ Refresh backend state on close
        }) {
            AddGuestSheetView(
                onAddGuest: { updatedGuests in
                    guests = updatedGuests
                },
                existingGuests: guests,
                eventId: eventId
            )
        }
    }

    // MARK: - Helpers

    func summaryCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            Text(title)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
            Text(value)
                .font(.headline)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }

    func budgetPerGuest() -> Double {
        let totalGuests = max(guests.count + 1, 1)
        return budgetGoal / Double(totalGuests)
    }

    private func presentPaymentSheet(paymentIntentId: String) {
        guard let sheet = paymentSheet else {
            message = "Payment sheet not ready."
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let topVC = topViewController() {
                if topVC.presentedViewController != nil {
                    // Retry logic if needed
                    return
                }
                
                sheet.present(from: topVC) { result in
                    paymentSheet = nil

                    switch result {
                    case .completed:
                        updatePaidStatus(email: userSession.email, paid: true)
                        fetchUpdatedGuests() // ✅ fetch fresh data from backend
                    case .canceled:
                        message = "❌ Payment canceled"
                    case .failed(let error):
                        message = "❌ Payment failed: \(error.localizedDescription)"
                    }
                }
            } else {
                message = "Couldn't find view controller"
            }
        }
    }

    private func topViewController(controller: UIViewController? = UIApplication.shared
        .connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first(where: { $0.isKeyWindow })?.rootViewController) -> UIViewController? {

        if let nav = controller as? UINavigationController {
            return topViewController(controller: nav.visibleViewController)
        }
        if let tab = controller as? UITabBarController {
            return topViewController(controller: tab.selectedViewController)
        }
        if let presented = controller?.presentedViewController {
            return topViewController(controller: presented)
        }
        return controller
    }

    
    func paidCount() -> Int {
        guests.filter { $0.paid }.count
    }

    func startCheckout() {
        guard let token = TokenManager.shared.getAccessToken() else { return }

        let email = userSession.email
        let urlString = "https://backendevent-etce.onrender.com/api/payments/reunion-checkout?eventId=\(eventId)&email=\(email)"

        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                print("❌ Stripe error: \(error)")
                return
            }

            guard let data = data else {
                print("❌ No data returned from server")
                return
            }

            if let raw = String(data: data, encoding: .utf8) {
                print("🧾 Raw response:")
                print(raw)
            }

            guard let response = try? JSONDecoder().decode(PaymentSheetResponse.self, from: data) else {
                print("❌ Failed to decode payment response")
                return
            }

            var config = PaymentSheet.Configuration()
            config.merchantDisplayName = "WKND"
            config.primaryButtonColor = .systemPink

            DispatchQueue.main.async {
                paymentSheet = PaymentSheet(paymentIntentClientSecret: response.clientSecret, configuration: config)

                if let intentId = extractPaymentIntentId(from: response.clientSecret) {
                    presentPaymentSheet(paymentIntentId: intentId)
                }
            }
        }.resume()
    }
    
    private func extractPaymentIntentId(from clientSecret: String) -> String? {
        return clientSecret.components(separatedBy: "_secret").first
    }

    
    func fetchUpdatedGuests() {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/events/\(eventId)") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data else { return }
            if let updatedEvent = try? JSONDecoder().decode(Event.self, from: data) {
                DispatchQueue.main.async {
                    self.guests = updatedEvent.reunionGuests ?? []
                }
            }
        }.resume()
    }


    
    func updatePaidStatus(email: String, paid: Bool) {
        guard let url = URL(string: "https://backendevent-etce.onrender.com/api/payments/confirm-reunion-paid?eventId=\(eventId)&email=\(email)&paid=\(paid)") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                print("❌ Confirm reunion paid failed: \(error)")
            } else if let httpResponse = response as? HTTPURLResponse {
                print("✅ Confirm reunion paid status: \(httpResponse.statusCode)")
            }
        }.resume()
    }

}

struct GuestUpdateRequest: Encodable {
    let email: String
    let paid: Bool
}

struct PaymentSheetResponse: Decodable {
    let clientSecret: String
}

struct AddGuestSheetView: View {
    @Environment(\.dismiss) var dismiss
    @State private var usernameSearch = ""
    @State private var suggestions: [String] = []
    @State private var isSearching = false
    @State private var justAddedUsername: String?

    var onAddGuest: ([ReunionGuest]) -> Void
    var existingGuests: [ReunionGuest]
    var eventId: Int

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("🔍 Edit the Reunion Guests")
                    .font(.title.bold())
                    .foregroundColor(.white)

                TextField("Start typing a username...", text: $usernameSearch)
                    .onChange(of: usernameSearch) { _ in fetchSuggestions() }
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
                    .foregroundColor(.white)

                if isSearching {
                    HStack {
                        Spacer()
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                        Spacer()
                    }
                } else if !usernameSearch.isEmpty && suggestions.isEmpty {
                    Text("❌ No matching users found")
                        .foregroundColor(.gray)
                        .padding(.top, 20)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {

                        // Suggestions
                        if !suggestions.isEmpty {
                            Text("Suggestions")
                                .foregroundColor(.white.opacity(0.6))
                                .font(.headline)

                            ForEach(suggestions, id: \.self) { username in
                                Button {
                                    addGuest(username: username)
                                } label: {
                                    HStack {
                                        Image(systemName: "person.crop.circle.badge.plus")
                                        Text(username).fontWeight(.medium)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                    }
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(Color.white.opacity(0.08))
                                    .cornerRadius(10)
                                }
                            }

                            Divider().background(Color.white.opacity(0.2)).padding(.vertical)
                        }

                        // Current Guests (with swipe to delete)
                        Text("Current Guests")
                            .foregroundColor(.white.opacity(0.6))
                            .font(.headline)

                        if existingGuests.isEmpty {
                            HStack {
                                Spacer()
                                Text("🙁 No guests added yet")
                                    .foregroundColor(.gray)
                                    .padding(.vertical, 32)
                                Spacer()
                            }
                        } else {
                            List {
                                ForEach(existingGuests, id: \.username) { guest in
                                    HStack {
                                        Image(systemName: guest.attending ? "checkmark.circle.fill" : "person.fill")
                                            .foregroundColor(guest.attending ? .green : .white)
                                        Text(guest.name.isEmpty ? guest.username : guest.name)
                                            .foregroundColor(.white)
                                        Spacer()
                                    }
                                    .padding()
                                    .listRowBackground(Color.clear)
                                    .background(Color.white.opacity(0.05))
                                    .cornerRadius(10)
                                }
                                .onDelete(perform: deleteGuest)
                            }
                            .listStyle(PlainListStyle())
                            .frame(height: 200)
                            .background(Color.clear)
                        }
                    }
                }

                if let added = justAddedUsername {
                    Text("✅ Added \(added)")
                        .foregroundColor(.green)
                        .font(.subheadline)
                        .transition(.opacity)
                        .padding(.top)
                }

                Spacer()
            }
            .padding()
            .background(LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .navigationBarItems(trailing: Button("Close") {
                dismiss()
            }.foregroundColor(.gold))
        }
    }

    func fetchSuggestions() {
        guard !usernameSearch.isEmpty else {
            suggestions = []
            return
        }

        isSearching = true
        let query = usernameSearch.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlStr = "https://backendevent-etce.onrender.com/user/search-usernames?q=\(query)"

        guard let url = URL(string: urlStr),
              let token = TokenManager.shared.getAccessToken() else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                isSearching = false
                if let data = data,
                   let usernames = try? JSONDecoder().decode([String].self, from: data) {
                    suggestions = usernames.filter { u in
                        !existingGuests.contains(where: { $0.username.lowercased() == u.lowercased() })
                    }
                } else {
                    suggestions = []
                }
            }
        }.resume()
    }

    func deleteGuest(at offsets: IndexSet) {
        // 1. Update local guest list
        let updatedGuests = existingGuests.enumerated()
            .filter { !offsets.contains($0.offset) }
            .map { $0.element }

        // 2. Convert to DTOs
        let guestDTOs: [[String: Any]] = updatedGuests.map {
            [
                "username": $0.username,
                "paid": $0.paid
            ]
        }

        // 3. Send to backend
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/events/\(eventId)") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["guests": guestDTOs])

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                print("❌ Failed to delete guest: \(error)")
            } else if let httpResponse = response as? HTTPURLResponse {
                print("✅ Guest deleted. Status: \(httpResponse.statusCode)")
            }
        }.resume()

        // 4. Update UI immediately
        DispatchQueue.main.async {
            onAddGuest(updatedGuests)
        }
    }

    
    func addGuest(username: String) {
        let newGuest = ReunionGuest(
            username: username,
            name: username,
            email: "",
            paid: false,
            attending: false
        )

        let updatedGuests = existingGuests + [newGuest]
        onAddGuest(updatedGuests)
        updateGuestListOnServer(updatedGuests)
        justAddedUsername = username

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            justAddedUsername = nil
            dismiss()
        }
    }

    func updateGuestListOnServer(_ updatedGuests: [ReunionGuest]) {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/events/\(eventId)") else { return }

        let guestDTOs: [[String: Any]] = updatedGuests.map {
            [
                "username": $0.username,
                "paid": $0.paid
            ]
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["guests": guestDTOs])

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                print("❌ Failed to update guests: \(error)")
            } else if let httpResponse = response as? HTTPURLResponse {
                print("✅ Updated guest list. Status: \(httpResponse.statusCode)")
            }
        }.resume()
    }

}



