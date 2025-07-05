import SwiftUI

struct ResalePostCard: View {
    let post: ResalePostDTO
    var onMessage: () -> Void = {}
    var onBuyNow: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 🎟 Event Image
            ZStack {
                if let imageUrl = post.eventImageUrl, let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(maxWidth: .infinity, maxHeight: 180)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(height: 180)
                                .clipped()
                        case .failure(_):
                            fallbackImage
                        @unknown default:
                            fallbackImage
                        }
                    }
                } else {
                    fallbackImage
                }
            }
            .frame(maxWidth: .infinity)
            .cornerRadius(14)

            // 📄 Post Info
            VStack(alignment: .leading, spacing: 6) {
                Text(post.title)
                    .font(.headline)
                    .foregroundColor(.white)

                Text(post.eventTitle)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))

                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.fill")
                        .foregroundColor(.white.opacity(0.4))
                    Text(post.sellerName)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                }

                Text("$\(String(format: "%.2f", post.price))")
                    .font(.title2.bold())
                    .foregroundColor(.neonGreen)
                    .padding(.top, 4)
            }

            // 🔘 Actions
            HStack {
                Button(action: onMessage) {
                    Label("Message", systemImage: "message.fill")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(10)
                }

                Spacer()

                Button(action: onBuyNow) {
                    Label("Buy Now", systemImage: "cart.fill")
                        .font(.subheadline.bold())
                        .foregroundColor(.black)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(Color.neonGreen)
                        .cornerRadius(10)
                }
            }
            .padding(.top, 6)
        }
        .padding()
        .background(Color.white.opacity(0.04))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 4)
    }

    var fallbackImage: some View {
        Image("defaultEvent")
            .resizable()
            .scaledToFill()
            .frame(height: 180)
            .clipped()
    }
}
