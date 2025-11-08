import SwiftUI
import PhotosUI

struct ChatSettingsView: View {
    @AppStorage("selectedLanguage") var lang: String = "en"
    let room: ChatRoomSummaryDTO

    @State private var name: String = ""
    @State private var iconImage: PhotosPickerItem? = nil
    @State private var iconData: Data? = nil
    @State private var isSaving = false
    @State private var errorText: String?

    var body: some View {
        Form {
            Section(header: Text(lang == "es" ? "Nombre del grupo" : "Group name")) {
                TextField("Name", text: $name)
            }
            Section(header: Text(lang == "es" ? "Icono del chat" : "Chat icon")) {
                HStack {
                    if let data = iconData, let ui = UIImage(data: data) {
                        Image(uiImage: ui)
                            .resizable().scaledToFill()
                            .frame(width: 60, height: 60).clipShape(Circle())
                    } else if let urlStr = room.iconUrl, let url = URL(string: urlStr) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty: ProgressView()
                            case .success(let img): img.resizable().scaledToFill()
                            case .failure: Image(systemName: "person.3.fill")
                            @unknown default: EmptyView()
                            }
                        }
                        .frame(width: 60, height: 60).clipShape(Circle())
                    } else {
                        Image(systemName: "person.3.fill").font(.largeTitle)
                    }
                    Spacer()
                    PhotosPicker(selection: $iconImage, matching: .images, photoLibrary: .shared()) {
                        Text(lang == "es" ? "Cambiar" : "Change")
                    }
                    .onChange(of: iconImage) { _ in Task { await pickIcon() } }
                }
            }
            Section {
                Button(lang == "es" ? "Guardar" : "Save") {
                    Task { await save() }
                }
                .disabled(isSaving)
            }
        }
        .navigationTitle(lang == "es" ? "Ajustes" : "Settings")
        .task { name = room.displayName }
        .alert(isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
            Alert(title: Text("Error"), message: Text(errorText ?? ""), dismissButton: .default(Text("OK")))
        }
    }

    private func pickIcon() async {
        guard let iconImage else { return }
        iconData = try? await iconImage.loadTransferable(type: Data.self)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            var iconUrl: String? = nil
            if let data = iconData {
                // Upload the icon and get a URL back
                iconUrl = try await ChatAPI.shared.uploadRoomIcon(roomId: room.id,
                                                                  imageData: data,
                                                                  fileName: "icon.jpg")
            }
            // Update name and/or iconUrl
            try await ChatAPI.shared.updateRoom(roomId: room.id, name: name, iconUrl: iconUrl)
        } catch {
            errorText = error.localizedDescription
        }
    }
}
