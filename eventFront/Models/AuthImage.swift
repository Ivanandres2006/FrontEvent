import SwiftUI


// MARK: - Authenticated image loader for QR (uses Bearer token)
struct AuthImage: View {
    let url: URL
    let token: String
    let size: CGFloat

    @State private var data: Data?
    @State private var isLoading = true
    @State private var hadError = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.black.opacity(0.95))
                .frame(width: size, height: size)

            if isLoading {
                ProgressView().frame(width: size - 40, height: size - 40)
            } else if let data, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: size - 40, height: size - 40)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "xmark.octagon.fill").font(.title)
                    Text("QR unavailable").font(.footnote)
                    Button("Retry") { fetch() }.font(.caption.bold())
                }
                .foregroundColor(.white.opacity(0.9))
                .frame(width: size - 40, height: size - 40)
            }
        }
        .onAppear(perform: fetch)
    }

    private func fetch() {
        isLoading = true; hadError = false; data = nil
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                isLoading = false
                guard err == nil,
                      let http = resp as? HTTPURLResponse, http.statusCode == 200,
                      let data = data else { hadError = true; return }
                self.data = data
            }
        }.resume()
    }
}
