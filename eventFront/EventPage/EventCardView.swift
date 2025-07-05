import SwiftUI

struct EventCardView: View {
    let event: Event

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // 📸 Event image
            Group {
                if let imageUrl = event.imageUrl,
                   let url = URL(string: imageUrl),
                   !imageUrl.isEmpty {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ZStack {
                                Color.black.opacity(0.2)
                                ProgressView().tint(.white)
                            }
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(height: 240)
                                .clipped()
                        case .failure(_):
                            Image("defaultEvent")
                                .resizable()
                                .scaledToFill()
                                .frame(height: 240)
                                .clipped()
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    Image("defaultEvent")
                        .resizable()
                        .scaledToFill()
                        .frame(height: 240)
                        .clipped()
                }
            }

            // 🧾 Text only (no background at all)
            VStack(alignment: .leading, spacing: 8) {
                Text(event.title)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(.neonGreen)
                    Text(event.location)
                        .foregroundColor(.white)
                        .font(.subheadline)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundColor(.neonGreen)
                    Text(formattedDate(event.dateTime))
                        .foregroundColor(.white)
                        .font(.caption)
                }
            }
            .padding()
        }
        .frame(height: 240)
        .cornerRadius(22)
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 6)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .clipped()

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

}
