import SwiftUI
import PhotosUI

struct TicketTierEditable: Identifiable {
    let id: Int // Must match backend ID
    var name: String
    var price: Double
    var quantity: Int
    var forceOpen: Bool
}

struct EditEventView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("selectedLanguage") var lang: String = "en"

    var event: Event
    var onSave: (Event) -> Void
    var onDelete: (() -> Void)? = nil

    @State private var title: String
    @State private var description: String
    @State private var location: String
    @State private var address: String
    @State private var date: Date
    @State private var imageUrl: String
    @State private var selectedImageData: Data?
    @State private var ticketTiers: [TicketTierEditable]
    @State private var message = ""
    @State private var isSaving = false
    @State private var showImagePicker = false
    @State private var showDeleteDialog = false

    init(event: Event, onSave: @escaping (Event) -> Void, onDelete: (() -> Void)? = nil) {
        self.event = event
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: event.title)
        _description = State(initialValue: event.description)
        _location = State(initialValue: event.location)
        _address = State(initialValue: event.address)
        _date = State(initialValue: Self.dateFromString(event.dateTime))
        _imageUrl = State(initialValue: event.imageUrl ?? "")
        _ticketTiers = State(initialValue: event.ticketTiers.map {
            TicketTierEditable(id: $0.id ?? 0, name: $0.name, price: $0.price, quantity: $0.availableQuantity, forceOpen: $0.forceOpen ?? false)
        })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                
                if isSaving{
                    ProgressView(lang == "es" ? "Guardando..." : "Saving...")
                                    .progressViewStyle(CircularProgressViewStyle(tint: .gold))
                                    .scaleEffect(1.5)
                }else{
                    ScrollView {
                        VStack(spacing: 24) {
                            Text(lang == "es" ? "\u{1F6E0} Editar Evento" : "\u{1F6E0} Edit Event")
                                .font(.largeTitle.bold())
                                .foregroundColor(.white)
                                .padding(.top)
                            
                            imageSection
                            inputFieldsSection
                            ticketTiersSection
                            saveButton
                            deleteButton
                        }
                        .padding()
                    }
                }
            }
            .sheet(isPresented: $showImagePicker) {
                PhotoPickerView(imageData: $selectedImageData)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(lang == "es" ? "Cancelar" : "Cancel") { dismiss() }
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
    }

    private var imageSection: some View {
        VStack(spacing: 12) {
            if let data = selectedImageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage).resizable().scaledToFit().frame(height: 180).cornerRadius(12)
            } else if let url = URL(string: imageUrl) {
                AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { ProgressView() }
                    .frame(height: 180).cornerRadius(12)
            }
            Button(lang == "es" ? "Cambiar Imagen" : "Change Image") { showImagePicker = true }
                .foregroundColor(.gold)
        }
    }

    private var inputFieldsSection: some View {
        VStack(spacing: 16) {
            CustomInputField(icon: "textformat", placeholder: lang == "es" ? "Titulo": "Title", text: $title)
            CustomMultilineField(icon: "doc.text", title: lang == "es" ? "Descripcion": "Description", text: $description)
            CustomInputField(icon: "mappin", placeholder: lang == "es" ? "Ubicacion": "Location", text: $location)
            CustomInputField(icon: "location.fill", placeholder: lang == "es" ? "Direccion": "Address", text: $address)
            CustomDatePicker(date: $date)
            if !message.isEmpty {
                Text(message).foregroundColor(.red).font(.footnote)
            }
        }
    }

    private var ticketTiersSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "ticket.fill").foregroundColor(.white)
                Text(lang == "es" ? "Niveles de entradas": "Ticket Tiers").font(.title3.bold()).foregroundColor(.white)
            }

            ForEach(ticketTiers.indices, id: \.self) { index in
                TicketTierEditor(tier: $ticketTiers[index])
            }

            Button {
                ticketTiers.append(TicketTierEditable(id: 0, name: "", price: 0.0, quantity: 0, forceOpen: false))
            } label: {
                Label(lang == "es" ? "Agregar nivel": "Add Tier", systemImage: "plus.circle.fill")
                    .foregroundColor(.gold)
            }
        }
    }

    private var saveButton: some View {
        Button(action: updateEvent) {
            HStack {
                Spacer()
                Text(
                    isSaving
                    ? (lang == "es" ? "Guardando..." : "Saving...")
                    : (lang == "es" ? "Guardar cambios" : "Save Changes")
                )
                    .foregroundColor(.black)
                    .fontWeight(.bold)
                    .padding(.vertical, 12)
                Spacer()
            }
            .background(isSaving ? Color.gray : Color.gold)
            .cornerRadius(16)
        }
        .disabled(isSaving)
    }


    private var deleteButton: some View {
        Button(role: .destructive) {
            showDeleteDialog = true
        } label: {
            Text(lang == "es" ? "Borrar Evento": "Delete Event").fontWeight(.semibold).foregroundColor(.red).padding(.vertical, 10).frame(maxWidth: .infinity)
        }
        .confirmationDialog(lang == "es" ? "Seguro que quiere borrar este evento?": "Are you sure you want to delete this event?", isPresented: $showDeleteDialog, titleVisibility: .visible) {
            Button(lang == "es" ? "Borrar": "Delete", role: .destructive, action: deleteEvent)
            Button(lang == "es" ? "Cancelar": "Cancel", role: .cancel) {}
        }
    }

    private func deleteEvent() {
        guard let token = TokenManager.shared.getAccessToken() else {
            message = "Not authenticated"
            return
        }

        let url = URL(string: "https://backendevent-etce.onrender.com/events/\(event.id)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { _, _, _ in
            DispatchQueue.main.async {
                onDelete?()
                dismiss()
            }
        }.resume()
    }

    private func updateEvent() {
        guard !title.isEmpty, !description.isEmpty, !location.isEmpty else {
            message = "Please fill in all fields."
            return
        }

        guard let token = TokenManager.shared.getAccessToken() else {
            message = "Not authenticated"
            return
        }

        isSaving = true
        message = ""

        let formattedDate = Self.formatDate(date)
        let url = URL(string: "https://backendevent-etce.onrender.com/events/\(event.id)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let tiers = ticketTiers.enumerated().map { index, tier in
            var tierDict: [String: Any] = [
                "name": tier.name,
                "price": tier.price,
                "quantity": tier.quantity,
                "forceOpen": tier.forceOpen,
                "order": index
            ]
            if tier.id != 0 {
                tierDict["id"] = tier.id
            }
            return tierDict
        }


        let body: [String: Any] = [
            "title": title,
            "description": description,
            "location": location,
            "address": address,
            "dateTime": formattedDate,
            "imageUrl": imageUrl,
            "ticketTiers": tiers
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                isSaving = false
            }

            guard let data = data, error == nil,
                  let updated = try? JSONDecoder().decode(Event.self, from: data) else {
                DispatchQueue.main.async {
                    message = "Failed to update event"
                }
                return
            }

            DispatchQueue.main.async {
                onSave(updated)
                dismiss()
            }
        }.resume()
    }

    static func dateFromString(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: string) ?? Date()
    }

    static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.string(from: date)
    }
}

