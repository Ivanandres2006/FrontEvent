


import SwiftUI

struct MyResaleListingsView: View {
    @AppStorage("selectedLanguage") var lang: String = "en"
    @Environment(\.dismiss) var dismiss

    @State private var listings: [MyListingDTO] = []
    @State private var loading = true
    @State private var error = ""

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                HStack {
                    Text(lang == "es" ? "Mis Publicaciones" : "My Listings")
                        .font(.largeTitle.bold())
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.top)

                if loading {
                    ProgressView().tint(.white)
                    Spacer()
                } else if !error.isEmpty {
                    Text(error).foregroundColor(.red)
                    Spacer()
                } else if listings.isEmpty {
                    Text(lang == "es" ? "No tienes publicaciones de reventa." : "You have no resale listings.")
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                } else {
                    List {
                        ForEach(listings) { l in
                            ListingRow(listing: l)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .padding()
        }
        .onAppear { load() }
    }

    func load() {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/api/resale/my-listings") else { return }
        loading = true; error = ""
        var r = URLRequest(url: url)
        r.httpMethod = "GET"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: r) { data, resp, _ in
            DispatchQueue.main.async { loading = false }
            guard let http = resp as? HTTPURLResponse else { return }
            if http.statusCode != 200 {
                DispatchQueue.main.async { error = "Server error: \(http.statusCode)" }
                return
            }
            if let data = data, let arr = try? JSONDecoder().decode([MyListingDTO].self, from: data) {
                DispatchQueue.main.async { listings = arr }
            }
        }.resume()
    }

    @ViewBuilder
    func ListingRow(listing: MyListingDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(listing.title ?? (lang == "es" ? "Sin título" : "Untitled"))
                    .foregroundColor(.white)
                    .font(.headline)
                Spacer()
                if listing.sold {
                    Tag(text: lang == "es" ? "Vendido" : "Sold")
                }
            }
            HStack {
                Text(listing.eventTitle ?? "")
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Text(String(format: "$%.2f", listing.price))
                    .foregroundColor(.gold)
                    .bold()
            }

            HStack(spacing: 10) {
                NavigationLink {
                    PendingOrdersView(postId: listing.id)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "tray.full")
                        Text(lang == "es" ? "Pedidos" : "Orders")
                        if listing.pendingManualOrders > 0 {
                            Badge(count: listing.pendingManualOrders)
                        }
                    }
                    .padding(.vertical, 8).padding(.horizontal, 12)
                    .background(Color.white.opacity(0.08))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }

                if listing.sold == false {
                    // Optional: Edit price, share link, etc.
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }

    func Tag(text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.bold())
            .padding(.vertical, 4).padding(.horizontal, 8)
            .background(Color.white.opacity(0.1))
            .foregroundColor(.white)
            .cornerRadius(6)
    }

    func Badge(count: Int) -> some View {
        Text("\(count)")
            .font(.caption2.bold())
            .padding(6)
            .background(Color.gold)
            .foregroundColor(.black)
            .clipShape(Circle())
    }
}
