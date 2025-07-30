import SwiftUI

struct PostCreationView: View {
    @AppStorage("selectedLanguage") var lang: String = "en"
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var userSession: UserSession

    @ObservedObject var viewModel: PostCreationViewModel
    var onPostCreated: () -> Void

    @State private var selectedTicketLabel: String = ""
    @State private var selectedTicketId: Int?
    @State private var price = ""
    @State private var title = ""
    @State private var isLoading = false
    @State private var errorMessage = ""

    var availableTickets: [TicketDTO] {
        viewModel.tickets.filter { !$0.resold }
    }

    var body: some View {
        ZStack {
            backgroundView

            ScrollView {
                VStack(spacing: 24) {
                    if viewModel.tickets.isEmpty {
                        Text(
                            lang == "es"
                                ? "No tienes entradas para eventos activos en este momento."
                                : "You don't have any tickets for active events right now."
                        )
                        .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.top, 60)
                    } else if availableTickets.isEmpty {
                        Text(
                            lang == "es"
                                ? "Todas tus entradas ya están publicadas para reventa."
                                : "All your tickets are already posted for resale."
                        )
                        .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.top, 60)
                    } else {

                        Text(
                            lang == "es"
                                ? "🎟 Entradas Disponibles: \(availableTickets.count)"
                                : "🎟 Tickets Available: \(availableTickets.count)"
                        )
                        .foregroundColor(.white)

                        headerView
                        dropdownView
                        CustomTextField(    placeholder: lang == "es" ? "Precio (USD)" : "Price (USD)", text: $price, keyboardType: .decimalPad)
                        submitButton
                        errorTextView
                    }

                    Spacer(minLength: 20)
                }
                .padding()
            }
        }
        .onAppear {
            print("📥 PostCreationView appeared with \(viewModel.tickets.count) tickets")
            for ticket in viewModel.tickets {
                print("🔹 \(ticket.eventTitle ?? "nil") | \(ticket.tierName ?? "nil") | ID: \(ticket.id) | Resold: \(ticket.resold)")
            }
        }
    }

    var backgroundView: some View {
        LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }

    var headerView: some View {
        Text(lang == "es" ? "Crear Publicación de Reventa" : "Create Resale Post")
            .font(.largeTitle.bold())
            .foregroundColor(.white)
            .padding(.top)
    }

    var dropdownView: some View {
        let options = availableTickets.map {
            let e = $0.eventTitle ?? (lang == "es" ? "Evento Sin Título" : "Untitled Event")
            let t = $0.tierName ?? (lang == "es" ? "Nivel Sin Nombre" : "Unnamed Tier")
            return "\(e) - \(t) • #\($0.id)"
        }


        return VStack(alignment: .leading, spacing: 10) {
            Text(lang == "es" ? "Selecciona Entrada" : "Select Ticket")
                .foregroundColor(.white.opacity(0.7))

            CustomDropdown(
                label: lang == "es" ? "Elige una Entrada" : "Choose a Ticket",
                selection: $selectedTicketLabel,
                options: options
            )
            .id(UUID())
            .onChange(of: selectedTicketLabel) { label in
                // label ends with "• #<id>"
                if let idString = label.split(separator: "#").last,
                   let id = Int(idString) {
                    selectedTicketId = id
                    if let ticket = availableTickets.first(where: { $0.id == id }) {
                        title = "\(ticket.eventTitle ?? "") - \(ticket.tierName ?? "")"
                        if price.isEmpty { price = "10.00" }
                    }
                } else {
                    errorMessage = lang == "es" ? "Entrada no encontrada." : "Ticket not matched."
                }
            }
        }
    }

    var submitButton: some View {
        Button(action: createPost) {
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .black))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gold)
                    .cornerRadius(12)
            } else {
                Text(lang == "es" ? "Publicar Entrada" : "Post Ticket")
                    .font(.headline)
                    .foregroundColor(.black)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.gold)
                    .cornerRadius(12)
            }
        }
        .disabled(isLoading || selectedTicketId == nil || price.isEmpty || availableTickets.isEmpty)
    }

    var errorTextView: some View {
        Group {
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.footnote)
                    .padding(.top, 4)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: errorMessage)
            }
        }
    }

    struct CustomTextField: View {
        let placeholder: String
        @Binding var text: String
        var keyboardType: UIKeyboardType = .default

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(placeholder)
                    .foregroundColor(.white.opacity(0.7))
                TextField("", text: $text)
                    .keyboardType(keyboardType)
                    .autocapitalization(.none)
                    .padding()
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(10)
                    .foregroundColor(.white)
            }
        }
    }

    // MARK: - Network

    func createPost() {
        guard let token = TokenManager.shared.getAccessToken(),
              let ticketId = selectedTicketId,
              let url = URL(string: "https://backendevent-etce.onrender.com/resale/create"),
              let priceValue = Double(price) else {
            withAnimation { errorMessage = "Invalid input" }
            return
        }

        isLoading = true
        errorMessage = ""

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "ticketId": ticketId,
            "price": priceValue,
            "title": title
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: request) { data, response, _ in
            DispatchQueue.main.async {
                isLoading = false
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    // ✅ hide immediately in UI
                    if let idx = viewModel.tickets.firstIndex(where: { $0.id == ticketId }) {
                        viewModel.tickets[idx].resold = true
                    }
                    onPostCreated()
                    dismiss()
                } else {
                    withAnimation {
                        errorMessage = lang == "es" ? "No se pudo crear la publicación" : "Failed to create post"
                    }
                }

            }
        }.resume()
    }
}
