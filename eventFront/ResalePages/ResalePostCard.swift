import SwiftUI

struct ResalePostCard: View {
    let post: ResalePostDTO
    var onMessage: () -> Void
    var trailingSellerMenu: (() -> AnyView)? = nil
    var onBuyNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let url = URL(string: post.eventImageUrl ?? "") {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: Color.white.opacity(0.06)
                    }
                }
                .frame(height: 160)
                .clipped()
                .cornerRadius(16)
            }

            Text(post.title)
                .foregroundColor(.white)
                .font(.headline)

            HStack {
                Text(post.eventTitle)
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Text(String(format: "$%.2f", post.price))
                    .foregroundColor(.gold)
                    .fontWeight(.bold)
            }

            HStack(spacing: 10) {
                Button(action: onMessage) {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right.fill")
                        .padding(.vertical, 8).padding(.horizontal, 12)
                        .background(Color.white.opacity(0.08))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                Button(action: onBuyNow) {
                    Label("Buy", systemImage: "creditcard.fill")
                        .padding(.vertical, 8).padding(.horizontal, 12)
                        .background(Color.gold)
                        .foregroundColor(.black)
                        .cornerRadius(10)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        // Inside ResalePostCard view
        .overlay(alignment: .topTrailing) {
            if let trailingSellerMenu = trailingSellerMenu { trailingSellerMenu() }
        }
    }
}
