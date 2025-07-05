import SwiftUI

struct EventCardViewWithHighlight: View {
    let event: Event
    let searchText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 📸 Event image
            AsyncImage(url: URL(string: event.imageUrl ?? "")) { phase in
                switch phase {
                case .empty:
                    ZStack {
                        Color.deepNavy
                        ProgressView().tint(.white)
                    }
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure(_):
                    Image("defaultEvent")
                        .resizable()
                        .scaledToFill()
                @unknown default:
                    EmptyView()
                }
            }
            .frame(height: 180)
            .cornerRadius(16)
            .clipped()

            // 📝 Event title with highlighting
            highlightText(event.title, with: searchText)
                .font(.headline)
                .foregroundColor(.white)
                .lineLimit(2)

            // 📍 Location
            HStack {
                Image(systemName: "mappin.circle.fill")
                    .foregroundColor(.neonGreen)
                Text(event.location)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.85))
            }

            // 📆 Date
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.cyan)
                Text(formattedDate(event.dateTime))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.75))
            }
        }
        .padding()
        .background(
            LinearGradient(colors: [.deepNavy.opacity(0.6), .black.opacity(0.8)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 4)
    }
    
    func formattedDate(_ isoString: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

        guard let date = formatter.date(from: isoString) else { return isoString }

        let output = DateFormatter()
        output.locale = Locale.current
        output.timeZone = TimeZone.current
        output.dateFormat = "EEEE, MMM d 'at' h:mm a"
        return output.string(from: date)
    }

    private func highlightText(_ text: String, with keyword: String) -> Text {
        guard !keyword.isEmpty else {
            return Text(text)
        }

        let parts = text.components(separatedBy: keyword)
        var result = Text("")

        for i in 0..<parts.count {
            result = result + Text(parts[i])
            if i != parts.count - 1 {
                result = result + Text(keyword)
                    .foregroundColor(.accentElectric)
                    .bold()
            }
        }

        return result
    }
}
