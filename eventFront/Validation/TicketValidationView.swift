import SwiftUI
import AVFoundation

struct TicketValidationView: View {
    @AppStorage("selectedLanguage") var lang: String = "en"

    @State private var scannedCode: String?
    @State private var resultColor: Color = .gray
    @State private var resultText: String = "Scan a QR code"
    @State private var isLoading = false

    // we’ll use this to “restart” the scanner by changing the view identity
    @State private var shouldRestartScanner = false

    var body: some View {
        VStack(spacing: 20) {
            // Scanner
            QRScannerView { raw in
                scannedCode = raw
                handleScan(raw)
            }
            .id(shouldRestartScanner) // <— replaces .restartScanner(...)
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            // Result banner
            HStack(spacing: 10) {
                Circle().fill(resultColor).frame(width: 10, height: 10)
                Text(resultText)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Spacer()
                if isLoading { ProgressView() }
            }
            .padding()
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08)))

            if let scanned = scannedCode {
                Text("\(lang == "es" ? "Último:" : "Last:") \(scanned)")
                    .foregroundColor(.white.opacity(0.6))
                    .font(.footnote)
            }

            Spacer()
        }
        .padding()
        .background(
            LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }

    // MARK: - Scan flow

    private func handleScan(_ raw: String) {
        isLoading = true

        guard let ticketId = parseTicketId(from: raw) else {
            isLoading = false
            showBanner(text: lang == "es" ? "QR inválido" : "Invalid QR", color: .red)
            softRestart()
            return
        }
        validateTicket(ticketId)
    }

    /// Accepts plain "123" OR "TICKET:123:email"
    private func parseTicketId(from code: String) -> Int? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = Int(trimmed) { return id }
        let parts = trimmed.split(separator: ":")
        if parts.count >= 2, parts[0].uppercased() == "TICKET",
           let id = Int(parts[1]) { return id }
        return nil
    }

    private func validateTicket(_ ticketId: Int) {
        guard
            let token = TokenManager.shared.getAccessToken(),
            let url = URL(string: "https://backendevent-etce.onrender.com/api/tickets/validate/\(ticketId)")
        else {
            isLoading = false
            showBanner(text: lang == "es" ? "Sesión inválida" : "Invalid session", color: .red)
            softRestart()
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, response, _ in
            DispatchQueue.main.async {
                guard
                    let http = response as? HTTPURLResponse, http.statusCode == 200,
                    let data = data,
                    let json = try? JSONDecoder().decode(ValidatedTicket.self, from: data)
                else {
                    self.isLoading = false
                    self.showBanner(text: self.lang == "es" ? "Entrada inválida o no autorizada" : "Invalid or unauthorized ticket", color: .red)
                    self.softRestart()
                    return
                }

                if json.used {
                    self.isLoading = false
                    self.showBanner(
                        text: self.lang == "es" ? "❌ Ya utilizada · Nivel: \(json.tier)" : "❌ Already used · Tier: \(json.tier)",
                        color: .red
                    )
                    self.softRestart()
                } else {
                    self.markTicketAsUsed(ticketId: json.ticketId, tier: json.tier)
                }
            }
        }.resume()
    }

    private func markTicketAsUsed(ticketId: Int, tier: String) {
        guard
            let token = TokenManager.shared.getAccessToken(),
            let url = URL(string: "https://backendevent-etce.onrender.com/api/tickets/validate/\(ticketId)/mark-used")
        else {
            isLoading = false
            showBanner(text: lang == "es" ? "Sesión inválida" : "Invalid session", color: .red)
            softRestart()
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, response, _ in
            DispatchQueue.main.async {
                self.isLoading = false
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    self.showBanner(
                        text: self.lang == "es" ? "✅ Entrada escaneada · \(tier)" : "✅ Ticket scanned · \(tier)",
                        color: .green
                    )
                } else {
                    self.showBanner(
                        text: self.lang == "es" ? "❌ No se pudo marcar como usada" : "❌ Failed to mark as used",
                        color: .red
                    )
                }
                self.softRestart()
            }
        }.resume()
    }

    private func showBanner(text: String, color: Color) {
        self.resultText = text
        self.resultColor = color
    }

    /// Reset banner after a short delay and recreate the scanner view.
    private func softRestart() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            self.resultText = "Scan a QR code"
            self.resultColor = .gray
            self.shouldRestartScanner.toggle() // forces QRScannerView recreation
        }
    }
}
