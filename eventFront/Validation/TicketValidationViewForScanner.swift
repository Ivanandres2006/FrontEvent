import SwiftUI

struct TicketValidationViewForScanner: View {
    let eventId: Int

    @State private var scannedCode: String?
    @State private var resultColor: Color = .gray
    @State private var resultText: String = "Scan a QR code"
    @State private var shouldRestartScanner = false

    var body: some View {
        VStack(spacing: 20) {
            QRScannerView { code in
                self.scannedCode = code
                validateTicket(code)
            }
            .restartScanner(shouldRestartScanner)
            .frame(height: 300)
            .cornerRadius(16)

            Text(resultText)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(resultColor)
                .multilineTextAlignment(.center)
                .padding()

            if let scanned = scannedCode {
                Text("Ticket ID: \(scanned)")
                    .foregroundColor(.white.opacity(0.6))
                    .font(.footnote)
            }

            Spacer()
        }
        .padding()
        .background(LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    private func validateTicket(_ code: String) {
        guard let url = URL(string: "http://localhost:8080/api/tickets/validate/\(code)"),
              let token = TokenManager.shared.getAccessToken() else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                if let data = data,
                   let json = try? JSONDecoder().decode(ValidatedTicket.self, from: data),
                   json.eventId == eventId {

                    if json.used {
                        resultColor = .red
                        resultText = "❌ Already used\nTier: \(json.tier)"
                    } else {
                        markTicketAsUsed(ticketId: json.ticketId, tier: json.tier)
                    }
                } else {
                    resultColor = .red
                    resultText = "🚫 Invalid or wrong event ticket"
                }
            }
        }.resume()
    }

    private func markTicketAsUsed(ticketId: Int, tier: String) {
        guard let url = URL(string: "http://localhost:8080/api/tickets/validate/\(ticketId)/mark-used"),
              let token = TokenManager.shared.getAccessToken() else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                if let data = data,
                   let response = try? JSONDecoder().decode(MarkUsedResponse.self, from: data),
                   response.status == "Ticket marked as used" {
                    resultColor = .green
                    resultText = "✅ Ticket scanned\nTier: \(tier)"
                } else {
                    resultColor = .red
                    resultText = "❌ Failed to mark as used"
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    resultText = "Scan a QR code"
                    resultColor = .gray
                    shouldRestartScanner.toggle()
                }
            }
        }.resume()
    }

    struct ValidatedTicket: Decodable {
        let ticketId: Int
        let event: String
        let tier: String
        let quantity: Int
        let status: String
        let email: String
        let used: Bool
        let eventId: Int
    }

    struct MarkUsedResponse: Decodable {
        let status: String
    }
}
