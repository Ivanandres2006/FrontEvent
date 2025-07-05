import SwiftUI

struct TicketValidationView: View {
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
        guard let url = URL(string: "http://localhost:8080/api/tickets/validate/\(code)") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(TokenManager.shared.getAccessToken() ?? "")", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                if let data = data,
                   let json = try? JSONDecoder().decode(ValidatedTicket.self, from: data) {

                    if json.used {
                        resultColor = .red
                        resultText = "❌ Ticket already used\nTier: \(json.tier)"
                    } else {
                        markTicketAsUsed(ticketId: json.ticketId, tier: json.tier)
                    }
                } else {
                    resultColor = .red
                    resultText = "Invalid or unauthorized ticket"
                }
            }
        }.resume()
    }

    private func markTicketAsUsed(ticketId: Int, tier: String) {
        guard let url = URL(string: "http://localhost:8080/api/tickets/validate/\(ticketId)/mark-used") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(TokenManager.shared.getAccessToken() ?? "")", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                if let data = data,
                   let response = try? JSONDecoder().decode(MarkUsedResponse.self, from: data),
                   response.status == "Ticket marked as used" {
                    resultColor = .green
                    resultText = "✅ Ticket used successfully\nTier: \(tier)"
                } else {
                    resultColor = .red
                    resultText = "❌ Failed to mark ticket as used"
                }
            }
        }.resume()
    }

    struct MarkUsedResponse: Decodable {
        let status: String
    }
}

struct ValidatedTicket: Decodable {
    let ticketId: Int
    let event: String
    let tier: String
    let quantity: Int
    let status: String
    let email: String
    let used: Bool
}
