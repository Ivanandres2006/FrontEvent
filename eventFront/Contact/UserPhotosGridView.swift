import SwiftUI

struct UserPhotosGridView: View {
    let userId: Int
    @State private var photos: [PhotoDTO] = []
    @State private var loading = true
    @State private var loadError: String?

    private let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        Group {
            if loading {
                ProgressView()
            } else if let err = loadError {
                Text(err).foregroundStyle(.red)
            } else if photos.isEmpty {
                ContentUnavailableView("No photos yet", systemImage: "photo.on.rectangle")
                    .foregroundStyle(.white)
            } else {
                LazyVGrid(columns: cols, spacing: 6) {
                    ForEach(photos) { p in
                        AsyncImage(url: URL(string: p.url)) { $0.resizable().scaledToFill() }
                            placeholder: { Rectangle().fill(.gray.opacity(0.15)) }
                            .frame(height: 110)
                            .clipped()
                            .cornerRadius(8)
                    }
                }
            }
        }
        .task(id: userId) { await load() } // reload if userId changes
    }

    @MainActor
    private func load() async {
        loading = true
        defer { loading = false }
        do {
            photos = try await PhotosAPI.userPhotos(userId: userId)
            loadError = nil
        } catch {
            loadError = "Failed to load photos."
        }
    }
}
