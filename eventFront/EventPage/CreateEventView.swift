import SwiftUI
import PhotosUI
import CoreLocation

struct CreateEventView: View {
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


    let states = ["Alabama", "Alaska", "Arizona", "Arkansas", "California", "Colorado", "Connecticut", "Delaware", "Florida", "Georgia", "Hawaii", "Idaho", "Illinois", "Indiana", "Iowa", "Kansas", "Kentucky", "Louisiana", "Maine", "Maryland", "Massachusetts", "Michigan", "Minnesota", "Mississippi", "Missouri", "Montana", "Nebraska", "Nevada", "New Hampshire", "New Jersey", "New Mexico", "New York", "North Carolina", "North Dakota", "Ohio", "Oklahoma", "Oregon", "Pennsylvania", "Rhode Island", "South Carolina", "South Dakota", "Tennessee", "Texas", "Utah", "Vermont", "Virginia", "Washington", "West Virginia", "Wisconsin", "Wyoming"]

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

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
                        stepTickets.tag(3)
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
                                Text(step < 3 ? "Next" : "Create Event")
                                    .bold()
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.neonGreen)
                                    .foregroundColor(.black)
                                    .cornerRadius(14)
                            }
                        }
                    }
                    .padding()
                    .disabled(isLoading || (step == 0 && title.isEmpty))
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

                            Text("Event Created!")
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
            .fill(step >= index ? Color.neonGreen : Color.white.opacity(0.2))
            .frame(width: 40, height: 40)
            .overlay(Image(systemName: icon).foregroundColor(.black))
            .animation(.easeInOut, value: step)
    }

    var stepEventInfo: some View {
        VStack(spacing: 24) {
            Text("🎯 Event Info")
                .font(.title2.bold())
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top)

            CustomInputField(icon: "textformat", placeholder: "Event Title", text: $title)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .foregroundColor(.white.opacity(0.7))
                    Text("Description")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.subheadline)
                }

                ZStack(alignment: .topLeading) {
                    if description.isEmpty {
                        Text("Write a description...")
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
                    Text("Event Date & Time")
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

    var stepLocation: some View {
        VStack(spacing: 20) {
            Text("📍 Location")
                .font(.title.bold())
                .foregroundColor(.white)

            CustomInputField(icon: "mappin.and.ellipse", placeholder: "City / Venue", text: $location)
            CustomInputField(icon: "house", placeholder: "Street Address", text: $address)
            CustomInputField(icon: "globe", placeholder: "Country", text: $country)
            CustomDropdown(label: "Select State", selection: $state, options: states)
        }
        .padding(.horizontal)
    }

    var stepImage: some View {
        VStack(spacing: 20) {
            Text("📸 Event Image")
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
                Text("Select Image")
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.neonGreen)
                    .foregroundColor(.black)
                    .cornerRadius(12)
            }
        }
        .padding(.horizontal)
    }

    var stepTickets: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("🎟 Ticket Tiers")
                    .font(.title.bold())
                    .foregroundColor(.white)

                // Input Fields
                Group {
                    CustomInputField(icon: "tag", placeholder: "Tier Name", text: $tierName)
                    CustomInputField(icon: "dollarsign.circle", placeholder: "Price", text: $tierPrice, keyboard: .decimalPad)
                    CustomInputField(icon: "number", placeholder: "Quantity", text: $tierQuantity, keyboard: .numberPad)
                    VStack(alignment: .leading, spacing: 4) {
                        CustomInputField(
                            icon: "list.number",
                            placeholder: "Tier Order",
                            text: $tierOrder,
                            keyboard: .numberPad
                        )

                        Text("Enter a number. Lower numbers unlock first (e.g. 1 for Early Bird, 2 for General Entry).")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }

                // More Options Toggle
                Button(action: {
                    withAnimation {
                        showTierOptions.toggle()
                    }
                }) {
                    HStack {
                        Image(systemName: showTierOptions ? "chevron.down.circle.fill" : "chevron.right.circle")
                        Text("More Options")
                    }
                    .foregroundColor(.white.opacity(0.8))
                }

                // Time range inputs
                if showTierOptions {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Start Time")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        DatePicker("Start", selection: $tierStartDate)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .foregroundColor(.white)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(10)

                        Text("End Time")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        DatePicker("End", selection: $tierEndDate)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .foregroundColor(.white)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(10)
                    }
                    .padding(.horizontal)
                }

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
                    Text("Add Tier")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.neonGreen)
                        .foregroundColor(.black)
                        .cornerRadius(12)
                }

                Divider().background(Color.white.opacity(0.2))

                // Preview of Added Tiers
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(ticketTiers.sorted(by: { $0.order < $1.order })) { tier in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tier.name)
                                    .font(.headline)
                                    .foregroundColor(.white)

                                Text("$\(tier.price, specifier: "%.2f") • \(tier.quantity) tickets • Order: \(tier.order)")
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
                                ticketTiers.removeAll { $0.id == tier.id }
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

                Spacer(minLength: 100)
            }
            .padding(.horizontal)
            .padding(.bottom, 32) // extra bottom space
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

    func createEvent() {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "http://localhost:8080/events") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let finalImageUrl = imageUrl.isEmpty ? "/default-event.jpg" : imageUrl

        let payload: [String: Any] = [
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

    func fetchEventById(_ id: Int) {
        
        guard let url = URL(string: "http://localhost:8080/events/\(id)"),
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

    func uploadImageToServer(imageData: Data) async {
        guard let url = URL(string: "http://localhost:8080/events/upload-image"),
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
        message = ""
        isLoading = false
        newEvent = nil
    }
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


    

