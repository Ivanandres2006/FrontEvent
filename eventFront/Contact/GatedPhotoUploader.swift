import SwiftUI
import PhotosUI

struct GatedPhotoUploader: View {
    let eventId: Int

    @State private var eligible = false
    @State private var loading = true
    @State private var selected: PhotosPickerItem?
    @State private var preview: UIImage?
    @State private var message: String?
    @AppStorage("selectedLanguage") private var lang: String = "en"

    var body: some View {
        VStack(spacing: 12) {
            if loading {
                ProgressView()
            } else if eligible {
                PhotosPicker(selection: $selected, matching: .images) {
                    Label(lang == "es" ? "Subir foto del evento" : "Upload event photo", systemImage: "photo.on.rectangle.angled")
                }
                if let img = preview {
                    Image(uiImage: img).resizable().scaledToFit()
                        .frame(maxHeight: 240)
                        .cornerRadius(12)
                    HStack {
                        Button(lang == "es" ? "Publicar" : "Post") { Task { await doUpload(img) } }
                            .buttonStyle(.borderedProminent)
                        Button(lang == "es" ? "Cancelar" : "Clear") { selected = nil; preview = nil }
                            .buttonStyle(.bordered)
                    }
                }
            } else {
                Text(lang == "es"
                     ? "Solo puedes publicar si tienes ticket para este evento y aún no ha pasado."
                     : "You can only post if you have a ticket for this event and it hasn't passed.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            }
        }
        .onChange(of: selected) { _ in Task { await handlePick() } }
        .task {
            do { eligible = try await PhotosAPI.eligibility(eventId: eventId) }
            catch { eligible = false }
            loading = false
        }
        .alert(message ?? "", isPresented: .constant(message != nil)) {
            Button("OK") { message = nil }
        }
    }

    private func handlePick() async {
        guard let item = selected else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let ui = UIImage(data: data) {
            preview = ui
        }
    }

    private func doUpload(_ img: UIImage) async {
        do {
            try await PhotosAPI.upload(image: img, eventId: eventId)
            message = lang == "es" ? "Publicado ✨" : "Posted ✨"
            preview = nil; selected = nil
        } catch {
            message = lang == "es" ? "Error al subir." : "Upload failed."
        }
    }
}
