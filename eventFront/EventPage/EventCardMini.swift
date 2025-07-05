//
//  EventCardMini.swift
//  eventFront
//
//  Created by Ivan Andres Madriz on 20/6/25.
//
import SwiftUI

struct EventCardMini: View {
    let event: Event
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            HStack(spacing: 16) {
                // 📸 Left-side image
                AsyncImage(url: URL(string: event.imageUrl ?? "")) { phase in
                    switch phase {
                    case .empty:
                        ZStack {
                            LinearGradient(colors: [.indigo.opacity(0.5), .black.opacity(0.5)],
                                           startPoint: .top, endPoint: .bottom)
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
                        Color.gray
                    }
                }
                .frame(width: 100, height: 100)
                .cornerRadius(16)
                .clipped()
                .shadow(color: .purple.opacity(0.3), radius: 6, x: 0, y: 4)
                
                // 📝 Right-side info
                VStack(alignment: .leading, spacing: 6) {
                    Text(event.title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundColor(.mint)
                        Text(event.location)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                    
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .foregroundColor(.cyan)
                        Text(formattedDate(event.dateTime))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                
                Spacer()
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [
                        Color.deepNavy.opacity(0.6),
                        Color.black.opacity(0.8)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(22)
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 5)
            
            // ✅ Bottom-right badge overlay
            if let label = badgeLabel(for: event.dateTime) {
                Text(label)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.neonGreen.opacity(0.25))
                    .foregroundColor(.neonGreen)
                    .cornerRadius(12)
                    .padding(10)
            }
        }
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
    
    
    
    func badgeLabel(for isoString: String) -> String? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        
        guard let eventDate = formatter.date(from: isoString) else {
            return nil
        }
        
        let now = Date()
        let calendar = Calendar.current
        
        // Strip time to get date-only difference
        let startOfToday = calendar.startOfDay(for: now)
        let startOfEventDay = calendar.startOfDay(for: eventDate)
        
        let components = calendar.dateComponents([.day], from: startOfToday, to: startOfEventDay)
        guard let dayDiff = components.day else { return nil }
        
        if dayDiff < 0 {
            return nil // past
        } else if dayDiff == 0 {
            let hour = calendar.component(.hour, from: eventDate)
            return hour >= 17 ? "🎉 Tonight" : "🎉 Today"
        } else if dayDiff == 1 {
            return "☀️ Tomorrow"
        } else if dayDiff <= 5 {
            return "🕒 In \(dayDiff) day\(dayDiff == 1 ? "" : "s")"
        } else {
            return nil
        }
    }
}