private struct TicketTierEditor: View {
    @AppStorage("selectedLanguage") var lang: String = "en"
    @Binding var tier: TicketTierEditable
    @State private var isToggling = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(tier.name.isEmpty
                     ? (lang == "es" ? "Nuevo Nivel" : "New Tier")
                     : tier.name)
                    .font(.headline).foregroundColor(.white)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(lang == "es" ? "Nombre" : "Name").foregroundColor(.gray)
                TextField(lang == "es" ? "Nombre del nivel" :"Tier name", text: $tier.name)
                    .padding().background(Color.white.opacity(0.08)).cornerRadius(12).foregroundColor(.white)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading) {
                    Text(lang == "es" ? "Precio" :"Price").foregroundColor(.gray)
                    TextField(lang == "es" ? "Precio" :"Price", value: $tier.price, formatter: NumberFormatter.currency)
                        .keyboardType(.decimalPad)
                        .padding().background(Color.white.opacity(0.08)).cornerRadius(12).foregroundColor(.white)
                }

                VStack(alignment: .leading) {
                    Text(lang == "es" ? "Cantidad" :"Quantity").foregroundColor(.gray)
                    TextField(lang == "es" ? "Cantidad" :"Qty", value: $tier.quantity, formatter: NumberFormatter())
                        .keyboardType(.numberPad)
                        .padding().background(Color.white.opacity(0.08)).cornerRadius(12).foregroundColor(.white)
                }
            }

            Button {
                toggleForceOpen()
            } label: {
                Label(
                    tier.forceOpen
                        ? (lang == "es" ? "Cerrar Nivel" : "Close Tier")
                        : (lang == "es" ? "Abrir Ahora" : "Open Now"),
                      systemImage: tier.forceOpen ? "lock.fill" : "bolt.fill")
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(tier.forceOpen ? Color.red.opacity(0.2) : Color.gold.opacity(0.15))
                    .foregroundColor(tier.forceOpen ? .red : .gold)
                    .cornerRadius(10)
            }
            .disabled(isToggling)
        }
        .padding().background(Color.white.opacity(0.04)).cornerRadius(12)
    }

    private func toggleForceOpen() {
        guard let token = TokenManager.shared.getAccessToken() else { return }
        isToggling = true

        let urlStr = "https://backendevent-etce.onrender.com/api/tickets/tier/\(tier.id)/" + (tier.forceOpen ? "force-close" : "force-open")
        guard let url = URL(string: urlStr) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { _, _, _ in
            DispatchQueue.main.async {
                tier.forceOpen.toggle()
                isToggling = false
            }
        }.resume()
    }
}

struct CustomInputField: View {
    var icon: String
    var placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var isSecure: Bool = false

    var body: some View {
        HStack {
            Image(systemName: icon).foregroundColor(.gray)
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
                    .keyboardType(keyboard)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }
        }
        .padding()
        .background(Color.white.opacity(0.08))
        .cornerRadius(10)
        .foregroundColor(.white)
    }
}

struct CustomMultilineField: View {
    var icon: String
    var title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon).foregroundColor(.gray)
                Text(title)
                    .foregroundColor(.white.opacity(0.8))
                    .font(.subheadline)
            }

            TextEditor(text: $text)
                .frame(height: 100)
                .padding(8)
                .background(Color.white.opacity(0.05))
                .cornerRadius(10)
                .foregroundColor(.white)
                .scrollContentBackground(.hidden)
        }
    }
}

struct CustomDatePicker: View {
    @Binding var date: Date

    var body: some View {
        HStack {
            Image(systemName: "calendar")
                .foregroundColor(.gray)
            DatePicker("", selection: $date)
                .labelsHidden()
                .tint(.white)
        }
        .padding()
        .background(Color.white.opacity(0.08))
        .cornerRadius(12)
    }
}

extension NumberFormatter {
    static var currency: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter
    }
}
