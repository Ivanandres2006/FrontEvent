//
//  ChatTypesAndDTOs.swift
//  eventFront
//

import Foundation

// Matches BE enum values (and tolerates legacy GROUP)
enum ChatRoomType: String, Codable {
    case DIRECT, RESALE, PROMOTER_GROUP, ADMIN

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "DIRECT": self = .DIRECT
        case "RESALE": self = .RESALE
        case "PROMOTER_GROUP", "GROUP": self = .PROMOTER_GROUP
        case "ADMIN": self = .ADMIN
        default: self = .DIRECT // be permissive
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(self.rawValue)
    }
}


/// Matches dbeventservice/dto/ChatRoomSummaryDTO.java
struct ChatRoomSummaryDTO: Identifiable, Codable, Equatable, Hashable {
    let id: Int
    let type: ChatRoomType
    let displayName: String
    let iconUrl: String?
    let lastMessagePreview: String?
    let lastMessageAt: Date?
    let unreadCount: Int

    enum CodingKeys: String, CodingKey {
        case id, type, displayName, iconUrl, lastMessagePreview, lastMessageAt, unreadCount
    }
}

struct ChatMessageDTO: Identifiable, Decodable, Equatable, Hashable {
    let id: Int
    let chatId: Int
    let senderId: Int?
    let senderUsername: String?
    let text: String?
    let attachmentUrl: String?
    let type: MessageType
    let createdAt: Date
    let metaJson: String?     // 👈 add this

    enum MessageType: String, Codable { case TEXT, IMAGE, OFFER, SYSTEM } // 👈

    enum CodingKeys: String, CodingKey {
        case id, chatId, senderId, senderUsername, text, type, createdAt, metaJson
        case attachmentUrl            // primary key used by BE
        case imageUrl                 // fallback for old payloads
    }
    
    // ✅ Decoding init (kept as-is)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decode(Int.self, forKey: .id)
        chatId        = try c.decode(Int.self, forKey: .chatId)
        senderId      = try c.decodeIfPresent(Int.self, forKey: .senderId)
        senderUsername = try c.decodeIfPresent(String.self, forKey: .senderUsername)
        text          = try c.decodeIfPresent(String.self, forKey: .text)
        type          = try c.decode(MessageType.self, forKey: .type)
        createdAt     = try c.decode(Date.self, forKey: .createdAt)
        metaJson      = try c.decodeIfPresent(String.self, forKey: .metaJson)
        attachmentUrl = try c.decodeIfPresent(String.self, forKey: .attachmentUrl)
        ?? c.decodeIfPresent(String.self, forKey: .imageUrl)
    }

    init(id: Int,
             chatId: Int,
             senderId: Int?,
             senderUsername: String?,
             text: String?,
             attachmentUrl: String?,
             type: MessageType,
             createdAt: Date,
             metaJson: String?) {
            self.id = id
            self.chatId = chatId
            self.senderId = senderId
            self.senderUsername = senderUsername
            self.text = text
            self.attachmentUrl = attachmentUrl
            self.type = type
            self.createdAt = createdAt
            self.metaJson = metaJson
        }

    func replacing(metaJson: String?) -> ChatMessageDTO {
        .init(id: id,
              chatId: chatId,
              senderId: senderId,
              senderUsername: senderUsername,
              text: text,
              attachmentUrl: attachmentUrl,
              type: type,
              createdAt: createdAt,
              metaJson: metaJson)
    }
}

// Convenience decode for offers
struct OfferMeta: Decodable {
    let kind: String?
    let amount: Double?
    let currency: String?
    let authorId: Int?
    let status: String?
    let parentId: Int?
    let resalePostId: Int?
}

