import Foundation

struct ReferredBuyerDTO: Codable, Identifiable {
    let id: Int              // 👈 Coming from backend (e.g. PromoterSale ID)
    let username: String
    let email: String
    let timestamp: String
    
    let quantity: Int?
    let unitPrice: Double?
}
