import Foundation

enum AppTab: Hashable {
    case chats
    case contacts
    case calls
    case settings

    var title: String {
        switch self {
        case .chats:
            return "Chats"
        case .contacts:
            return "Contacts"
        case .calls:
            return "Calls"
        case .settings:
            return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .chats:
            return "bubble.left.and.bubble.right.fill"
        case .contacts:
            return "person.2.fill"
        case .calls:
            return "phone.fill"
        case .settings:
            return "gearshape.fill"
        }
    }
}

enum ChatFolder: String, CaseIterable, Identifiable, Hashable {
    case all
    case unread
    case personal
    case groups
    case channels

    var id: Self { self }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .unread:
            return "Unread"
        case .personal:
            return "Personal"
        case .groups:
            return "Groups"
        case .channels:
            return "Channels"
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            return "tray.full.fill"
        case .unread:
            return "text.badge.star"
        case .personal:
            return "person.fill"
        case .groups:
            return "person.3.fill"
        case .channels:
            return "megaphone.fill"
        }
    }
}

enum MessageDirection: String, Hashable {
    case incoming
    case outgoing
}

enum MessageDeliveryStatus: String, Hashable {
    case sending
    case sent
    case read

    var accessibilityText: String {
        switch self {
        case .sending:
            return "Sending"
        case .sent:
            return "Sent"
        case .read:
            return "Read"
        }
    }
}

enum MessageKind: Hashable {
    case text
    case voice(transcript: String, durationSeconds: Int)
    case photo(description: String)
    case document(description: String, fileName: String?)
    case audio(description: String, durationSeconds: Int?)
    case video(description: String, durationSeconds: Int?)

    var summaryText: String {
        switch self {
        case .text:
            return "Text"
        case let .voice(transcript, durationSeconds):
            return "Voice note, \(durationSeconds) seconds. \(transcript)"
        case let .photo(description):
            return "Photo. \(description)"
        case let .document(description, fileName):
            if let fileName, !fileName.isEmpty {
                return "Document, \(fileName). \(description)"
            }
            return "Document. \(description)"
        case let .audio(description, durationSeconds):
            if let durationSeconds {
                return "Audio, \(durationSeconds) seconds. \(description)"
            }
            return "Audio. \(description)"
        case let .video(description, durationSeconds):
            if let durationSeconds {
                return "Video, \(durationSeconds) seconds. \(description)"
            }
            return "Video. \(description)"
        }
    }
}

enum MessageAttachmentKind: String, Hashable {
    case photo
    case document
    case audio
    case video
    case voiceNote
    case videoNote

    var systemImage: String {
        switch self {
        case .photo:
            return "photo.fill"
        case .document:
            return "doc.fill"
        case .audio:
            return "music.note"
        case .video:
            return "video.fill"
        case .voiceNote:
            return "waveform"
        case .videoNote:
            return "video.bubble.left.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .photo:
            return "Photo attachment"
        case .document:
            return "Document attachment"
        case .audio:
            return "Audio attachment"
        case .video:
            return "Video attachment"
        case .voiceNote:
            return "Voice note"
        case .videoNote:
            return "Video note"
        }
    }

    var supportsInlinePlayback: Bool {
        switch self {
        case .audio, .voiceNote:
            return true
        case .photo, .document, .video, .videoNote:
            return false
        }
    }
}

struct MessageAttachment: Hashable {
    var kind: MessageAttachmentKind
    var fileName: String? = nil
    var mimeType: String? = nil
    var durationSeconds: Int? = nil
    var telegramFileID: Int? = nil
    var localPath: String? = nil
    var width: Int? = nil
    var height: Int? = nil

    var localURL: URL? {
        guard let localPath else {
            return nil
        }

        let trimmedPath = localPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: trimmedPath)
    }

    var isAvailableLocally: Bool {
        guard let localURL else {
            return false
        }
        return FileManager.default.fileExists(atPath: localURL.path)
    }
}

struct Message: Identifiable, Hashable {
    let id: UUID
    var sender: String
    var text: String
    var timestamp: Date
    var direction: MessageDirection
    var status: MessageDeliveryStatus
    var kind: MessageKind
    var attachment: MessageAttachment? = nil
    var isPinned: Bool = false
    var telegramMessageID: Int64? = nil

