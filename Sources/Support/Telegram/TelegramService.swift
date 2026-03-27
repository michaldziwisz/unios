import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
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
    case waitingForEmailAddress(message: String)
    case waitingForEmailCode(message: String, emailPattern: String, codeLength: Int)
    case working(message: String)
    case waitingForCode(message: String)
    case waitingForOtherDeviceConfirmation(message: String, link: String)
    case waitingForPassword(hint: String)
    case ready
    case failed(message: String)

    var statusMessage: String {
        switch self {
        case let .unavailable(message):
            return message
        case .waitingForPhone:
            return "Enter the phone number for your Telegram account."
        case let .waitingForEmailAddress(message):
            return message
        case let .waitingForEmailCode(message, _, _):
            return message
        case let .working(message):
            return message
        case let .waitingForCode(message):
            return message
        case let .waitingForOtherDeviceConfirmation(message, _):
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

    var acceptsEmailAddress: Bool {
        if case .waitingForEmailAddress = self {
            return true
        }
        return false
    }

    var acceptsEmailCode: Bool {
        if case .waitingForEmailCode = self {
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

    var confirmationLink: String? {
        if case let .waitingForOtherDeviceConfirmation(_, link) = self {
            return link
        }
        return nil
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
    private static let supportedCallVersions = ["2.4.4"]

    weak var delegate: (any TelegramServiceDelegate)?

    private let configuration: TelegramAppConfiguration
    private let manager: TDLibClientManager
    private let client: TDLibClient

    init(configuration: TelegramAppConfiguration) {
        final class UpdateRelay {
            var handler: ((Data) -> Void)?

            func forward(_ data: Data) {
                handler?(data)
            }
        }

        self.configuration = configuration
        self.manager = TDLibClientManager()
        let updateRelay = UpdateRelay()
        self.client = manager.createClient(updateHandler: { [updateRelay] data, _ in
            updateRelay.forward(data)
        })
        updateRelay.handler = { [weak self] data in
            self?.handleUpdate(data)
        }
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

    func submitEmailAddress(_ emailAddress: String) async throws {
        _ = try await client.setAuthenticationEmailAddress(emailAddress: emailAddress)
    }

    func submitEmailCode(_ code: String) async throws {
        let authentication = EmailAddressAuthentication.emailAddressAuthenticationCode(
            EmailAddressAuthenticationCode(code: code)
        )
        _ = try await client.checkAuthenticationEmailCode(code: authentication)
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

    func sendPhoto(
        from localFileURL: URL,
        caption: String,
        size: CGSize?,
        to chatID: Int64
    ) async throws {
        let dimensions = mediaDimensions(from: size)
        let content = InputMessageContent.inputMessagePhoto(
            InputMessagePhoto(
                addedStickerFileIds: [],
                caption: formattedCaption(caption),
                hasSpoiler: false,
                height: dimensions.height,
                photo: .inputFileLocal(InputFileLocal(path: localFileURL.path)),
                selfDestructType: nil,
                showCaptionAboveMedia: false,
                thumbnail: nil,
                width: dimensions.width
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

    func sendDocument(
        from localFileURL: URL,
        caption: String,
        disableContentTypeDetection: Bool = false,
        to chatID: Int64
    ) async throws {
        let content = InputMessageContent.inputMessageDocument(
            InputMessageDocument(
                caption: formattedCaption(caption),
                disableContentTypeDetection: disableContentTypeDetection,
                document: .inputFileLocal(InputFileLocal(path: localFileURL.path)),
                thumbnail: nil
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

    func sendAudio(
        from localFileURL: URL,
        caption: String,
        duration: Int,
        performer: String,
        title: String,
        to chatID: Int64
    ) async throws {
        let content = InputMessageContent.inputMessageAudio(
            InputMessageAudio(
                albumCoverThumbnail: nil,
                audio: .inputFileLocal(InputFileLocal(path: localFileURL.path)),
                caption: formattedCaption(caption),
                duration: max(duration, 0),
                performer: performer,
                title: title
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

    func sendVideo(
        from localFileURL: URL,
        caption: String,
        size: CGSize?,
        duration: Int,
        to chatID: Int64
    ) async throws {
        let dimensions = mediaDimensions(from: size)
        let content = InputMessageContent.inputMessageVideo(
            InputMessageVideo(
                addedStickerFileIds: [],
                caption: formattedCaption(caption),
                cover: nil,
                duration: max(duration, 0),
                hasSpoiler: false,
                height: dimensions.height,
                selfDestructType: nil,
                showCaptionAboveMedia: false,
                startTimestamp: 0,
                supportsStreaming: true,
                thumbnail: nil,
                video: .inputFileLocal(InputFileLocal(path: localFileURL.path)),
                width: dimensions.width
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

    func sendVoiceNote(
        from localFileURL: URL,
        caption: String,
        duration: Int,
        waveform: Data,
        to chatID: Int64
    ) async throws {
        let content = InputMessageContent.inputMessageVoiceNote(
            InputMessageVoiceNote(
                caption: formattedCaption(caption),
                duration: max(duration, 0),
                selfDestructType: nil,
                voiceNote: .inputFileLocal(InputFileLocal(path: localFileURL.path)),
                waveform: waveform
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

    func downloadFile(fileID: Int) async throws -> URL {
        let file = try await client.downloadFile(
            fileId: fileID,
            limit: 0,
            offset: 0,
            priority: 32,
            synchronous: true
        )

        let localPath = file.local.path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !localPath.isEmpty else {
            throw NSError(
                domain: "UniOS.TelegramService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The Telegram file finished downloading without a readable local path."]
            )
        }

        return URL(fileURLWithPath: localPath)
    }

    func loadCallLogs(limit: Int, onlyMissed: Bool) async throws -> [CallLog] {
        let response = try await client.searchCallMessages(
            limit: min(limit, 100),
            offset: "",
            onlyMissed: onlyMissed
        )

        var items: [CallLog] = []
        items.reserveCapacity(response.messages.count)

        for message in response.messages {
            if let item = try await mapCallLog(message) {
                items.append(item)
            }
        }

        return items.sorted { $0.time > $1.time }
    }

    func startCall(to userID: Int64, isVideo: Bool) async throws -> Int {
        let callID = try await client.createCall(
            isVideo: isVideo,
            protocol: CallProtocol(
                libraryVersions: Self.supportedCallVersions,
                maxLayer: 92,
                minLayer: 65,
                udpP2p: true,
                udpReflector: true
            ),
            userId: userID
        )
        return callID.id
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

        case let .authorizationStateWaitEmailAddress(value):
            return .waitingForEmailAddress(
                message: emailAddressPrompt(allowAppleID: value.allowAppleId, allowGoogleID: value.allowGoogleId)
            )

        case let .authorizationStateWaitEmailCode(value):
            return .waitingForEmailCode(
                message: emailCodePrompt(
                    pattern: value.codeInfo.emailAddressPattern,
                    length: value.codeInfo.length
                ),
                emailPattern: value.codeInfo.emailAddressPattern,
                codeLength: value.codeInfo.length
            )

        case let .authorizationStateWaitCode(value):
            let message = "Enter the Telegram code sent to \(value.codeInfo.phoneNumber)."
            return .waitingForCode(message: message)

        case let .authorizationStateWaitOtherDeviceConfirmation(value):
            return .waitingForOtherDeviceConfirmation(
                message: "Confirm this sign in from another logged-in Telegram device. You can use the Telegram link or QR code shown below.",
                link: value.link
            )

        case let .authorizationStateWaitPassword(value):
            return .waitingForPassword(hint: value.passwordHint)

        case .authorizationStateReady:
            return .ready

        case .authorizationStateLoggingOut:
            return .working(message: "Signing out from Telegram.")

        case .authorizationStateClosing, .authorizationStateClosed:
            return .working(message: "Closing the Telegram session.")

        case .authorizationStateWaitRegistration:
            return .failed(message: "New account registration is not wired into this build yet.")

        case .authorizationStateWaitPremiumPurchase:
            return .failed(message: "Telegram Premium purchase confirmation is not supported in this build.")

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

    private func emailAddressPrompt(allowAppleID: Bool, allowGoogleID: Bool) -> String {
        var message = "Telegram needs the email address linked to this account."
        if allowAppleID || allowGoogleID {
            message += " Apple ID and Google ID shortcuts are available in TDLib, but this build currently continues with the email address path."
        }
        return message
    }

    private func emailCodePrompt(pattern: String, length: Int) -> String {
        let sanitizedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = sanitizedPattern.isEmpty ? "your email address" : sanitizedPattern

        guard length > 0 else {
            return "Enter the Telegram code sent to \(destination)."
        }

        return "Enter the \(length)-character Telegram code sent to \(destination)."
    }

    private func mediaDimensions(from size: CGSize?) -> (width: Int, height: Int) {
        guard let size else {
            return (0, 0)
        }

        return (
            width: max(Int(size.width.rounded()), 0),
            height: max(Int(size.height.rounded()), 0)
        )
    }

    private func formattedCaption(_ text: String) -> FormattedText? {
        guard let caption = nonEmptyText(text) else {
            return nil
        }
        return FormattedText(entities: [], text: caption)
    }

    private func mapCallLog(_ message: TDLibKit.Message) async throws -> CallLog? {
        let call: MessageCall
        switch message.content {
        case let .messageCall(value):
            call = value
        default:
            return nil
        }

        let chat = try await client.getChat(chatId: message.chatId)
        let personName: String
        let telegramUserID: Int64?
        switch chat.type {
        case let .chatTypePrivate(value):
            let user = try await client.getUser(userId: value.userId)
            personName = Self.displayName(for: user)
            telegramUserID = value.userId
        default:
            personName = chat.title
            telegramUserID = nil
        }

        return CallLog(
            id: StableIdentifier.messageUUID(chatID: message.chatId, messageID: message.id),
            personName: personName,
            direction: callDirection(for: message, discardReason: call.discardReason),
            time: messageDate(for: message.date),
            durationDescription: callDurationDescription(for: call),
            note: callNote(for: call),
            isVideo: call.isVideo,
            telegramUserID: telegramUserID
        )
    }

    private func callDirection(for message: TDLibKit.Message, discardReason: CallDiscardReason) -> CallDirection {
        switch discardReason {
        case .callDiscardReasonMissed, .callDiscardReasonDeclined:
            return message.isOutgoing ? .outgoing : .missed
        default:
            return message.isOutgoing ? .outgoing : .incoming
        }
    }

    private func callDurationDescription(for call: MessageCall) -> String {
        guard call.duration > 0 else {
            return "No answer"
        }

        let minutes = call.duration / 60
        let seconds = call.duration % 60
        if minutes > 0 && seconds > 0 {
            return "\(minutes)m \(seconds)s"
        }
        if minutes > 0 {
            return minutes == 1 ? "1 minute" : "\(minutes) minutes"
        }
        return seconds == 1 ? "1 second" : "\(seconds) seconds"
    }

    private func callNote(for call: MessageCall) -> String {
        let callType = call.isVideo ? "Video" : "Audio"

        switch call.discardReason {
        case .callDiscardReasonMissed:
            return "\(callType) call missed"
        case .callDiscardReasonDeclined:
            return "\(callType) call declined"
        case .callDiscardReasonDisconnected:
            return "\(callType) call disconnected"
        case .callDiscardReasonHungUp:
            return "\(callType) call ended"
        case let .callDiscardReasonUpgradeToGroupCall(value):
            return value.inviteLink.isEmpty ? "\(callType) call upgraded to a group call" : "Upgraded to a group call"
        case .callDiscardReasonEmpty:
            return "\(callType) call"
        }
    }

    private func callSummary(for call: MessageCall) -> String {
        "\(callNote(for: call)). \(callDurationDescription(for: call))"
    }

    private func audioDescription(fileName: String, title: String, performer: String) -> String {
        if let title = nonEmptyText(title), let performer = nonEmptyText(performer) {
            return "\(title) by \(performer)"
        }
        if let title = nonEmptyText(title) {
            return title
        }
        if let performer = nonEmptyText(performer) {
            return performer
        }
        return nonEmptyText(fileName) ?? "Audio attachment"
    }

    private func photoAttachment(from photo: Photo) -> MessageAttachment? {
        guard let bestPhoto = photo.sizes.max(by: { ($0.width * $0.height) < ($1.width * $1.height) }) else {
            return nil
        }

        return MessageAttachment(
            kind: .photo,
            mimeType: "image/jpeg",
            telegramFileID: bestPhoto.photo.id,
            localPath: resolvedLocalPath(for: bestPhoto.photo),
            width: bestPhoto.width,
            height: bestPhoto.height
        )
    }

    private func documentAttachment(from document: Document) -> MessageAttachment {
        MessageAttachment(
            kind: .document,
            fileName: nonEmptyText(document.fileName),
            mimeType: nonEmptyText(document.mimeType),
            telegramFileID: document.document.id,
            localPath: resolvedLocalPath(for: document.document)
        )
    }

    private func audioAttachment(from audio: Audio) -> MessageAttachment {
        MessageAttachment(
            kind: .audio,
            fileName: nonEmptyText(audio.fileName),
            mimeType: nonEmptyText(audio.mimeType),
            durationSeconds: audio.duration,
            telegramFileID: audio.audio.id,
            localPath: resolvedLocalPath(for: audio.audio)
        )
    }

    private func videoAttachment(from video: Video) -> MessageAttachment {
        MessageAttachment(
            kind: .video,
            fileName: nonEmptyText(video.fileName),
            mimeType: nonEmptyText(video.mimeType),
            durationSeconds: video.duration,
            telegramFileID: video.video.id,
            localPath: resolvedLocalPath(for: video.video),
            width: video.width,
            height: video.height
        )
    }

    private func videoNoteAttachment(from videoNote: VideoNote) -> MessageAttachment {
        MessageAttachment(
            kind: .videoNote,
            mimeType: "video/mp4",
            durationSeconds: videoNote.duration,
            telegramFileID: videoNote.video.id,
            localPath: resolvedLocalPath(for: videoNote.video),
            width: videoNote.length,
            height: videoNote.length
        )
    }

    private func voiceNoteAttachment(from voiceNote: VoiceNote) -> MessageAttachment {
        MessageAttachment(
            kind: .voiceNote,
            mimeType: nonEmptyText(voiceNote.mimeType),
            durationSeconds: voiceNote.duration,
            telegramFileID: voiceNote.voice.id,
            localPath: resolvedLocalPath(for: voiceNote.voice)
        )
    }

    private func resolvedLocalPath(for file: TDLibKit.File) -> String? {
        let localPath = file.local.path.trimmingCharacters(in: .whitespacesAndNewlines)
        return localPath.isEmpty ? nil : localPath
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
            attachment: mappedContent.attachment,
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

    private func mappedMessageContent(_ content: TDLibKit.MessageContent) -> (text: String, kind: MessageKind, attachment: MessageAttachment?) {
        switch content {
        case let .messageText(value):
            let text = nonEmptyText(value.text.text) ?? "Message"
            return (text, .text, nil)

        case let .messagePhoto(value):
            let description = nonEmptyText(value.caption.text) ?? "Photo attachment"
            return (
                description,
                .photo(description: description),
                photoAttachment(from: value.photo)
            )

        case let .messageVoiceNote(value):
            let transcript = nonEmptyText(value.caption.text) ?? "Voice note"
            return (
                transcript,
                .voice(transcript: transcript, durationSeconds: value.voiceNote.duration),
                voiceNoteAttachment(from: value.voiceNote)
            )

        case let .messageAudio(value):
            let fallback = audioDescription(fileName: value.audio.fileName, title: value.audio.title, performer: value.audio.performer)
            let description = nonEmptyText(value.caption.text) ?? fallback
            return (
                description,
                .audio(description: description, durationSeconds: value.audio.duration),
                audioAttachment(from: value.audio)
            )

        case let .messageDocument(value):
            let fallback = nonEmptyText(value.document.fileName) ?? "Document attachment"
            let description = nonEmptyText(value.caption.text) ?? fallback
            return (
                description,
                .document(description: description, fileName: nonEmptyText(value.document.fileName)),
                documentAttachment(from: value.document)
            )

        case let .messageAnimation(value):
            let description = nonEmptyText(value.caption.text) ?? "Animation"
            return (description, .video(description: description, durationSeconds: nil), nil)

        case let .messageVideo(value):
            let description = nonEmptyText(value.caption.text) ?? "Video attachment"
            return (
                description,
                .video(description: description, durationSeconds: value.video.duration),
                videoAttachment(from: value.video)
            )

        case let .messageVideoNote(value):
            let description = "Video note"
            return (
                description,
                .video(description: description, durationSeconds: value.videoNote.duration),
                videoNoteAttachment(from: value.videoNote)
            )

        case let .messageCall(value):
            let summary = callSummary(for: value)
            return (summary, .text, nil)

        case .messageSticker:
            return ("Sticker", .text, nil)

        case .messageLocation:
            return ("Location", .text, nil)

        case .messageContact:
            return ("Shared contact", .text, nil)

        case .messagePoll:
            return ("Poll", .text, nil)

        default:
            return ("Unsupported message type", .text, nil)
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

    private func userFacingMessage(for error: any Swift.Error) -> String {
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
