import SwiftUI

struct BadgeRow: View {
    let badges: [BadgeDTO]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(badges) { b in
                    HStack(spacing: 6) {
                        if let url = b.iconUrl, let u = URL(string: url) {
                            AsyncImage(url: u) { $0.resizable().scaledToFit() } placeholder: { Color.clear }
                                .frame(width: 16, height: 16)
                        }
                        Text(b.name)
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                            .help(b.description ?? "")
                    }
                }
            }.padding(.horizontal)
        }
    }
}