    var timestampLabel: String {
        timestamp.formatted(date: .omitted, time: .shortened)
    }

    func voiceOverLabel(speakContext: Bool) -> String {
        let contextPrefix = speakContext ? "\(sender), \(timestampLabel)." : ""
        switch kind {
        case .text:
            return "\(contextPrefix) \(text)".trimmingCharacters(in: .whitespaces)
        case .voice:
            return "\(contextPrefix) \(kind.summaryText)".trimmingCharacters(in: .whitespaces)
        case .photo, .document, .audio, .video:
            return "\(contextPrefix) \(kind.summaryText)".trimmingCharacters(in: .whitespaces)
        }
    }
}

struct Chat: Identifiable, Hashable {
    let id: UUID
    var title: String
    var handle: String
    var summary: String
    var folder: ChatFolder
    var unreadCount: Int
    var isMuted: Bool
    var isPinned: Bool
    var participants: [String]
    var participantSummary: String? = nil
    var lastUpdated: Date
    var messages: [Message]
    var avatarHue: Double
    var telegramChatID: Int64? = nil

    var initials: String {
        let initials = title
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
        return initials.isEmpty ? "#" : initials
    }

    var lastUpdatedLabel: String {
        if Calendar.current.isDateInToday(lastUpdated) {
            return lastUpdated.formatted(date: .omitted, time: .shortened)
        }
        return lastUpdated.formatted(date: .abbreviated, time: .omitted)
    }

    var accessibilityStatus: String {
        var segments: [String] = []
        if unreadCount > 0 {
            segments.append("\(unreadCount) unread")
        }
        if isMuted {
            segments.append("Muted")
        }
        if isPinned {
            segments.append("Pinned")
        }
        return segments.joined(separator: ", ")
    }

    var participantDescription: String {
        if let participantSummary, !participantSummary.isEmpty {
            return participantSummary
        }
        return "\(participants.count) participant\(participants.count == 1 ? "" : "s")"
    }

    func voiceOverLabel(speakContext: Bool) -> String {
        let base = "\(title). \(summary). Updated \(lastUpdatedLabel)."
        if speakContext, let latest = messages.last {
            return "\(base) Latest message: \(latest.voiceOverLabel(speakContext: false))"
        }
        return base
    }
}

enum ContactPresence: String, Hashable {
    case online
    case away
    case focus

    var description: String {
        switch self {
        case .online:
            return "Online"
        case .away:
            return "Away"
        case .focus:
            return "Notifications muted"
        }
    }
}

struct Contact: Identifiable, Hashable {
    let id: UUID
    var name: String
    var role: String
    var presence: ContactPresence
    var isFavorite: Bool
    var avatarHue: Double
    var note: String
    var telegramUserID: Int64? = nil

    var initials: String {
        let initials = name
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
        return initials.isEmpty ? "#" : initials
    }
}

enum CallDirection: Hashable {
    case incoming
    case outgoing
    case missed

    var label: String {
        switch self {
        case .incoming:
            return "Incoming"
        case .outgoing:
            return "Outgoing"
        case .missed:
            return "Missed"
        }
    }

    var systemImage: String {
        switch self {
        case .incoming:
            return "phone.arrow.down.left.fill"
        case .outgoing:
            return "phone.arrow.up.right.fill"
        case .missed:
            return "phone.down.fill"
        }
    }
}

struct CallLog: Identifiable, Hashable {
    let id: UUID
    var personName: String
    var direction: CallDirection
    var time: Date
    var durationDescription: String
    var note: String
    var isVideo: Bool = false
    var telegramUserID: Int64? = nil

    var timeLabel: String {
        if Calendar.current.isDateInToday(time) {
            return time.formatted(date: .omitted, time: .shortened)
        }
        return time.formatted(date: .abbreviated, time: .shortened)
    }
}

struct AccessibilityPreferences: Hashable {
    var announceUnreadMessages = true
    var speakMessageContext = true
    var preferCompactMediaDescriptions = false
    var focusComposerOnOpen = true
    var prioritizeUnreadChatsShortcut = true
}

struct UniOSSeedData: Hashable {
    var chats: [Chat]
    var contacts: [Contact]
    var calls: [CallLog]
    var accessibilityPreferences: AccessibilityPreferences
}
