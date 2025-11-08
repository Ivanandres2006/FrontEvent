import Foundation
import CryptoKit

enum ContactHasher {
    // Keep in sync with server PEPPER
    private static let pepper = "change-me-in-prod"

    static func hashEmail(_ email: String) -> String {
        let norm = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return sha256(norm + pepper)
    }

    static func hashPhone(_ phone: String) -> String {
        let norm = phone.filter(\.isNumber) // keep digits
        return sha256(norm + pepper)
    }

    private static func sha256(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
