import Foundation

enum ChatFiltering {
    static func apply(chats: [Chat], folder: ChatFolder, searchQuery: String) -> [Chat] {
        let normalizedQuery = normalize(searchQuery)

        return chats
            .filter { chat in
                matchesFolder(chat: chat, folder: folder) && matchesSearch(chat: chat, normalizedQuery: normalizedQuery)
            }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned {
                    return lhs.isPinned && !rhs.isPinned
                }
                return lhs.lastUpdated > rhs.lastUpdated
            }
    }

    static func firstUnreadChat(in chats: [Chat]) -> Chat? {
        apply(chats: chats, folder: .unread, searchQuery: "").first
    }

    private static func matchesFolder(chat: Chat, folder: ChatFolder) -> Bool {
        switch folder {
        case .all:
            return true
        case .unread:
            return chat.unreadCount > 0
        case .personal, .groups, .channels:
            return chat.folder == folder
        }
    }

    private static func matchesSearch(chat: Chat, normalizedQuery: String) -> Bool {
        guard !normalizedQuery.isEmpty else {
            return true
        }

        let haystack = [
            chat.title,
            chat.handle,
            chat.summary,
            chat.participants.joined(separator: " "),
            chat.messages.map(\.text).joined(separator: " ")
        ]
        .joined(separator: " ")

        return normalize(haystack).contains(normalizedQuery)
    }

    private static func normalize(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

