import Foundation
#if canImport(UIKit)
import UIKit
#endif
import TDLibKit

enum SessionSource: Hashable {
    case demo
    case telegram
}

struct TelegramAccountProfile: Hashable {
    let userID: Int64
    var displayName: String
    var username: String?
    var phoneNumber: String

    var handle: String {
        if let username, !username.isEmpty {
            return "@\(username)"
        }
        return phoneNumber.isEmpty ? "Telegram account" : phoneNumber
    }
}

enum TelegramSignInState: Hashable {
    case unavailable(message: String)
    case waitingForPhone
    case working(message: String)
    case waitingForCode(message: String)
    case waitingForPassword(hint: String)
    case ready
    case failed(message: String)

    var statusMessage: String {
        switch self {
        case let .unavailable(message):
            return message
        case .waitingForPhone:
            return "Enter the phone number for your Telegram account."
        case let .working(message):
            return message
        case let .waitingForCode(message):
            return message
        case let .waitingForPassword(hint):
            return hint.isEmpty ? "Enter your Telegram two-step verification password." : "Enter your Telegram two-step verification password. Hint: \(hint)."
        case .ready:
            return "Telegram is ready."
        case let .failed(message):
            return message
        }
    }

    var acceptsPhoneNumber: Bool {
        if case .waitingForPhone = self {
            return true
        }
        return false
    }

    var acceptsCode: Bool {
        if case .waitingForCode = self {
            return true
        }
        return false
    }

    var acceptsPassword: Bool {
        if case .waitingForPassword = self {
            return true
        }
        return false
    }

    var isWorking: Bool {
        if case .working = self {
            return true
        }
        return false
    }
}

enum TelegramServiceEvent: Hashable {
    case authorizationChanged(TelegramSignInState)
    case chatsChanged
    case chatChanged(chatID: Int64)
}

@MainActor
protocol TelegramServiceDelegate: AnyObject {
    func telegramService(_ service: TelegramService, didReceive event: TelegramServiceEvent)
}

final class TelegramService {
    weak var delegate: (any TelegramServiceDelegate)?

    private let configuration: TelegramAppConfiguration
    private let manager: TDLibClientManager
    private let client: TDLibClient

    init(configuration: TelegramAppConfiguration) {
        self.configuration = configuration
        self.manager = TDLibClientManager()
        self.client = manager.createClient(updateHandler: { [weak self] data, _ in
            self?.handleUpdate(data)
        })
    }

    deinit {
        manager.closeClients()
    }

    func start() async throws -> TelegramSignInState {
        let state = try await client.getAuthorizationState()
        return try await applyAuthorizationState(state)
    }

    func submitPhoneNumber(_ phoneNumber: String) async throws {
        let settings = PhoneNumberAuthenticationSettings(
            allowFlashCall: false,
            allowMissedCall: false,
            allowSmsRetrieverApi: false,
            authenticationTokens: [],
            firebaseAuthenticationSettings: nil,
            hasUnknownPhoneNumber: false,
            isCurrentPhoneNumber: false
        )
        _ = try await client.setAuthenticationPhoneNumber(phoneNumber: phoneNumber, settings: settings)
    }

    func submitCode(_ code: String) async throws {
        _ = try await client.checkAuthenticationCode(code: code)
    }

    func submitPassword(_ password: String) async throws {
        _ = try await client.checkAuthenticationPassword(password: password)
    }

    func logOut() async throws {
        _ = try await client.logOut()
    }

    func loadCurrentProfile() async throws -> TelegramAccountProfile {
        let me = try await client.getMe()
        return TelegramAccountProfile(
            userID: me.id,
            displayName: Self.displayName(for: me),
            username: me.usernames?.activeUsernames.first,
            phoneNumber: me.phoneNumber
        )
    }

    func loadChats(limit: Int, currentUserDisplayName: String) async throws -> [Chat] {
        let response = try await client.getChats(chatList: .chatListMain, limit: limit)
        var mappedChats: [Chat] = []
        mappedChats.reserveCapacity(response.chatIds.count)

        for chatID in response.chatIds {
            let chat = try await loadChat(chatID: chatID, currentUserDisplayName: currentUserDisplayName)
            mappedChats.append(chat)
        }

        return mappedChats
    }

