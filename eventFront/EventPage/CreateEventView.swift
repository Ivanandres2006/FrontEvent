import SwiftUI
import PhotosUI
import CoreLocation

struct CreateEventView: View {
    @AppStorage("selectedLanguage") var lang: String = "en"
    @EnvironmentObject var userSession: UserSession

    @Environment(\.dismiss) var dismiss
    @Binding var allEvents: [Event]
    @Binding var selectedTab: Int // ✅ Add this

    // Form State
    @State private var step = 0
    @Namespace var animation

    // Event Info
    @State private var title = ""
    @State private var description = ""
    @State private var date = Date()

    // Location Info
    @State private var location = ""
    @State private var address = ""
    @State private var state = "Illinois"
    @State private var country = "USA"
    @State private var latitude: Double? = nil
    @State private var longitude: Double? = nil

    // Image
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var previewImage: UIImage? = nil
    @State private var imageUrl = ""

    // Tickets
    @State private var ticketTiers: [TicketTierRequest] = []
    @State private var tierName = ""
    @State private var tierPrice = ""
    @State private var tierQuantity = ""
    @State private var tierOrder = ""
    @State private var showTierOptions = false
    @State private var tierStartDate = Date()
    @State private var tierEndDate = Date()
    
    // Others
    @State private var isLoading = false
    @State private var message = ""
    @State private var newEvent: Event? = nil
    @State private var showSuccessOverlay = false
    @State private var showSpinner = true
    
    @State private var eventType: String? = nil // "event" or "reunion"
    @State private var showTypeInfo = false
    
    // Reunion Info
    @State private var reunionBudgetGoal = ""
    @State private var budgetPurpose = ""
    @State private var reunionGuests: [ReunionGuest] = []
    @State private var newGuestName = ""
    @State private var newGuestEmail = ""
    @State private var zelleInfo = ""
    
    @State private var showContactPopup = false
    @State private var showZelleFields = false
    
    @State private var pagoMovilPhone = ""
    @State private var pagoMovilCi = ""
    @State private var pagoMovilBank = ""
    @State private var allowPagoMovil = false
    
    @State private var allowCash = false
    @State private var cashNote = ""

    @State private var zelleEmail = ""
    @State private var zellePhone = ""
    
    @State private var adminChatRoomId: Int? = nil
    @State private var showAdminChat = false
    
    @State private var usernameSearch = ""
    @State private var matchingUsernames: [String] = []
    @State private var selectedUsername = ""
    
    @State private var isSearching = false
    @State private var searchError = ""
    @FocusState private var isUsernameFocused: Bool



