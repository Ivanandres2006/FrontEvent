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
    @State private var state = "State"
    @State private var country = "United States"
    @State private var latitude: Double? = nil
    @State private var longitude: Double? = nil
    let countries = Locale.isoRegionCodes.compactMap { Locale.current.localizedString(forRegionCode: $0) }.sorted()
    @State private var showGooglePlacesAutocomplete = false

    // Image
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var previewImage: UIImage? = nil
    @State private var showImagePicker = false // Add this to your @State vars if not present
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
    @State private var showFieldError = false
    @State private var fieldErrorMessage = ""

    
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
    
    @State private var listOnly = false
    @State private var guestListFilename = ""
    @State private var guestListUrl = ""
    @State private var showFileImporter = false
    

    @State private var addressSuggestions: [GPlacePrediction] = []
    @State private var isAddressSearching = false
    @FocusState private var isAddressFieldFocused: Bool // New: for keyboard control


    @State private var addressQuery = ""

    


    let countryStates: [String: [String]] = [
        "United States": [
            "Alabama", "Alaska", "Arizona", "Arkansas", "California", "Colorado", "Connecticut", "Delaware",
            "Florida", "Georgia", "Hawaii", "Idaho", "Illinois", "Indiana", "Iowa", "Kansas", "Kentucky",
            "Louisiana", "Maine", "Maryland", "Massachusetts", "Michigan", "Minnesota", "Mississippi",
            "Missouri", "Montana", "Nebraska", "Nevada", "New Hampshire", "New Jersey", "New Mexico",
            "New York", "North Carolina", "North Dakota", "Ohio", "Oklahoma", "Oregon", "Pennsylvania",
            "Rhode Island", "South Carolina", "South Dakota", "Tennessee", "Texas", "Utah", "Vermont",
            "Virginia", "Washington", "West Virginia", "Wisconsin", "Wyoming"
        ],
        "Venezuela": [
            "Amazonas", "Anzoátegui", "Apure", "Aragua", "Barinas", "Bolívar", "Carabobo", "Cojedes",
            "Delta Amacuro", "Distrito Capital", "Falcón", "Guárico", "Lara", "Mérida", "Miranda", "Monagas",
            "Nueva Esparta", "Portuguesa", "Sucre", "Táchira", "Trujillo", "La Guaira", "Yaracuy", "Zulia"
        ]
    ]
    
    var statesForSelectedCountry: [String] {
        countryStates[country] ?? []
    }



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
                            stepCircle(index: 2, icon: "ticket.fill")
                        }
                        .padding(.top, 20)

                        TabView(selection: $step) {
                            stepEventInfo.tag(0)
                            stepLocation.tag(1)

                            if eventType == "event" {
                                stepTickets.tag(2)
                            } else if eventType == "reunion" {
                                stepReunionBudget.tag(2)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .animation(.easeInOut, value: step)

                        Spacer()

                        Button(action: {
                            var shouldBlock = false
                            var message = ""

                            switch step {
                            case 0:
                                if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    shouldBlock = true
                                    message = lang == "es"
                                        ? "Por favor, ingresa el título del evento."
                                        : "Please enter the event title."
                                }
                            case 1:
                                // Validate location and address (choose which is required for you)
                                if location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    shouldBlock = true
                                    message = lang == "es"
                                        ? "Por favor, completa la ubicación del evento."
                                        : "Please enter the event location."
                                }
                            case 2:
                                if ticketTiers.isEmpty {
                                    shouldBlock = true
                                    message = lang == "es"
                                        ? "Agrega al menos un nivel de entrada."
                                        : "Add at least one ticket tier."
                                }
                                // (Optionally, if you want to force tierName when creating a new one)
                                // if tierName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { ... }
                            default:
                                break
                            }

                            if shouldBlock {
                                fieldErrorMessage = message
                                showFieldError = true
                                let generator = UINotificationFeedbackGenerator()
                                generator.notificationOccurred(.error)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                                    withAnimation { showFieldError = false }
                                }
                                return
                            }

                            // If valid, continue to next step or submit
                            if step < 2 {
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
                        .disabled(isLoading)
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
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.pdf]) { result in
                switch result {
                case .success(let url):
                    guestListFilename = url.lastPathComponent
                    uploadGuestListPdf(fileUrl: url)
                case .failure:
                    print("Failed to select file")
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
            ZStack {
                // Top animated error bar
                VStack {
                    if showFieldError {
                        Text(fieldErrorMessage)
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(Color.red.opacity(0.97))
                            .cornerRadius(12)
                            .padding(.horizontal, 18)
                            .shadow(radius: 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .zIndex(10)
                    }
                    Spacer()
                }
                // Fullscreen event created overlay
                if showSuccessOverlay {
                    ZStack {
                        // Dim background
                        Color.black.opacity(0.65)
                            .ignoresSafeArea()
                            .blur(radius: 2)

                        VStack(spacing: 22) {
                            // Animated checkmark with gold glow
                            ZStack {
                                Circle()
                                    .fill(Color.gold.opacity(0.16))
                                    .frame(width: 82, height: 82)
                                Circle()
                                    .stroke(Color.gold, lineWidth: 3)
                                    .frame(width: 74, height: 74)
                                    .shadow(color: .gold.opacity(0.7), radius: 12, y: 4)
                                Image(systemName: "checkmark.seal.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 46, height: 46)
                                    .foregroundColor(.gold)
                                    .shadow(color: .gold, radius: 8)
                            }
                            .scaleEffect(showSpinner ? 0.8 : 1.1)
                            .opacity(showSpinner ? 0.7 : 1.0)
                            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: showSpinner)

                            // Headline
                            Text(lang == "es" ? "¡Evento creado!" : "Event Created!")
                                .font(.title.bold())
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.21), radius: 4, y: 2)

                            // Subheadline or loading indicator
                            if showSpinner {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .gold))
                                    .scaleEffect(1.15)
                                    .padding(.top, 4)
                                    .transition(.opacity)
                            } else {
                                Text(lang == "es"
                                     ? "Tu evento está listo. Redirigiendo..."
                                     : "Your event is ready. Redirecting...")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                        .padding(.vertical, 36)
                        .padding(.horizontal, 30)
                        .background(
                            BlurView(style: .systemUltraThinMaterialDark)
                                .background(Color.black.opacity(0.28))
                        )
                        .cornerRadius(28)
                        .shadow(color: .gold.opacity(0.18), radius: 22, y: 8)
                        .padding(.horizontal, 26)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
        )
    }

    // MARK: - Step Indicators
    func fetchPlaceDetail(_ placeId: String) {
        let apiKey = "AIzaSyAsSjybISIywrdMNKMVrKrhgDIQdX1r4pA"
        let langParam = lang
        let urlString = "https://maps.googleapis.com/maps/api/place/details/json?place_id=\(placeId)&key=\(apiKey)&language=\(langParam)"
        guard let url = URL(string: urlString) else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = json["result"] as? [String: Any] else { return }
            DispatchQueue.main.async {
                if let geometry = result["geometry"] as? [String: Any],
                   let loc = geometry["location"] as? [String: Any],
                   let lat = loc["lat"] as? Double,
                   let lng = loc["lng"] as? Double {
                    latitude = lat
                    longitude = lng
                }
                if let addr = result["formatted_address"] as? String {
                    address = addr
                    addressQuery = addr
                }
                // Optional: Extract city if you want
                if let addressComponents = result["address_components"] as? [[String: Any]] {
                    if let cityComponent = addressComponents.first(where: { ($0["types"] as? [String])?.contains("locality") ?? false }) {
                        location = cityComponent["long_name"] as? String ?? ""
                    }
                }
            }
        }.resume()
    }

    
    func fetchAddressSuggestions(_ input: String) {
        guard !input.isEmpty else {
            addressSuggestions = []
            return
        }
        let apiKey = "AIzaSyAsSjybISIywrdMNKMVrKrhgDIQdX1r4pA"
        let langParam = lang
        let inputEncoded = input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://maps.googleapis.com/maps/api/place/autocomplete/json?input=\(inputEncoded)&key=\(apiKey)&language=\(langParam)"
        guard let url = URL(string: urlString) else { return }

        isAddressSearching = true
        URLSession.shared.dataTask(with: url) { data, _, _ in
            DispatchQueue.main.async {
                isAddressSearching = false
                guard let data = data else {
                    print("No data returned from Google Places")
                    addressSuggestions = []
                    return
                }

                // 👇👇👇 PRINT THE RAW RESPONSE
                print("Raw address suggestion response:")
                print(String(data: data, encoding: .utf8) ?? "nil")

                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    print("Failed to decode JSON")
                    addressSuggestions = []
                    return
                }
                print("Decoded JSON:", json)

                guard let predictions = json["predictions"] as? [[String: Any]] else {
                    print("No predictions key in JSON")
                    addressSuggestions = []
                    return
                }
                print("Predictions:", predictions)

                addressSuggestions = predictions.compactMap {
                    guard let desc = $0["description"] as? String, let placeId = $0["place_id"] as? String else { return nil }
                    return GPlacePrediction(description: desc, placeId: placeId)
                }
                print("addressSuggestions updated:", addressSuggestions)
            }
        }.resume()
    }


    
    func stepCircle(index: Int, icon: String) -> some View {
        Circle()
            .fill(step >= index ? Color.gold : Color.white.opacity(0.2))
            .frame(width: 40, height: 40)
            .overlay(Image(systemName: icon).foregroundColor(.black))
            .animation(.easeInOut, value: step)
    }

    var stepEventInfo: some View {
        ScrollView {
            VStack(spacing: 24) {
                // --- Cover Image Section ---
                PhotosPicker(
                    selection: $selectedItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(style: StrokeStyle(lineWidth: 2, dash: [8]))
                            .foregroundColor(Color.white.opacity(0.35))
                            .background(Color.white.opacity(0.04).cornerRadius(16))
                            .frame(height: 140)
                        
                        if let previewImage = previewImage {
                            Image(uiImage: previewImage)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 140)
                                .clipped()
                                .cornerRadius(16)
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: "camera")
                                    .font(.system(size: 28, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                                Text(lang == "es" ? "Agregar imagen de portada" : "Add cover image")
                                    .foregroundColor(.white.opacity(0.8))
                                    .font(.body)
                            }
                        }
                    }
                }
                
                // --- Event Info Fields ---
                Text(lang == "es" ? "🎯 Información del evento" : "🎯 Event Info")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                
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
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
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
                    title: lang == "es" ? "Reunion" : "Meeting",
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
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
    }



    var stepLocation: some View {
        VStack(spacing: 20) {
            Text(lang == "es" ? "📍 Ubicación" : "📍 Location")
                .font(.title.bold())
                .foregroundColor(.white)

            CustomInputField(
                icon: "mappin.and.ellipse",
                placeholder: lang == "es" ? "Ciudad" : "City",
                text: $location
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: "house")
                        .foregroundColor(.white.opacity(0.7))
                    TextField(
                        address.isEmpty ? (lang == "es" ? "Dirección (busca con Google)" : "Street Address (Search with Google)") : address,
                        text: $addressQuery,
                        prompt: Text(lang == "es" ? "Dirección (busca con Google)" : "Street Address (Search with Google)").foregroundColor(.gray)
                    )
                    .focused($isAddressFieldFocused)
                    .onChange(of: addressQuery) { newValue in
                        // Only search if user isn't clicking a suggestion (avoids double-fetch)
                        if newValue != address { fetchAddressSuggestions(newValue) }
                    }
                    .foregroundColor(.white)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    
                    // 🔥 X button to clear
                    if !addressQuery.isEmpty {
                        Button(action: {
                            addressQuery = ""
                            address = ""
                            addressSuggestions = []
                            isAddressFieldFocused = true
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding()
                .background(Color.white.opacity(0.08))
                .cornerRadius(12)
                
                // Spinner while searching
                if isAddressSearching {
                    HStack { Spacer(); ProgressView().padding(.vertical, 10); Spacer() }
                }
                // Dropdown
                else if !addressSuggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(addressSuggestions) { suggestion in
                            Button(action: {
                                addressQuery = suggestion.description
                                address = suggestion.description
                                addressSuggestions = []
                                fetchPlaceDetail(suggestion.placeId)
                                // Dismiss keyboard
                                isAddressFieldFocused = false
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            }) {
                                Text(suggestion.description)
                                    .foregroundColor(.white)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.white.opacity(0.1))
                            }
                        }
                    }
                    .background(Color.black.opacity(0.94))
                    .cornerRadius(12)
                    .shadow(radius: 4)
                    .padding(.top, -8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.bottom, 12)
            .onTapGesture {
                // Dismiss keyboard if tap outside
                isAddressFieldFocused = false
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }


            CustomDropdown(
                label: lang == "es" ? "Seleccionar país" : "Select Country",
                selection: $country,
                options: countries
            )

            if !statesForSelectedCountry.isEmpty {
                CustomDropdown(
                    label: lang == "es" ? "Seleccionar Estado" : "Select State",
                    selection: $state,
                    options: statesForSelectedCountry
                )
            } else {
                CustomInputField(
                    icon: "building.2",
                    placeholder: lang == "es" ? "Estado / Provincia" : "State / Province",
                    text: $state
                )
            }
        }
        .padding(.horizontal)
        .onChange(of: country) { _ in
            state = statesForSelectedCountry.first ?? ""
        }
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }

    

    var stepTickets: some View {
        ScrollView {
            VStack(spacing: 28) {
                Text(lang == "es" ? "🎟 Niveles de Entradas" : "🎟 Ticket Tiers")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 8)

                TicketTiersPreview // 👈
                Divider().background(Color.white.opacity(0.15))

                TierCreationSection // 👈
                Divider().background(Color.white.opacity(0.18))

                PaymentMethodsSection // 👈
                Divider().background(Color.white.opacity(0.16))

                MoreOptionsSection // 👈

                Spacer(minLength: 100)
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
    }

    private var TicketTiersPreview: some View {
        Group {
            if !ticketTiers.isEmpty {
                VStack(spacing: 16) {
                    ForEach(ticketTiers.indices, id: \.self) { idx in
                        let tier = ticketTiers[idx]
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(lang == "es" ? "Nivel" : "Tier") \(idx + 1): \(tier.name)")
                                    .font(.headline)
                                    .foregroundColor(.gold)
                                Text("$\(tier.price, specifier: "%.2f") • \(tier.quantity) \(lang == "es" ? "entradas" : "tickets")")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.8))
                                if let start = tier.startTime {
                                    Text("\(lang == "es" ? "Desde" : "From"): \(formattedDate(start))")
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.65))
                                }
                                if let end = tier.endTime {
                                    Text("\(lang == "es" ? "Hasta" : "Until"): \(formattedDate(end))")
                                        .font(.caption2)
                                        .foregroundColor(.white.opacity(0.65))
                                }
                            }
                            Spacer()
                            Button {
                                ticketTiers.remove(at: idx)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                    .font(.title2)
                            }
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(16)
                        .shadow(color: .black.opacity(0.16), radius: 7, y: 4)
                        .animation(.spring(), value: ticketTiers.count)
                    }
                }
            }
        }
    }

    private var TierCreationSection: some View {
        VStack(spacing: 10) {
            Text(lang == "es" ? "Crear nuevo nivel" : "Add New Tier")
                .font(.headline)
                .foregroundColor(.white)
            CustomInputField(
                icon: "ticket",
                placeholder: lang == "es" ? "Nombre del nivel" : "Tier Name",
                text: $tierName
            )
            CustomInputField(
                icon: "dollarsign.circle",
                placeholder: lang == "es" ? "Precio" : "Price (USD)",
                text: $tierPrice,
                keyboard: .decimalPad
            )
            CustomInputField(
                icon: "number",
                placeholder: lang == "es" ? "Cantidad" : "Quantity",
                text: $tierQuantity,
                keyboard: .numberPad
            )
            if showTierOptions {
                DatePicker(
                    lang == "es" ? "Inicio de venta" : "Sale Start",
                    selection: $tierStartDate,
                    
                    displayedComponents: [.date, .hourAndMinute]
                )
                .foregroundColor(.white)
                DatePicker(
                    lang == "es" ? "Fin de venta" : "Sale End",
                    selection: $tierEndDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .foregroundColor(.white)
            }
            Button {
                withAnimation { showTierOptions.toggle() }
            } label: {
                Text(showTierOptions
                    ? (lang == "es" ? "Ocultar Opciones" : "Hide Options")
                    : (lang == "es" ? "Opciones avanzadas" : "Advanced Options"))
                    .font(.caption)
                    .foregroundColor(.gold)
            }
            Button(action: {
                guard let price = Double(tierPrice),
                      let qty = Int(tierQuantity),
                      !tierName.isEmpty else { return }

                let newTier = TicketTierRequest(
                    name: tierName,
                    price: price,
                    quantity: qty,
                    order: ticketTiers.count,
                    startTime: showTierOptions ? tierStartDate : nil,
                    endTime: showTierOptions ? tierEndDate : nil
                )
                ticketTiers.append(newTier)
                tierName = ""
                tierPrice = ""
                tierQuantity = ""
                showTierOptions = false
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text(lang == "es" ? "Agregar Nivel" : "Add Tier")
                }
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.gold)
                .cornerRadius(14)
                .shadow(color: .gold.opacity(0.23), radius: 8, y: 2)
            }
            .padding(.top, 6)
        }
        .padding()
        .background(Color.white.opacity(0.08))
        .cornerRadius(18)
    }

    private var PaymentMethodsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(lang == "es" ? "Métodos de Pago" : "Payment Methods")
                .font(.headline)
                .foregroundColor(.white)

            ZelleToggleView(
                showFields: $showZelleFields,
                zelleEmail: $zelleEmail,
                zellePhone: $zellePhone,
                lang: lang
            )

            if country.lowercased() == "venezuela" {
                Divider().background(Color.white.opacity(0.2))
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
        }
        .padding()
        .background(Color.white.opacity(0.08))
        .cornerRadius(18)
    }

    private var MoreOptionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(lang == "es" ? "Más Opciones" : "More Options")
                .font(.headline)
                .foregroundColor(.white)
            Toggle(lang == "es" ? "Solo Lista de Espera" : "List-Only Access", isOn: $listOnly)
                .toggleStyle(SwitchToggleStyle(tint: .gold))
                .foregroundStyle(.white)
                .padding(.top, 4)
            if listOnly {
                VStack(spacing: 8) {
                    Text(lang == "es" ? "Sube una lista PDF (opcional)" : "Upload guest list PDF (optional)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    Button {
                        showFileImporter = true
                    } label: {
                        HStack {
                            Image(systemName: "doc.fill")
                            Text(guestListFilename.isEmpty ? (lang == "es" ? "Seleccionar Archivo" : "Choose File") : guestListFilename)
                        }
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(10)
                    }
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.08))
        .cornerRadius(18)
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
        print("🔐 Access Token: \(token)")

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
            "listOnly": listOnly,
            "guestListPdf": guestListUrl,
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
    
    func uploadGuestListPdf(fileUrl: URL) {
        guard let token = TokenManager.shared.getAccessToken() else { return }
        var request = URLRequest(url: URL(string: "https://backendevent-etce.onrender.com/events/upload-guestlist")!)
        request.httpMethod = "POST"
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        var data = Data()
        data.append("--\(boundary)\r\n")
        data.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileUrl.lastPathComponent)\"\r\n")
        data.append("Content-Type: application/pdf\r\n\r\n")
        if let fileData = try? Data(contentsOf: fileUrl) {
            data.append(fileData)
        }
        data.append("\r\n--\(boundary)--\r\n")

        request.httpBody = data

        URLSession.shared.dataTask(with: request) { responseData, _, _ in
            guard let responseData = responseData else { return }
            if let result = try? JSONDecoder().decode([String: String].self, from: responseData),
               let url = result["url"] {
                guestListUrl = url
            }
        }.resume()
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
        addressQuery = ""
        state = ""
        country = "United States"
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
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}

struct GPlacePrediction: Identifiable {
    let id = UUID()
    let description: String
    let placeId: String
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


    

