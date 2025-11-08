import SwiftUI

struct OrderReviewView: View {
    @AppStorage("selectedLanguage") var lang: String = "en"

    let order: ResaleOrderDTO
    var onConfirmed: () -> Void

    @Environment(\.dismiss) var dismiss

    @State private var isLoading = false
    @State private var error = ""
    @State private var success = false

    @State private var cancelReason = ""   // NEW

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, .deepNavy], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(lang == "es" ? "Revisar Pago Manual" : "Review Manual Payment")
                        .font(.largeTitle.bold())
                        .foregroundColor(.white)
                        .padding(.top)

                    InfoRow(title: lang == "es" ? "Publicación" : "Listing", value: order.postTitle ?? "—")
                    InfoRow(title: lang == "es" ? "Comprador" : "Buyer", value: (order.buyerUsername ?? order.buyerName) ?? "—")
                    InfoRow(title: lang == "es" ? "Monto" : "Amount", value: String(format: "$%.2f", order.amount))
                    InfoRow(title: lang == "es" ? "Método" : "Method", value: (order.method ?? "").uppercased())
                    InfoRow(title: lang == "es" ? "Referencia" : "Reference", value: order.reference ?? "—")

                    VStack(alignment: .leading, spacing: 6) {
                        Text(lang == "es" ? "Motivo de cancelación (opcional)" : "Cancellation reason (optional)")
                            .foregroundColor(.white.opacity(0.8))
                            .font(.caption)
                        TextField(lang == "es" ? "Escribe el motivo…" : "Type a reason…", text: $cancelReason)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(10)
                    }

                    HStack(spacing: 10) {
                        PillButton(
                            title: lang == "es" ? "Chatear" : "Message",
                            systemImage: "bubble.left.and.bubble.right.fill",
                            background: Color.white.opacity(0.08),
                            foreground: .white
                        ) { openChatWithBuyer() }

                        PillButton(
                            title: lang == "es" ? "Confirmar y Transferir" : "Confirm & Transfer",
                            systemImage: "checkmark.seal.fill",
                            background: .gold,
                            foreground: .black,
                            isLoading: isLoading
                        ) { confirm() }

                        PillButton(
                            title: lang == "es" ? "Cancelar" : "Cancel",
                            systemImage: "xmark.octagon.fill",
                            background: Color.white.opacity(0.1),
                            foreground: .white
                        ) { cancel() }
                    }


                    if !error.isEmpty {
                        Text(error).foregroundColor(.red)
                    }
                    if success {
                        Text(lang == "es" ? "Confirmado ✅" : "Confirmed ✅")
                            .foregroundColor(.green)
                    }

                    Spacer(minLength: 40)
                }
                .padding()
            }
        }
    }

    @ViewBuilder
    func InfoRow(title: String, value: String) -> some View {
        HStack {
            Text(title).bold().foregroundColor(.white)
            Spacer()
            Text(value).foregroundColor(.white.opacity(0.9))
        }
        .padding()
        .background(Color.white.opacity(0.06))
        .cornerRadius(12)
    }

    func openChatWithBuyer() {
        // Hook into your existing Chat screen here if wanted
    }

    func confirm() {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/api/resale/manual/confirm/\(order.id)")
        else { return }

        isLoading = true; error = ""; success = false

        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: r) { _, resp, _ in
            DispatchQueue.main.async { isLoading = false }
            guard let http = resp as? HTTPURLResponse else { return }
            if http.statusCode != 200 {
                DispatchQueue.main.async { error = "Server error: \(http.statusCode)" }
                return
            }
            DispatchQueue.main.async {
                success = true
                onConfirmed()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { dismiss() }
            }
        }.resume()
    }

    func cancel() {
        guard let token = TokenManager.shared.getAccessToken(),
              let url = URL(string: "https://backendevent-etce.onrender.com/api/resale/manual/cancel/\(order.id)")
        else { return }

        isLoading = true; error = ""; success = false

        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["reason": cancelReason])

        URLSession.shared.dataTask(with: r) { _, resp, _ in
            DispatchQueue.main.async { isLoading = false }
            guard let http = resp as? HTTPURLResponse else { return }
            if http.statusCode != 200 {
                DispatchQueue.main.async { error = "Server error: \(http.statusCode)" }
                return
            }
            DispatchQueue.main.async {
                onConfirmed()
                dismiss()
            }
        }.resume()
    }
}

struct PillButton: View {
    let title: String
    let systemImage: String?
    let background: Color
    let foreground: Color
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
                    .font(.headline)
                    .lineLimit(1)                // keep it on one line
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.9)
                    .fixedSize(horizontal: true, vertical: false)

                if isLoading {
                    ProgressView()
                        .tint(foreground)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(background)
            .foregroundColor(foreground)
            .cornerRadius(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