    let states = ["Alabama", "Alaska", "Arizona", "Arkansas", "California", "Colorado", "Connecticut", "Delaware", "Florida", "Georgia", "Hawaii", "Idaho", "Illinois", "Indiana", "Iowa", "Kansas", "Kentucky", "Louisiana", "Maine", "Maryland", "Massachusetts", "Michigan", "Minnesota", "Mississippi", "Missouri", "Montana", "Nebraska", "Nevada", "New Hampshire", "New Jersey", "New Mexico", "New York", "North Carolina", "North Dakota", "Ohio", "Oklahoma", "Oregon", "Pennsylvania", "Rhode Island", "South Carolina", "South Dakota", "Tennessee", "Texas", "Utah", "Vermont", "Virginia", "Washington", "West Virginia", "Wisconsin", "Wyoming"]

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                if eventType == nil {
                    eventTypePicker
                } else {
                    VStack {
                        // Step Indicators
                        HStack(spacing: 12) {
                            stepCircle(index: 0, icon: "text.bubble")
                            stepCircle(index: 1, icon: "mappin.and.ellipse")
                            stepCircle(index: 2, icon: "photo.on.rectangle")
                            stepCircle(index: 3, icon: "ticket.fill")
                        }
                        .padding(.top, 20)

                        TabView(selection: $step) {
                            stepEventInfo.tag(0)
                            stepLocation.tag(1)
                            stepImage.tag(2)

                            if eventType == "event" {
                                stepTickets.tag(3)
                            } else if eventType == "reunion" {
                                stepReunionBudget.tag(3)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .animation(.easeInOut, value: step)

                        Spacer()

                        Button(action: {
                            if step < 3 {
                                step += 1
                            } else {
                                geocodeAndCreateEvent()
                            }
                        }) {
                            HStack {
                                if isLoading {
                                    ProgressView().tint(.black)
                                } else {
                                    Text(step < 3
                                         ? (lang == "es" ? "Siguiente" : "Next")
                                         : (lang == "es" ? "Crear Evento" : "Create Event"))
                                    .bold()
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.gold)
                                    .foregroundColor(.black)
                                    .cornerRadius(14)
                                }
                            }
                        }
                        .padding()
                        .disabled(isLoading || (step == 0 && title.isEmpty))
                    }
                }
            }
            .fullScreenCover(isPresented: $showAdminChat) {
                if let roomId = adminChatRoomId {
                    ChatView(
                        chatSummary: ChatRoomSummary(
                            chatRoomId: roomId,
                            resalePostId: nil,
                            title: "Admin Chat",
                            sellerName: "Admin",
                            unreadMessages: nil,
                            otherUsername: userSession.username,
                            buyerId: userSession.userId,
                            otherUserId: nil,
                            eventId: nil,
                            type: "Direct" // ✅ required
                        ),
                        currentUserId: userSession.userId,
                    )
                }
            }
            .onChange(of: showAdminChat) { isPresented in
                if !isPresented {
                    refreshUserSession()
                }
            }
            .onChange(of: selectedItem) {
                uploadSelectedImage()
            }
        }
        .onDisappear {
            resetForm()
        }
        .overlay(
            Group {
                if showSuccessOverlay {
                    ZStack {
                        Color.black.opacity(0.5)
                            .ignoresSafeArea()
                        VStack(spacing: 16) {
                            if showSpinner {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.5)
                                    .transition(.opacity)
                            }
                            Text(lang == "es" ? "¡Evento creado!" : "Event Created!")
                                .font(.title2.bold())
                                .foregroundColor(.white)
                        }
                        .padding()
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(16)
                        .transition(.opacity)
                    }
                }
            }
        )
    }

    // MARK: - Step Indicators
    func stepCircle(index: Int, icon: String) -> some View {
        Circle()
            .fill(step >= index ? Color.gold : Color.white.opacity(0.2))
            .frame(width: 40, height: 40)
            .overlay(Image(systemName: icon).foregroundColor(.black))
            .animation(.easeInOut, value: step)
    }

    var stepEventInfo: some View {
        VStack(spacing: 24) {
            Text(lang == "es" ? "🎯 Información del evento" : "🎯 Event Info")
                .font(.title2.bold())
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top)

            CustomInputField(icon: "textformat", placeholder: lang == "es" ? "Título del evento" : "Event Title", text: $title)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .foregroundColor(.white.opacity(0.7))
                    Text(lang == "es" ? "Descripción" : "Description")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.subheadline)
                }

                ZStack(alignment: .topLeading) {
                    if description.isEmpty {
                        Text(lang == "es" ? "Escribe una descripción..." : "Write a description...")
                            .foregroundColor(.gray)
                            .padding(.horizontal, 12)
                            .padding(.top, 12)
                    }

                    TextEditor(text: $description)
                        .frame(height: 100)
                        .padding(12)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(12)
                        .foregroundColor(.white)
                        .scrollContentBackground(.hidden)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .foregroundColor(.white.opacity(0.7))
                    Text(lang == "es" ? "Fecha y hora del evento" : "Event Date & Time")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.subheadline)
                }

                DatePicker("", selection: $date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white.opacity(0.10))
                    .cornerRadius(12)
                    .foregroundColor(.white)
            }

            Spacer()
        }
        .padding(.horizontal)
    }
    
    var eventTypePicker: some View {
        VStack(spacing: 32) {
            Text(lang == "es" ? "¿Qué deseas crear?" : "What do you want to create?")
                .font(.title.bold())
                .foregroundColor(.white)
                .padding(.top, 60)

            HStack(spacing: 20) {
                eventTypeButton(
                    title: lang == "es" ? "Evento" : "Event",
                    icon: "ticket.fill",
                    description: lang == "es" ? "Vende entradas y gestiona asistentes." : "Sell tickets and manage attendees.",
                    type: "event"
                )
                eventTypeButton(
                    title: lang == "es" ? "Reunión" : "Reunion",
                    icon: "person.3.fill",
                    description: lang == "es" ? "Gratis. Comparte presupuesto y organiza juntos." : "Free. Split budget and plan together.",
                    type: "reunion"
                )
            }
            .padding(.horizontal)
        }
        .overlay(
            Group {
                if showContactPopup {
                    ZStack {
                        Color.black.opacity(0.6).ignoresSafeArea()

                        VStack(spacing: 24) {
                            Text(lang == "es" ? "Contáctanos antes de crear un evento" : "Contact us before creating an event")
                                .font(.headline)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.white)

                            Button {
                                startChatWithAdmin(currentUserId: userSession.userId)
                            } label: {
                                Label(lang == "es" ? "Chatear en la App" : "Chat in App", systemImage: "message")
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color.gold)
                                    .foregroundColor(.black)
                                    .cornerRadius(12)
                            }

                            Button {
                                if let url = URL(string: "mailto:email@example.com") {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                Label(lang == "es" ? "Enviar Email" : "Send Email", systemImage: "envelope")
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color.white.opacity(0.1))
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }

                            Button(action: {
                                showContactPopup = false
                            }) {
                                Text(lang == "es" ? "Cancelar" : "Cancel")
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                        .padding()
                        .background(Color.black.opacity(0.95))
                        .cornerRadius(20)
                        .padding(.horizontal, 40)
                    }
                }
            }
        )
    }
    
    var stepReunionBudget: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(lang == "es" ? "💰 Presupuesto de la Reunión" : "💰 Reunion Budget")
                    .font(.title.bold())
                    .foregroundColor(.white)

                // Budget Amount
                CustomInputField(
                    icon: "dollarsign.circle",
                    placeholder: lang == "es" ? "Presupuesto total" : "Total Budget ($)",
                    text: $reunionBudgetGoal,
                    keyboard: .decimalPad
                )

                // Purpose
                CustomInputField(
                    icon: "text.bubble",
                    placeholder: lang == "es" ? "¿Para qué es el presupuesto?" : "What's the budget for?",
                    text: $budgetPurpose
                )

                // Zelle or Payment Info
                ZelleToggleView(
                    showFields: $showZelleFields,
                    zelleEmail: $zelleEmail,
                    zellePhone: $zellePhone,
                    lang: lang
                )

                Divider().background(Color.white.opacity(0.3))

                // Guest List Section
                Text(lang == "es" ? "👥 Invitados" : "👥 Guests")
                    .font(.headline)
                    .foregroundColor(.white)

                VStack(alignment: .leading, spacing: 10) {
                    TextField(lang == "es" ? "Buscar por nombre de usuario" : "Search by username", text: $usernameSearch)
                        .focused($isUsernameFocused)
                        .onSubmit {
                            if let first = matchingUsernames.first {
                                selectedUsername = first
                                newGuestName = first
                                // 👇 Don't clear the search now — leave it to allow trying other names
                            }
                        }
                        .onChange(of: usernameSearch) { _ in
                            fetchUsernameSuggestions()
                        }
                        .padding()
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(10)
                        .foregroundColor(.white)
                        .submitLabel(.done) // shows "Done" on keyboard

                    // Show selected username as confirmation
                    if !selectedUsername.isEmpty {
                        Text("✅ \(selectedUsername)")
                            .foregroundColor(.green)
                            .font(.caption)
                    }

                    if isSearching {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else if !matchingUsernames.isEmpty {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(matchingUsernames, id: \.self) { username in
                                    Button(action: {
                                        selectedUsername = username
                                        newGuestName = username
                                        usernameSearch = username
                                        // 👇 Keep suggestions visible
                                        isUsernameFocused = true
                                    }) {
                                        HStack {
                                            Text(username)
                                                .foregroundColor(.white)
                                            Spacer()
                                        }
                                        .padding(.vertical, 8)
                                        .padding(.horizontal)
                                        .background(username == selectedUsername ? Color.white.opacity(0.1) : Color.clear)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 150)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                    } else if !usernameSearch.isEmpty {
                        Text(lang == "es" ? "No se encontraron coincidencias." : "No matches found.")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }

                Button {
                    guard !selectedUsername.isEmpty else { return }
                    let guest = ReunionGuest(
                        username: selectedUsername,
                        name: newGuestName, // ← usually the same
                        email: newGuestEmail,
                        paid: false,
                        attending: false
                    )
                    reunionGuests.append(guest)
                    newGuestName = ""
                    newGuestEmail = ""
                    selectedUsername = ""
                    usernameSearch = ""
                } label: {
                    Label(lang == "es" ? "Agregar Invitado" : "Add Guest", systemImage: "plus.circle.fill")
                        .foregroundColor(.gold)
                        .padding(.top, 4)
                }

                // List of Guests
                ForEach(reunionGuests) { guest in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(guest.name)
                                .foregroundColor(.white)
                                .font(.body.bold())
                            if !guest.email.isEmpty {
                                Text(guest.email)
                                    .foregroundColor(.white.opacity(0.6))
                                    .font(.caption)
                            }
                        }

                        Spacer()

                        Button(action: {
                            if let index = reunionGuests.firstIndex(where: { $0.id == guest.id }) {
                                reunionGuests[index].paid.toggle()
                            }
                        }) {
                            Label(
                                guest.paid ? (lang == "es" ? "Pagado" : "Paid") : (lang == "es" ? "Pendiente" : "Pending"),
                                systemImage: guest.paid ? "checkmark.seal.fill" : "hourglass"
                            )
                            .foregroundColor(guest.paid ? .green : .orange)
                            .padding(6)
                            .background(Color.white.opacity(0.07))
                            .cornerRadius(8)
                        }

                        Button(action: {
                            reunionGuests.removeAll { $0.id == guest.id }
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                                .padding(.leading, 4)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(12)
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal)
        }
    }



    var stepLocation: some View {
        VStack(spacing: 20) {
            Text(lang == "es" ? "📍 Ubicación" : "📍 Location")
                .font(.title.bold())
                .foregroundColor(.white)

            CustomInputField(
                icon: "mappin.and.ellipse",
                placeholder: lang == "es" ? "Ciudad / Lugar" : "City / Venue",
                text: $location
            )

            CustomInputField(
                icon: "house",
                placeholder: lang == "es" ? "Dirección" : "Street Address",
                text: $address
            )

            CustomInputField(
                icon: "globe",
                placeholder: lang == "es" ? "País" : "Country",
                text: $country
            )

            CustomDropdown(
                label: lang == "es" ? "Seleccionar Estado" : "Select State",
                selection: $state,
                options: states
            )
        }
        .padding(.horizontal)
    }

    var stepImage: some View {
        VStack(spacing: 20) {
            Text(lang == "es" ? "📸 Imagen del Evento" : "📸 Event Image")
                .font(.title.bold())
                .foregroundColor(.white)

            if let previewImage = previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 200)
                    .cornerRadius(16)
                    .shadow(radius: 10)
            }

            PhotosPicker(selection: $selectedItem, matching: .images) {
                Text(lang == "es" ? "Seleccionar Imagen" : "Select Image")
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gold)
                    .foregroundColor(.black)
                    .cornerRadius(12)
            }
        }
        .padding(.horizontal)
    }

    var stepTickets: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text(lang == "es" ? "🎟 Niveles de Entradas" : "🎟 Ticket Tiers")
                    .font(.title.bold())
                    .foregroundColor(.white)

                // Input Section (moved to subview)
                TierInputView(
                    tierName: $tierName,
                    tierPrice: $tierPrice,
                    tierQuantity: $tierQuantity,
                    tierOrder: $tierOrder,
                    tierStartDate: $tierStartDate,
                    tierEndDate: $tierEndDate,
                    showTierOptions: $showTierOptions,
                    lang: lang
                )

                // Add Tier Button
                Button(action: {
                    guard let price = Double(tierPrice),
                          let qty = Int(tierQuantity),
                          let order = Int(tierOrder),
                          !tierName.isEmpty else {
                        return
                    }

                    let newTier = TicketTierRequest(
                        name: tierName,
                        price: price,
                        quantity: qty,
                        order: order,
                        startTime: showTierOptions ? tierStartDate : nil,
                        endTime: showTierOptions ? tierEndDate : nil
                    )

                    ticketTiers.append(newTier)

                    // Reset fields
                    tierName = ""
                    tierPrice = ""
                    tierQuantity = ""
                    tierOrder = ""
                    showTierOptions = false
                }) {
                    Text(lang == "es" ? "Agregar Nivel" : "Add Tier")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gold)
                        .foregroundColor(.black)
                        .cornerRadius(12)
                }

                Divider().background(Color.white.opacity(0.2))

                // Zelle input toggle
                ZelleToggleView(
                    showFields: $showZelleFields,
                    zelleEmail: $zelleEmail,
                    zellePhone: $zellePhone,
                    lang: lang
                )
                
                if country.lowercased() == "venezuela" {
                    Divider().background(Color.white.opacity(0.3))

                    Toggle(lang == "es" ? "💳 Aceptar Pago Móvil" : "💳 Accept Pago Móvil", isOn: $allowPagoMovil)
                        .toggleStyle(SwitchToggleStyle(tint: .gold))
                        .foregroundColor(.white)

                    if allowPagoMovil {
                        CustomInputField(
                            icon: "phone",
                            placeholder: lang == "es" ? "Teléfono Pago Móvil" : "Pago Móvil Phone",
                            text: $pagoMovilPhone
                        )
                        CustomInputField(
                            icon: "idcard",
                            placeholder: lang == "es" ? "Cédula de Identidad" : "National ID (CI)",
                            text: $pagoMovilCi
                        )
                        CustomInputField(
                            icon: "building.2",
                            placeholder: lang == "es" ? "Banco" : "Bank",
                            text: $pagoMovilBank
                        )
                    }

                    Toggle(lang == "es" ? "💵 Aceptar Efectivo" : "💵 Accept Cash", isOn: $allowCash)
                        .toggleStyle(SwitchToggleStyle(tint: .gold))
                        .foregroundColor(.white)

                    if allowCash {
                        CustomInputField(
                            icon: "text.bubble",
                            placeholder: lang == "es"
                                ? "Nota para mostrar al comprador (ej: pagar en la puerta)"
                                : "Note for the buyer (e.g. pay at the door)",
                            text: $cashNote
                        )
                    }
                }

                // Preview List (moved to subview)
                TierPreviewList(
                    ticketTiers: ticketTiers,
                    lang: lang,
                    formattedDate: formattedDate,
                    removeTier: { id in
                        ticketTiers.removeAll { $0.id == id }
                    }
                )

                Spacer(minLength: 100)
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
    }



    // MARK: - Logic
    func geocodeAndCreateEvent() {
        isLoading = true
        let full = "\(address), \(state), \(country)"
        CLGeocoder().geocodeAddressString(full) { placemarks, error in
            if let placemark = placemarks?.first {
                latitude = placemark.location?.coordinate.latitude
                longitude = placemark.location?.coordinate.longitude
            }
            createEvent()
        }
    }
    
    func eventTypeButton(title: String, icon: String, description: String, type: String) -> some View {
        Button {
            if type == "event" {
                if userSession.canCreateEvent {
                    eventType = type
                } else {
                    showContactPopup = true
                }
            } else {
                eventType = type // reunions go straight to form
            }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 36))
                    .foregroundColor(.gold)

                Text(title)
                    .font(.title3.bold())
                    .foregroundColor(.white)

                Text(description)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.08))
            .cornerRadius(18)
        }
    }



    func createEvent() {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/events") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let finalImageUrl = imageUrl.isEmpty ? "/default-event.jpg" : imageUrl

        var payload: [String: Any] = [
            "title": title,
            "description": description,
            "location": location,
            "state": state,
            "address": address,
            "country": country,
            "latitude": latitude ?? 0.0,
            "longitude": longitude ?? 0.0,
            "dateTime": ISO8601DateFormatter().string(from: date),
            "imageUrl": finalImageUrl,
            "type": eventType ?? "event",
            "ticketTiers": ticketTiers.map { tier in
                var dict: [String: Any] = [
                    "name": tier.name,
                    "price": tier.price,
                    "quantity": tier.quantity,
                    "order": tier.order
                ]
                if let start = tier.startTime {
                    dict["startTime"] = ISO8601DateFormatter().string(from: start)
                }
                if let end = tier.endTime {
                    dict["endTime"] = ISO8601DateFormatter().string(from: end)
                }
                return dict
            }
        ]

        // ✅ Add Zelle info if fields are visible and filled
        if showZelleFields, (!zelleEmail.isEmpty || !zellePhone.isEmpty) {
            payload["zelleEmail"] = zelleEmail
            payload["zellePhone"] = zellePhone
        }

        // ✅ Reunion-specific extras
        if eventType == "reunion" {
            payload["budgetGoal"] = Double(reunionBudgetGoal) ?? 0.0
            payload["budgetPurpose"] = budgetPurpose
            payload["guests"] = reunionGuests.map { guest in
                return [
                    "username": guest.username, // 👈 This is actually the username
                    "paid": guest.paid
                ]
            }
        }
        
        // ✅ Add Venezuela-specific payment info if applicable
        if country.lowercased() == "venezuela" {
            payload["allowPagoMovil"] = allowPagoMovil
            payload["allowCash"] = allowCash

            if allowPagoMovil {
                payload["pagoMovilPhone"] = pagoMovilPhone
                payload["pagoMovilCi"] = pagoMovilCi
                payload["pagoMovilBank"] = pagoMovilBank
            }

            if allowCash {
                payload["cashNote"] = cashNote
            }
        }


        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false

                if let error = error {
                    print("❌ POST /events failed: \(error)")
                    return
                }

                if let httpResponse = response as? HTTPURLResponse {
                    print("📨 POST /events status: \(httpResponse.statusCode)")
                }

                guard let data = data else {
                    print("❌ No data from POST /events")
                    return
                }

                if let raw = String(data: data, encoding: .utf8) {
                    print("📦 Raw response: \(raw)")
                }

                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let id = json["id"] as? Int {
                    print("✅ Created event with ID: \(id)")
                    fetchEventById(id)
                } else {
                    print("❌ Failed to decode event ID from response")
                }
            }
        }.resume()
    }
    
    func fetchUsernameSuggestions() {
        guard !usernameSearch.isEmpty else {
            matchingUsernames = []
            isSearching = false
            searchError = ""
            return
        }

        let query = usernameSearch.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlStr = "https://backendevent-etce.onrender.com/user/search-usernames?q=\(query)"
        guard let url = URL(string: urlStr),
              let token = TokenManager.shared.getAccessToken() else { return }

        isSearching = true
        searchError = ""

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isSearching = false

                if let error = error {
                    print("❌ Username search error:", error)
                    searchError = "Network error. Try again."
                    return
                }

                guard let data = data else {
                    searchError = "No data returned."
                    return
                }

                if let usernames = try? JSONDecoder().decode([String].self, from: data) {
                    matchingUsernames = usernames
                    searchError = ""
                } else {
                    matchingUsernames = []
                    searchError = "Failed to decode suggestions."
                }
            }
        }.resume()
    }

    
    func refreshUserSession() {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/user/me") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            DispatchQueue.main.async {
                let first = json["firstName"] as? String ?? ""
                let last = json["lastName"] as? String ?? ""
                let username = json["username"] as? String ?? ""
                let createEvents = json["canCreateEvents"] as? Bool ?? false
                userSession.firstName = first
                userSession.lastName = last
                userSession.username = username
                userSession.fullName = "\(first) \(last)"
                userSession.canCreateEvent = createEvents
                userSession.email = json["email"] as? String ?? ""
                userSession.userId = json["id"] as? Int ?? 0
                userSession.role = (json["role"] as? String ?? "USER").uppercased()
                if let eventIds = json["promotedEvents"] as? [Int] {
                    userSession.promotedEvents = eventIds
                }
            }
        }.resume()
    }

    
    func fetchEventById(_ id: Int) {
        
        guard let url = URL(string: "https://backendevent-etce.onrender.com/events/\(id)"),
              let token = TokenManager.shared.getAccessToken() else {
            print("❌ Invalid URL or missing token")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Request failed with error: \(error.localizedDescription)")
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                print("🌐 Response status: \(httpResponse.statusCode)")
            }

            guard let data = data else {
                print("❌ No data received")
                return
            }

            if let raw = String(data: data, encoding: .utf8) {
                print("📦 Raw JSON: \(raw)")
            }

            do {
                let event = try JSONDecoder().decode(Event.self, from: data)
                DispatchQueue.main.async {
                    print("✅ Decoded event: \(event.title)")
                    self.allEvents.append(event)

                    self.isLoading = false
                    self.showSuccessOverlay = true
                    self.showSpinner = true

                    // Remove spinner after 1 second
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        withAnimation {
                            self.showSpinner = false
                        }
                    }

                    // Switch to tab after 1.2 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation {
                            self.selectedTab = 0
                        }
                    }

                    // Hide overlay and reset after 2.0 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation {
                            self.showSuccessOverlay = false
                        }
                        self.resetForm()
                    }
                }
            } catch {
                print("❌ Failed to decode Event: \(error)")
            }
        }.resume()
    }
    
    func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }


    func uploadSelectedImage() {
        guard let item = selectedItem else { return }

        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                previewImage = image
                await uploadImageToServer(imageData: data)
            }
        }
    }
    
    func startChatWithAdmin(currentUserId: Int) {
        let cacheKey = "adminChatRoomId_\(currentUserId)"

        // ✅ CASE 1: Reuse if already created
        if let cachedId = UserDefaults.standard.value(forKey: cacheKey) as? Int {
            self.adminChatRoomId = cachedId
            self.showAdminChat = true
            print("🔁 Reusing cached adminChatRoomId:", cachedId)
            return
        }

        // ✅ CASE 2: Create new if not cached
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/chat/start-with-admin") else {
            print("❌ Missing token or invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [:])

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Network error: \(error)")
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else { return }

            if httpResponse.statusCode >= 400 {
                print("❌ Server error: \(httpResponse.statusCode)")
                UserDefaults.standard.removeObject(forKey: cacheKey)
                return
            }

            guard let data = data else {
                print("❌ No response data")
                return
            }

            do {
                let decoded = try JSONDecoder().decode(ChatRoomIdResponse.self, from: data)
                DispatchQueue.main.async {
                    self.adminChatRoomId = decoded.chatRoomId
                    self.showAdminChat = true
                    UserDefaults.standard.set(decoded.chatRoomId, forKey: cacheKey)
                    print("✅ New admin chat created and cached:", decoded.chatRoomId)
                }
            } catch {
                print("❌ Failed to decode chatRoomId:", error)
                UserDefaults.standard.removeObject(forKey: cacheKey)
            }
        }.resume()
    }







    func uploadImageToServer(imageData: Data) async {
        guard let url = URL(string: "https://backendevent-etce.onrender.com/events/upload-image"),
              let token = TokenManager.shared.getAccessToken() else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"event.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let response = try? JSONDecoder().decode([String: String].self, from: data),
               let urlString = response["imageUrl"] {
                imageUrl = urlString
            }
        } catch {
            print("Upload error: \(error)")
        }
    }

    func resetForm() {
        step = 0
        title = ""
        description = ""
        date = Date()
        location = ""
        address = ""
        state = "Illinois"
        country = "USA"
        latitude = nil
        longitude = nil
        selectedItem = nil
        previewImage = nil
        imageUrl = ""
        ticketTiers = []
        tierName = ""
        tierPrice = ""
        tierQuantity = ""
        tierOrder = ""
        showTierOptions = false
        tierStartDate = Date()
        tierEndDate = Date()
        message = ""
        isLoading = false
        newEvent = nil

        // ✅ Reset event type so user sees the picker again
        eventType = nil
        showZelleFields = false
        zelleEmail = ""
        zellePhone = ""
        reunionBudgetGoal = ""
        budgetPurpose = ""
        reunionGuests = []
        newGuestName = ""
        newGuestEmail = ""
    }
}

