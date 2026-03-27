import CryptoKit
import Foundation
import TDLibKit

enum StableIdentifier {
    static func chatUUID(for telegramChatID: Int64) -> UUID {
        uuid(seed: "telegram-chat-\(telegramChatID)")
    }

    static func chatUUID(for telegramChatID: TdInt64) -> UUID {
        chatUUID(for: telegramChatID.rawValue)
    }

    static func messageUUID(chatID: Int64, messageID: Int64) -> UUID {
        uuid(seed: "telegram-chat-\(chatID)-message-\(messageID)")
    }

    static func messageUUID(chatID: TdInt64, messageID: TdInt64) -> UUID {
        messageUUID(chatID: chatID.rawValue, messageID: messageID.rawValue)
    }

    private static func uuid(seed: String) -> UUID {
        let digest = SHA256.hash(data: Data(seed.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