    func loadChat(chatID: Int64, currentUserDisplayName: String) async throws -> Chat {
        let tdChat = try await client.getChat(chatId: chatID)
        return try await mapChat(tdChat, currentUserDisplayName: currentUserDisplayName)
    }

    func loadMessages(chatID: Int64, currentUserDisplayName: String, limit: Int = 40) async throws -> [Message] {
        let tdChat = try await client.getChat(chatId: chatID)
        _ = try await client.openChat(chatId: chatID)
        let history = try await client.getChatHistory(
            chatId: chatID,
            fromMessageId: 0,
            limit: limit,
            offset: 0,
            onlyLocal: false
        )

        let historyMessages = Array((history.messages ?? []).reversed())
        if !historyMessages.isEmpty {
            let ids = historyMessages.map(\.id)
            try? await client.viewMessages(
                chatId: chatID,
                forceRead: true,
                messageIds: ids,
                source: nil
            )
        }

        var mappedMessages: [Message] = []
        mappedMessages.reserveCapacity(historyMessages.count)

        for message in historyMessages {
            let mappedMessage = try await mapMessage(
                message,
                chat: tdChat,
                currentUserDisplayName: currentUserDisplayName
            )
            mappedMessages.append(mappedMessage)
        }

        return mappedMessages
    }

    func sendText(_ text: String, to chatID: Int64) async throws {
        let content = InputMessageContent.inputMessageText(
            InputMessageText(
                clearDraft: true,
                linkPreviewOptions: nil,
                text: FormattedText(entities: [], text: text)
            )
        )

        _ = try await client.sendMessage(
            chatId: chatID,
            inputMessageContent: content,
            options: nil,
            replyMarkup: nil,
            replyTo: nil,
            topicId: nil
        )
    }

    func markViewed(chatID: Int64, messageIDs: [Int64]) async {
        guard !messageIDs.isEmpty else {
            return
        }

        try? await client.viewMessages(
            chatId: chatID,
            forceRead: true,
            messageIds: messageIDs,
            source: nil
        )
    }