struct TierPreviewList: View {
    var ticketTiers: [TicketTierRequest]
    var lang: String
    var formattedDate: (Date) -> String
    var removeTier: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(ticketTiers.sorted(by: { $0.order < $1.order })) { tier in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tier.name)
                            .font(.headline)
                            .foregroundColor(.white)

                        Text(
                            lang == "es"
                                ? "$\(tier.price, specifier: "%.2f") • \(tier.quantity) boletos • Orden: \(tier.order)"
                                : "$\(tier.price, specifier: "%.2f") • \(tier.quantity) tickets • Order: \(tier.order)"
                        )
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))

                        if let start = tier.startTime, let end = tier.endTime {
                            Text("⏰ \(formattedDate(start)) - \(formattedDate(end))")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }

                    Spacer()

                    Button(action: {
                        removeTier(tier.id)
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                            .padding(.leading, 8)
                    }
                }
                .padding()
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
            }
        }
    }
}


struct ZelleToggleView: View {
    @Binding var showFields: Bool
    @Binding var zelleEmail: String
    @Binding var zellePhone: String
    var lang: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: {
                withAnimation {
                    showFields.toggle()
                }
            }) {
                Label(
                    showFields
                        ? (lang == "es" ? "Ocultar Zelle" : "Hide Zelle Info")
                        : (lang == "es" ? "💸 ¿Aceptar contribuciones por Zelle?" : "💸 Accept Zelle Contributions?"),
                    systemImage: showFields ? "chevron.up.circle.fill" : "chevron.right.circle"
                )
                .foregroundColor(.white)
                .padding(.top, 8)
            }

            if showFields {
                VStack(spacing: 12) {
                    CustomInputField(
                        icon: "envelope",
                        placeholder: lang == "es" ? "Email de Zelle" : "Zelle Email",
                        text: $zelleEmail
                    )
                    CustomInputField(
                        icon: "phone.fill",
                        placeholder: lang == "es" ? "Teléfono de Zelle" : "Zelle Phone Number",
                        text: $zellePhone
                    )
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

struct TierInputView: View {
    @Binding var tierName: String
    @Binding var tierPrice: String
    @Binding var tierQuantity: String
    @Binding var tierOrder: String
    @Binding var tierStartDate: Date
    @Binding var tierEndDate: Date
    @Binding var showTierOptions: Bool
    var lang: String

    var body: some View {
        Group {
            CustomInputField(
                icon: "tag",
                placeholder: lang == "es" ? "Nombre del Nivel" : "Tier Name",
                text: $tierName
            )

            CustomInputField(
                icon: "dollarsign.circle",
                placeholder: lang == "es" ? "Precio" : "Price",
                text: $tierPrice,
                keyboard: .decimalPad
            )

            CustomInputField(
                icon: "number",
                placeholder: lang == "es" ? "Cantidad" : "Quantity",
                text: $tierQuantity,
                keyboard: .numberPad
            )

            VStack(alignment: .leading, spacing: 4) {
                CustomInputField(
                    icon: "list.number",
                    placeholder: lang == "es" ? "Orden del Nivel" : "Tier Order",
                    text: $tierOrder,
                    keyboard: .numberPad
                )

                Text(
                    lang == "es"
                        ? "Ingresa un número. Los números más bajos se desbloquean primero (por ejemplo, 1 para Preventa, 2 para Entrada General)."
                        : "Enter a number. Lower numbers unlock first (e.g. 1 for Early Bird, 2 for General Entry)."
                )
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
            }

            Button(action: {
                withAnimation {
                    showTierOptions.toggle()
                }
            }) {
                HStack {
                    Image(systemName: showTierOptions ? "chevron.down.circle.fill" : "chevron.right.circle")
                    Text(lang == "es" ? "Más Opciones" : "More Options")
                }
                .foregroundColor(.white.opacity(0.8))
            }

            if showTierOptions {
                VStack(alignment: .leading, spacing: 8) {
                    Text(lang == "es" ? "Hora de Inicio" : "Start Time")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    DatePicker(lang == "es" ? "Inicio" : "Start", selection: $tierStartDate)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(10)

                    Text(lang == "es" ? "Hora de Fin" : "End Time")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    DatePicker(lang == "es" ? "Fin" : "End", selection: $tierEndDate)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(10)
                }
            }
        }
    }
}

struct ChatRoomIdResponse: Decodable {
    let chatRoomId: Int
}
    
    struct CustomDropdown: View {
        var label: String
        @Binding var selection: String
        var options: [String]

        @State private var isExpanded = false

        var body: some View {
            VStack(spacing: 4) {
                Button(action: {
                    withAnimation { isExpanded.toggle() }
                }) {
                    HStack {
                        Text(selection.isEmpty ? label : selection)
                            .foregroundColor(selection.isEmpty ? .gray : .white)
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding()
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(12)
                }

                if isExpanded {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(options, id: \.self) { option in
                                Button(action: {
                                    selection = option
                                    isExpanded = false
                                }) {
                                    Text(option)
                                        .foregroundColor(.white)
                                        .padding(.vertical, 8)
                                        .padding(.horizontal)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(selection == option ? Color.white.opacity(0.1) : Color.clear)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(12)
                    .shadow(radius: 4)
                }
            }
        }
    }


    

