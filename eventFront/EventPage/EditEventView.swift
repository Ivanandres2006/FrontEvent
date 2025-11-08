import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Net helpers

private enum Net {
    static let base = "https://backendevent-etce.onrender.com"
    static func abs(_ raw: String?) -> String {
        guard var s = raw, !s.isEmpty else { return base + "/default-event.jpg" }
        if s.hasPrefix("http") { return s }
        if !s.hasPrefix("/") { s = "/" + s }
        return base + s
    }
}

// Formats a Date as *local* time without timezone (matches backend LocalDateTime)
private func isoLocalString(_ date: Date) -> String {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .iso8601)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = .current
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    return f.string(from: date)
}

// Parses server strings back to a local wall-clock Date.
// If the string had a timezone (e.g. "...Z" or "+01:00"), we *ignore it*
// and use the first 19 chars so 2:00 PM stays 2:00 PM locally.
private func parseEventDate(_ s: String) -> Date {
    let core = String(s.prefix(19)) // "yyyy-MM-dd'T'HH:mm:ss"
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .iso8601)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = .current
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    if let d = f.date(from: core) { return d }
    // Fallback (rare)
    if #available(iOS 15.0, *) {
        var iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
    }
    return Date()
}


// MARK: - View

struct EditEventView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("selectedLanguage") private var lang: String = "en"

    var event: Event
    var onSave: (Event) -> Void
    var onDelete: (() -> Void)? = nil

    // Basics
    @State private var title: String
    @State private var descriptionText: String
    @State private var location: String
    @State private var address: String
    @State private var date: Date

    // Image
    @State private var imageUrl: String
    @State private var imagePickerItem: PhotosPickerItem? = nil
    @State private var previewImage: UIImage? = nil
    @State private var isUploadingImage = false
    @State private var imageError: String?

    // Owner options / payments / access
    @State private var stateField: String
    @State private var countryField: String
    @State private var zelleEmail: String
    @State private var zellePhone: String
    @State private var allowPagoMovil: Bool
    @State private var allowCash: Bool
    @State private var pagoMovilPhone: String
    @State private var pagoMovilCi: String
    @State private var pagoMovilBank: String
    @State private var cashNote: String
    @State private var listOnly: Bool
    @State private var guestListUrl: String
    @State private var showFileImporter = false

    // UI State
    @State private var isSaving = false
    @State private var showDeleteDialog = false
    @State private var formError: String = ""
    @State private var showFieldError = false
    @Namespace private var anim

    // MARK: Init

    init(event: Event, onSave: @escaping (Event) -> Void, onDelete: (() -> Void)? = nil) {
        self.event = event
        self.onSave = onSave
        self.onDelete = onDelete

        _title           = State(initialValue: event.title)
        _descriptionText = State(initialValue: event.description)
        _location        = State(initialValue: event.location)
        _address         = State(initialValue: event.address)
        _date            = State(initialValue: parseEventDate(event.dateTime))
        _imageUrl        = State(initialValue: event.imageUrl ?? "")

        _stateField      = State(initialValue: event.state ?? "")
        _countryField    = State(initialValue: event.country)
        _zelleEmail      = State(initialValue: event.zelleEmail ?? "")
        _zellePhone      = State(initialValue: event.zellePhone ?? "")
        _allowPagoMovil  = State(initialValue: event.allowPagoMovil ?? false)
        _allowCash       = State(initialValue: event.allowCash ?? false)
        _pagoMovilPhone  = State(initialValue: event.pagoMovilPhone ?? "")
        _pagoMovilCi     = State(initialValue: event.pagoMovilCi ?? "")
        _pagoMovilBank   = State(initialValue: event.pagoMovilBank ?? "")
        _cashNote        = State(initialValue: event.cashNote ?? "")
        _listOnly        = State(initialValue: event.listOnly ?? false)
        _guestListUrl    = State(initialValue: event.guestListPdf ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 22) {
                        header

                        imageSection
                        if let err = imageError {
                            errorRow(err)
                        }

                        basicsSection
                        divider

                        ownerOptionsSection
                        divider

                        actionButtons
                        deleteButton
                            .padding(.top, 6)
                            .padding(.bottom, 30)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                }

                if isSaving { savingOverlay }

                // top toast for field errors
                VStack {
                    if showFieldError {
                        Text(formError)
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(Color.red.opacity(0.97))
                            .cornerRadius(12)
                            .padding(.horizontal, 18)
                            .shadow(radius: 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    Spacer()
                }
                .animation(.easeInOut, value: showFieldError)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(lang == "es" ? "Cancelar" : "Cancel") { dismiss() }
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.pdf]) { result in
                if case .success(let url) = result {
                    uploadGuestListPdf(fileUrl: url)
                }
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .foregroundColor(.gold)
            Text(lang == "es" ? "Editar Evento" : "Edit Event")
                .font(.title2.bold())
                .foregroundColor(.white)
            Spacer()
        }
    }

    private var imageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(lang == "es" ? "Imagen de portada" : "Cover Image")
                .font(.headline)
                .foregroundColor(.white)

            PhotosPicker(selection: $imagePickerItem, matching: .images) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(style: StrokeStyle(lineWidth: 2, dash: [8]))
                                .foregroundColor(Color.white.opacity(0.35))
                        )
                        .frame(height: 190)

                    if let img = previewImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 190)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    } else if let url = URL(string: imageUrl), !imageUrl.isEmpty {
                        AsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            ProgressView().tint(.gold)
                        }
                        .frame(height: 190)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "camera").font(.system(size: 26, weight: .medium))
                            Text(lang == "es" ? "Cambiar imagen" : "Change image")
                        }
                        .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
            .onChange(of: imagePickerItem) { _ in uploadPickedImage() }

            if isUploadingImage {
                ProgressView(lang == "es" ? "Subiendo..." : "Uploading...")
                    .progressViewStyle(CircularProgressViewStyle(tint: .gold))
            }
        }
    }

    private var basicsSection: some View {
        VStack(spacing: 14) {
            CustomInputField(icon: "textformat",
                             placeholder: lang == "es" ? "Título" : "Title",
                             text: $title)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text").foregroundColor(.white.opacity(0.7))
                    Text(lang == "es" ? "Descripción" : "Description")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.subheadline)
                }
                TextEditor(text: $descriptionText)
                    .frame(height: 100)
                    .padding(10)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(12)
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
            }

            CustomInputField(icon: "mappin.and.ellipse",
                             placeholder: lang == "es" ? "Ciudad" : "City",
                             text: $location)

            CustomInputField(icon: "building.2",
                             placeholder: lang == "es" ? "Estado / Provincia" : "State / Province",
                             text: $stateField)

            CustomInputField(icon: "globe",
                             placeholder: lang == "es" ? "País" : "Country",
                             text: $countryField)

            CustomInputField(icon: "house",
                             placeholder: lang == "es" ? "Dirección" : "Address",
                             text: $address)

            HStack {
                Image(systemName: "calendar").foregroundColor(.white.opacity(0.7))
                DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .tint(.white)
            }
            .padding()
            .background(Color.white.opacity(0.10))
            .cornerRadius(12)
        }
    }

    private var ownerOptionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(lang == "es" ? "Opciones del Organizador" : "Owner Options")
                .font(.title3.bold())
                .foregroundColor(.white)

            Toggle(lang == "es" ? "Solo lista de acceso" : "List-only access", isOn: $listOnly)
                .toggleStyle(SwitchToggleStyle(tint: .gold))
                .foregroundColor(.white)

            if listOnly {
                VStack(alignment: .leading, spacing: 8) {
                    Text(lang == "es" ? "Lista de invitados (PDF opcional)" : "Guest list PDF (optional)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.75))
                    HStack {
                        Text(guestListUrl.isEmpty
                             ? (lang == "es" ? "Ningún archivo seleccionado" : "No file selected")
                             : guestListUrl)
                        .foregroundColor(.white.opacity(0.8))
                        Spacer()
                        Button {
                            showFileImporter = true
                        } label: {
                            Label(lang == "es" ? "Seleccionar" : "Choose", systemImage: "doc.fill")
                                .padding(8)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(10)
                        }
                    }
                }
                .padding()
                .background(Color.white.opacity(0.06))
                .cornerRadius(12)
            }

            // Zelle
            VStack(alignment: .leading, spacing: 8) {
                Text("💸 Zelle").font(.headline).foregroundColor(.white)
                CustomInputField(icon: "envelope", placeholder: "Zelle Email", text: $zelleEmail)
                CustomInputField(icon: "phone.fill", placeholder: "Zelle Phone", text: $zellePhone)
            }
            .padding()
            .background(Color.white.opacity(0.06))
            .cornerRadius(12)

            // Venezuela-specific
            if countryField.lowercased() == "venezuela" {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(lang == "es" ? "Aceptar Pago Móvil" : "Accept Pago Móvil", isOn: $allowPagoMovil)
                        .toggleStyle(SwitchToggleStyle(tint: .gold))
                        .foregroundColor(.white)

                    if allowPagoMovil {
                        CustomInputField(icon: "iphone.gen3", placeholder: lang == "es" ? "Teléfono Pago Móvil" : "Pago Móvil Phone", text: $pagoMovilPhone)
                        CustomInputField(icon: "idcard", placeholder: lang == "es" ? "Cédula de Identidad" : "National ID (CI)", text: $pagoMovilCi)
                        CustomInputField(icon: "building.columns", placeholder: lang == "es" ? "Banco" : "Bank", text: $pagoMovilBank)
                    }

                    Toggle(lang == "es" ? "Aceptar Efectivo" : "Accept Cash", isOn: $allowCash)
                        .toggleStyle(SwitchToggleStyle(tint: .gold))
                        .foregroundColor(.white)

                    if allowCash {
                        CustomInputField(icon: "text.bubble", placeholder: lang == "es" ? "Nota para el comprador" : "Note for the buyer", text: $cashNote)
                    }
                }
                .padding()
                .background(Color.white.opacity(0.06))
                .cornerRadius(12)
            }
        }
    }

    private var actionButtons: some View {
        Button(action: save) {
            HStack {
                Spacer()
                Text(isSaving
                     ? (lang == "es" ? "Guardando..." : "Saving...")
                     : (lang == "es" ? "Guardar cambios" : "Save Changes"))
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                    .padding(.vertical, 12)
                Spacer()
            }
            .background(isSaving ? Color.gray : Color.gold)
            .cornerRadius(16)
        }
        .disabled(isSaving)
        .padding(.top, 6)
    }

    private var deleteButton: some View {
        Button(role: .destructive) { showDeleteDialog = true } label: {
            Text(lang == "es" ? "Borrar Evento" : "Delete Event")
                .fontWeight(.semibold)
                .foregroundColor(.red)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
        }
        .confirmationDialog(
            lang == "es" ? "¿Seguro que quieres borrar este evento?" : "Are you sure you want to delete this event?",
            isPresented: $showDeleteDialog, titleVisibility: .visible
        ) {
            Button(lang == "es" ? "Borrar" : "Delete", role: .destructive, action: deleteEvent)
            Button(lang == "es" ? "Cancelar" : "Cancel", role: .cancel) {}
        }
    }

    private var divider: some View {
        Divider().background(Color.white.opacity(0.18))
            .padding(.top, 4)
    }

    private var savingOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .gold))
                Text(lang == "es" ? "Guardando cambios..." : "Saving changes...")
                    .foregroundColor(.white)
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 24)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
        }
        .transition(.opacity)
    }

    private func errorRow(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
            Text(msg).foregroundColor(.red).font(.footnote).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                withAnimation { imageError = nil; previewImage = nil; imagePickerItem = nil }
            } label: {
                Text(lang == "es" ? "Elegir otra" : "Choose another")
                    .font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.white.opacity(0.08)).cornerRadius(8)
            }
        }
    }

    // MARK: - Networking

    private func deleteEvent() {
        guard let token = TokenManager.shared.getAccessToken() else { return }
        let url = URL(string: "\(Net.base)/events/\(event.id)")!
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: req) { _, _, _ in
            DispatchQueue.main.async {
                onDelete?()
                dismiss()
            }
        }.resume()
    }

    private func save() {
        // basic client validation
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return showField(lang == "es" ? "Por favor agrega un título." : "Please enter a title.") }
        guard !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return showField(lang == "es" ? "Por favor agrega la ciudad." : "Please enter the city.") }
        guard !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return showField(lang == "es" ? "Por favor agrega la dirección." : "Please enter the address.") }

        guard let token = TokenManager.shared.getAccessToken() else { return showField("Not authenticated.") }

        isSaving = true

        // Build body (NO ticketTiers here; backend keeps existing tiers)
        var body: [String: Any] = [
            "title": title,
            "description": descriptionText,
            "location": location,
            "state": stateField,
            "address": address,
            "country": countryField,
            "dateTime": isoLocalString(date),
            "imageUrl": imageUrl.isEmpty ? "/default-event.jpg" : imageUrl,
            "zelleEmail": zelleEmail,
            "zellePhone": zellePhone,
            "allowPagoMovil": allowPagoMovil,
            "allowCash": allowCash,
            "pagoMovilPhone": pagoMovilPhone,
            "pagoMovilCi": pagoMovilCi,
            "pagoMovilBank": pagoMovilBank,
            "cashNote": cashNote,
            "listOnly": listOnly,
            "guestListPdf": guestListUrl
        ]

        // If Venezuela is not selected, clear alt-payment fields
        if countryField.lowercased() != "venezuela" {
            body["allowPagoMovil"] = false
            body["allowCash"] = false
            body["pagoMovilPhone"] = ""
            body["pagoMovilCi"] = ""
            body["pagoMovilBank"] = ""
            body["cashNote"] = ""
        }

        let url = URL(string: "\(Net.base)/events/\(event.id)")!
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { data, _, error in
            DispatchQueue.main.async { self.isSaving = false }

            guard let data = data, error == nil else {
                return showField("Failed to update event.")
            }
            if let raw = String(data: data, encoding: .utf8) {
                print("📦 Update response:", raw)
            }
            if let updated = try? JSONDecoder().decode(Event.self, from: data) {
                DispatchQueue.main.async {
                    onSave(updated)
                    dismiss()
                }
            } else {
                showField("Server error while updating.")
            }
        }.resume()
    }

    private func uploadPickedImage() {
        guard let item = imagePickerItem else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let ui = UIImage(data: data) {
                await MainActor.run { self.previewImage = ui }
                await uploadImageToServer(imageData: data)
            } else {
                await MainActor.run {
                    self.previewImage = nil
                    self.imageError = lang == "es" ? "Imagen inválida." : "Invalid image."
                }
            }
        }
    }

    private func uploadImageToServer(imageData: Data) async {
        await MainActor.run { self.isUploadingImage = true; self.imageError = nil }

        // compress a bit
        let jpeg = UIImage(data: imageData)?.jpegData(compressionQuality: 0.8) ?? imageData
        guard let url = URL(string: "\(Net.base)/events/upload-image") else { return }

        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"event.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(jpeg)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let txt = String(data: data, encoding: .utf8) ?? ""
                print("❌ upload-image failed:", txt)
                await MainActor.run {
                    self.imageError = lang == "es" ? "Error al subir la imagen." : "Image upload failed."
                }
                return
            }
            if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String],
               let url = dict["imageUrl"] {
                await MainActor.run { self.imageUrl = url; self.imageError = nil }
            } else {
                await MainActor.run {
                    self.imageError = lang == "es" ? "Respuesta inesperada del servidor." : "Unexpected server response."
                }
            }
        } catch {
            await MainActor.run {
                self.imageError = lang == "es" ? "Fallo de red." : "Network error."
            }
        }
        await MainActor.run { self.isUploadingImage = false }
    }

    private func uploadGuestListPdf(fileUrl: URL) {
        var request = URLRequest(url: URL(string: "\(Net.base)/events/upload-guestlist")!)
        request.httpMethod = "POST"
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var data = Data()
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileUrl.lastPathComponent)\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: application/pdf\r\n\r\n".data(using: .utf8)!)
        if let fileData = try? Data(contentsOf: fileUrl) {
            data.append(fileData)
        }
        data.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = data

        URLSession.shared.dataTask(with: request) { responseData, _, _ in
            guard let responseData = responseData else { return }
            if let result = try? JSONDecoder().decode([String: String].self, from: responseData),
               let url = result["url"] {
                DispatchQueue.main.async {
                    guestListUrl = url
                }
            }
        }.resume()
    }

    private func showField(_ msg: String) {
        let h = UINotificationFeedbackGenerator()
        h.notificationOccurred(.error)
        formError = msg
        withAnimation { showFieldError = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
            withAnimation { showFieldError = false }
        }
    }
}

// MARK: - Shared input views

struct CustomInputField: View {
    var icon: String
    var placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var isSecure: Bool = false

    var body: some View {
        HStack {
            Image(systemName: icon).foregroundColor(.white.opacity(0.7))
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
                    .keyboardType(keyboard)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .foregroundColor(.white)
            }
        }
        .padding()
        .background(Color.white.opacity(0.08))
        .cornerRadius(12)
    }
}