    func loadContacts(limit: Int) async throws -> [Contact] {
        let response = try await client.getContacts()
        var contacts: [Contact] = []
        contacts.reserveCapacity(min(limit, response.userIds.count))

        for userID in response.userIds.prefix(limit) {
            let user = try await client.getUser(userId: userID)
            contacts.append(mapContact(user))
        }

        return contacts.sorted {
            if $0.isFavorite != $1.isFavorite {
                return $0.isFavorite && !$1.isFavorite
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func createPrivateChat(for userID: Int64, currentUserDisplayName: String) async throws -> Chat {
        let chat = try await client.createPrivateChat(force: false, userId: userID)
        return try await mapChat(chat, currentUserDisplayName: currentUserDisplayName)
    }

    private func handleUpdate(_ data: Data) {
        guard let update = try? client.decoder.decode(Update.self, from: data) else {
            return
        }

        switch update {
        case let .updateAuthorizationState(value):
            Task { [weak self] in
                guard let self else {
                    return
                }

                do {
                    _ = try await self.applyAuthorizationState(value.authorizationState)
                } catch {
                    self.notify(.authorizationChanged(.failed(message: self.userFacingMessage(for: error))))
                }
            }

        case .updateNewChat:
            notify(.chatsChanged)

        case let .updateChatTitle(value):
            notify(.chatChanged(chatID: value.chatId))

        case let .updateChatLastMessage(value):
            notify(.chatChanged(chatID: value.chatId))

        case let .updateChatPosition(value):
            notify(.chatChanged(chatID: value.chatId))

        case let .updateChatReadInbox(value):
            notify(.chatChanged(chatID: value.chatId))

        case let .updateChatIsMarkedAsUnread(value):
            notify(.chatChanged(chatID: value.chatId))

        case let .updateNewMessage(value):
            notify(.chatChanged(chatID: value.message.chatId))

        default:
            break
        }
    }

    private func notify(_ event: TelegramServiceEvent) {
        Task { @MainActor [weak self] in
            guard let self, let delegate else {
                return
            }
            delegate.telegramService(self, didReceive: event)
        }
    }

    @discardableResult
    private func applyAuthorizationState(_ state: AuthorizationState) async throws -> TelegramSignInState {
        let mappedState = try await mapAuthorizationState(state)
        notify(.authorizationChanged(mappedState))
        return mappedState
    }

    private func mapAuthorizationState(_ state: AuthorizationState) async throws -> TelegramSignInState {
        switch state {
        case .authorizationStateWaitTdlibParameters:
            try await configureTDLib()
            return .working(message: "Preparing the Telegram session.")

        case .authorizationStateWaitPhoneNumber:
            return .waitingForPhone

        case let .authorizationStateWaitCode(value):
            let message = "Enter the Telegram code sent to \(value.codeInfo.phoneNumber)."
            return .waitingForCode(message: message)

        case let .authorizationStateWaitPassword(value):
            return .waitingForPassword(hint: value.passwordHint)

        case .authorizationStateReady:
            return .ready

        case .authorizationStateLoggingOut:
            return .working(message: "Signing out from Telegram.")

        case .authorizationStateClosing, .authorizationStateClosed:
            return .working(message: "Closing the Telegram session.")

        case .authorizationStateWaitOtherDeviceConfirmation:
            return .failed(message: "QR-code Telegram login is not wired into this build yet.")

        case .authorizationStateWaitRegistration:
            return .failed(message: "New account registration is not wired into this build yet.")

        case .authorizationStateWaitPremiumPurchase:
            return .failed(message: "Telegram Premium purchase confirmation is not supported in this build.")

        case .authorizationStateWaitEmailAddress, .authorizationStateWaitEmailCode:
            return .failed(message: "Email-based Telegram authorization is not supported in this build.")
        }
    }

    private func configureTDLib() async throws {
        let directories = try runtimeDirectories()

        _ = try await client.setTdlibParameters(
            apiHash: configuration.apiHash,
            apiId: configuration.apiID,
            applicationVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0",
            databaseDirectory: directories.databaseDirectory.path,
            databaseEncryptionKey: Data(),
            deviceModel: deviceModel,
            filesDirectory: directories.filesDirectory.path,
            systemLanguageCode: Locale.current.language.languageCode?.identifier ?? Locale.current.identifier,
            systemVersion: operatingSystemVersion,
            useChatInfoDatabase: true,
            useFileDatabase: true,
            useMessageDatabase: true,
            useSecretChats: true,
            useTestDc: configuration.useTestDC
        )
    }

    private func runtimeDirectories(fileManager: FileManager = .default) throws -> (databaseDirectory: URL, filesDirectory: URL) {
        let baseDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let tdlibRoot = baseDirectory.appendingPathComponent("TelegramTDLib", isDirectory: true)
        let databaseDirectory = tdlibRoot.appendingPathComponent("database", isDirectory: true)
        let filesDirectory = tdlibRoot.appendingPathComponent("files", isDirectory: true)

        try fileManager.createDirectory(at: databaseDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: filesDirectory, withIntermediateDirectories: true)

        return (databaseDirectory, filesDirectory)
    }

    private var deviceModel: String {
        #if canImport(UIKit)
        UIDevice.current.model
        #else
        "Apple device"
        #endif
    }

    private var operatingSystemVersion: String {
        #if canImport(UIKit)
        UIDevice.current.systemVersion
        #else
        ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }

    private func mapChat(_ tdChat: TDLibKit.Chat, currentUserDisplayName: String) async throws -> Chat {
        let previewMessage: Message?
        if let lastMessage = tdChat.lastMessage {
            previewMessage = try await mapMessage(lastMessage, chat: tdChat, currentUserDisplayName: currentUserDisplayName)
        } else {
            previewMessage = nil
        }
        let handle = try await chatHandle(for: tdChat)

        return Chat(
            id: StableIdentifier.chatUUID(for: tdChat.id),
            title: tdChat.title,
            handle: handle,
            summary: messageSummary(from: tdChat.lastMessage?.content),
            folder: try await folder(for: tdChat),
            unreadCount: tdChat.unreadCount,
            isMuted: isMuted(tdChat),
            isPinned: tdChat.positions.contains(where: \.isPinned),
            participants: try await participants(for: tdChat),
            participantSummary: try await participantSummary(for: tdChat),
            lastUpdated: messageDate(for: tdChat.lastMessage?.date),
            messages: previewMessage.map { [$0] } ?? [],
            avatarHue: avatarHue(for: tdChat.accentColorId),
            telegramChatID: tdChat.id
        )
    }

    private func mapMessage(
        _ tdMessage: TDLibKit.Message,
        chat tdChat: TDLibKit.Chat,
        currentUserDisplayName: String
    ) async throws -> Message {
        let mappedContent = mappedMessageContent(tdMessage.content)
        return Message(
            id: StableIdentifier.messageUUID(chatID: tdMessage.chatId, messageID: tdMessage.id),
            sender: try await senderName(for: tdMessage, currentUserDisplayName: currentUserDisplayName),
            text: mappedContent.text,
            timestamp: messageDate(for: tdMessage.date),
            direction: tdMessage.isOutgoing ? .outgoing : .incoming,
            status: deliveryStatus(for: tdMessage, chat: tdChat),
            kind: mappedContent.kind,
            isPinned: tdMessage.isPinned,
            telegramMessageID: tdMessage.id
        )
    }

    private func senderName(for message: TDLibKit.Message, currentUserDisplayName: String) async throws -> String {
        if message.isOutgoing {
            return currentUserDisplayName
        }

        switch message.senderId {
        case let .messageSenderUser(value):
            let user = try await client.getUser(userId: value.userId)
            return Self.displayName(for: user)

        case let .messageSenderChat(value):
            let chat = try await client.getChat(chatId: value.chatId)
            return chat.title
        }
    }

    private func mappedMessageContent(_ content: TDLibKit.MessageContent) -> (text: String, kind: MessageKind) {
        switch content {
        case let .messageText(value):
            let text = nonEmptyText(value.text.text) ?? "Message"
            return (text, .text)

        case let .messagePhoto(value):
            let description = nonEmptyText(value.caption.text) ?? "Photo attachment"
            return (description, .photo(description: description))

        case let .messageVoiceNote(value):
            let transcript = nonEmptyText(value.caption.text) ?? "Voice note"
            return (transcript, .voice(transcript: transcript, durationSeconds: value.voiceNote.duration))

        case let .messageAudio(value):
            let description = nonEmptyText(value.caption.text) ?? "Audio attachment"
            return (description, .text)

        case let .messageDocument(value):
            let description = nonEmptyText(value.caption.text) ?? "Document attachment"
            return (description, .text)

        case let .messageAnimation(value):
            let description = nonEmptyText(value.caption.text) ?? "Animation"
            return (description, .text)

        case let .messageVideo(value):
            let description = nonEmptyText(value.caption.text) ?? "Video attachment"
            return (description, .text)

        case .messageSticker:
            return ("Sticker", .text)

        case .messageLocation:
            return ("Location", .text)

        case .messageContact:
            return ("Shared contact", .text)

        case .messagePoll:
            return ("Poll", .text)

        default:
            return ("Unsupported message type", .text)
        }
    }

    private func messageSummary(from content: TDLibKit.MessageContent?) -> String {
        guard let content else {
            return "No messages yet."
        }
        return mappedMessageContent(content).text
    }

    private func folder(for chat: TDLibKit.Chat) async throws -> ChatFolder {
        switch chat.type {
        case .chatTypePrivate:
            return .personal

        case .chatTypeSecret:
            return .personal

        case .chatTypeBasicGroup:
            return .groups

        case let .chatTypeSupergroup(value):
            return value.isChannel ? .channels : .groups
        }
    }

    private func participants(for chat: TDLibKit.Chat) async throws -> [String] {
        switch chat.type {
        case let .chatTypePrivate(value):
            let user = try await client.getUser(userId: value.userId)
            return [Self.displayName(for: user)]

        case let .chatTypeSecret(value):
            let user = try await client.getUser(userId: value.userId)
            return [Self.displayName(for: user)]

        default:
            return []
        }
    }

    private func participantSummary(for chat: TDLibKit.Chat) async throws -> String {
        switch chat.type {
        case let .chatTypePrivate(value):
            let user = try await client.getUser(userId: value.userId)
            let me = try? await client.getMe()
            return user.id == me?.id ? "Saved messages" : "1 participant"

        case let .chatTypeSecret(value):
            _ = try await client.getUser(userId: value.userId)
            return "Secret chat"

        case let .chatTypeBasicGroup(value):
            let group = try await client.getBasicGroup(basicGroupId: value.basicGroupId)
            return "\(group.memberCount) members"

        case let .chatTypeSupergroup(value):
            let supergroup = try await client.getSupergroup(supergroupId: value.supergroupId)
            if value.isChannel {
                return "Channel"
            }
            if supergroup.memberCount > 0 {
                return "\(supergroup.memberCount) members"
            }
            return "Group conversation"
        }
    }

    private func chatHandle(for chat: TDLibKit.Chat) async throws -> String {
        switch chat.type {
        case let .chatTypePrivate(value):
            let user = try await client.getUser(userId: value.userId)
            if let username = user.usernames?.activeUsernames.first, !username.isEmpty {
                return "@\(username)"
            }
            return user.phoneNumber.isEmpty ? "Telegram chat" : user.phoneNumber

        case let .chatTypeSecret(value):
            let user = try await client.getUser(userId: value.userId)
            if let username = user.usernames?.activeUsernames.first, !username.isEmpty {
                return "@\(username)"
            }
            return "Secret chat"

        case let .chatTypeSupergroup(value):
            let supergroup = try await client.getSupergroup(supergroupId: value.supergroupId)
            if let username = supergroup.usernames?.activeUsernames.first, !username.isEmpty {
                return "@\(username)"
            }
            return value.isChannel ? "Channel" : "Group"

        case .chatTypeBasicGroup:
            return "Group"
        }
    }

    private func deliveryStatus(for message: TDLibKit.Message, chat: TDLibKit.Chat) -> MessageDeliveryStatus {
        if message.sendingState != nil {
            return .sending
        }

        guard message.isOutgoing else {
            return .read
        }

        if chat.lastReadOutboxMessageId >= message.id, chat.lastReadOutboxMessageId != 0 {
            return .read
        }

        return .sent
    }

    private func mapContact(_ user: TDLibKit.User) -> Contact {
        let username = user.usernames?.activeUsernames.first
        let note = username.map { "@\($0)" } ?? (user.phoneNumber.isEmpty ? "Telegram contact" : user.phoneNumber)

        return Contact(
            id: StableIdentifier.chatUUID(for: user.id),
            name: Self.displayName(for: user),
            role: user.isMutualContact ? "Mutual Telegram contact" : "Telegram contact",
            presence: contactPresence(for: user.status),
            isFavorite: user.isCloseFriend || user.isMutualContact,
            avatarHue: avatarHue(for: user.accentColorId),
            note: note,
            telegramUserID: user.id
        )
    }

    private func contactPresence(for status: UserStatus) -> ContactPresence {
        switch status {
        case .userStatusOnline:
            return .online

        case .userStatusOffline, .userStatusRecently:
            return .away

        case .userStatusLastWeek, .userStatusLastMonth, .userStatusEmpty:
            return .focus
        }
    }

    private func avatarHue(for accentColorID: Int) -> Double {
        let normalized = abs(accentColorID % 24)
        return Double(normalized) / 24.0
    }

    private func isMuted(_ chat: TDLibKit.Chat) -> Bool {
        !chat.notificationSettings.useDefaultMuteFor && chat.notificationSettings.muteFor > 0
    }

    private func messageDate(for timestamp: Int?) -> Foundation.Date {
        guard let timestamp, timestamp > 0 else {
            return .now
        }
        return Foundation.Date(timeIntervalSince1970: TimeInterval(timestamp))
    }

    private func userFacingMessage(for error: Error) -> String {
        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return description.isEmpty ? "Telegram request failed." : description
    }

    private static func displayName(for user: TDLibKit.User) -> String {
        let parts = [user.firstName, user.lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if !parts.isEmpty {
            return parts.joined(separator: " ")
        }

        if let username = user.usernames?.activeUsernames.first, !username.isEmpty {
            return "@\(username)"
        }

        return user.phoneNumber.isEmpty ? "Telegram user" : user.phoneNumber
    }

    private func nonEmptyText(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
