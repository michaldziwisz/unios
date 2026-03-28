import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class UniOSAppModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var selectedTab: AppTab = .chats
    @Published var selectedChatFolder: ChatFolder = .all
    @Published var chatSearchText = ""
    @Published var showMissedCallsOnly = false
    @Published var signInPhoneNumber = "+48 600 000 000"
    @Published var signInName = "VoiceOver Pilot"
    @Published var signInEmailAddress = ""
    @Published var signInEmailCode = ""
    @Published var signInVerificationCode = ""
    @Published var signInPassword = ""
    @Published var chats: [Chat]
    @Published var contacts: [Contact]
    @Published var calls: [CallLog]
    @Published var accessibilityPreferences: AccessibilityPreferences
    @Published private(set) var activeCallSession: ActiveCallSession?
    @Published private(set) var latestAnnouncement = ""
    @Published private(set) var sessionSource: SessionSource = .telegram
    @Published private(set) var telegramSignInState: TelegramSignInState
    @Published private(set) var telegramProfile: TelegramAccountProfile?
    @Published private(set) var isSyncingTelegramData = false

    private let seed: UniOSSeedData
    private let telegramConfiguration: TelegramAppConfiguration?
    private var telegramService: TelegramService?
    private var hasBootstrappedTelegramSession = false
    private var overviewRefreshTask: Task<Void, Never>?
    private static let isRunningUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    init(seed: UniOSSeedData = .preview) {
        self.seed = seed
        self.chats = seed.chats
        self.contacts = seed.contacts
        self.calls = seed.calls
        self.accessibilityPreferences = seed.accessibilityPreferences

        if Self.isRunningUnitTests {
            self.telegramConfiguration = nil
            self.telegramService = nil
            self.sessionSource = .demo
            self.telegramSignInState = .unavailable(message: "Telegram bootstrap is disabled while unit tests are running.")
            return
        }

        if let configuration = TelegramAppConfiguration.load() {
            self.telegramConfiguration = configuration
            self.telegramService = nil
            self.sessionSource = .telegram
            self.telegramSignInState = .waitingForPhone
        } else {
            self.telegramConfiguration = nil
            self.telegramService = nil
            self.sessionSource = .demo
            self.telegramSignInState = .unavailable(
                message: "Telegram credentials are not configured in this build. Run scripts/generate_telegram_secrets.sh to enable sign in."
            )
        }
    }

    deinit {
        overviewRefreshTask?.cancel()
    }

    var profileName: String {
        if let telegramProfile, sessionSource == .telegram {
            return telegramProfile.displayName
        }

        let trimmed = signInName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "VoiceOver Pilot" : trimmed
    }

    var activeAccountHandle: String {
        if let telegramProfile, sessionSource == .telegram {
            return telegramProfile.handle
        }
        return "VoiceOver-first workspace"
    }

    var canUseTelegram: Bool {
        telegramConfiguration != nil
    }

    var canDisplayActiveCallVideo: Bool {
        guard let activeCallSession else {
            return false
        }
        return sessionSource == .telegram && activeCallSession.isVideo && activeCallSession.nativeMediaEngineReady
    }

    var filteredChats: [Chat] {
        ChatFiltering.apply(chats: chats, folder: selectedChatFolder, searchQuery: chatSearchText)
    }

    var filteredCalls: [CallLog] {
        let items = showMissedCallsOnly ? calls.filter { $0.direction == .missed } : calls
        return items.sorted { $0.time > $1.time }
    }

    func signInDemo() {
        chats = seed.chats
        contacts = seed.contacts
        calls = seed.calls
        sessionSource = .demo
        telegramProfile = nil
        activeCallSession = nil
        isAuthenticated = true
        announce("\(profileName) signed in. \(filteredChats.count) conversations ready.")
    }

    func submitTelegramPhoneNumber() {
        guard canUseTelegram else {
            announce("Telegram credentials are unavailable in this build.")
            return
        }

        let phoneNumber = signInPhoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phoneNumber.isEmpty else {
            announce("Phone number is empty.")
            return
        }

        telegramSignInState = .working(message: "Sending the Telegram phone number.")
        Task { [weak self] in
            do {
                guard let self else {
                    return
                }
                let telegramService = try await self.prepareTelegramForPhoneAuthentication()
                try await telegramService.submitPhoneNumber(phoneNumber)
            } catch {
                await self?.handleTelegramFailure(error, fallbackState: .waitingForPhone)
            }
        }
    }

    func submitTelegramEmailAddress() {
        guard canUseTelegram else {
            announce("Telegram credentials are unavailable in this build.")
            return
        }

        let emailAddress = signInEmailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !emailAddress.isEmpty else {
            announce("Email address is empty.")
            return
        }

        telegramSignInState = .working(message: "Sending the Telegram email address.")
        Task { [weak self] in
            do {
                guard let self else {
                    return
                }
                let telegramService = try await self.startTelegramSessionIfNeeded()
                try await telegramService.submitEmailAddress(emailAddress)
            } catch {
                await self?.handleTelegramFailure(
                    error,
                    fallbackState: .waitingForEmailAddress(message: "Enter the email address linked to this Telegram account.")
                )
            }
        }
    }

    func submitTelegramEmailCode() {
        guard canUseTelegram else {
            announce("Telegram credentials are unavailable in this build.")
            return
        }

        let code = signInEmailCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            announce("Email code is empty.")
            return
        }

        telegramSignInState = .working(message: "Checking the Telegram email code.")
        Task { [weak self] in
            do {
                guard let self else {
                    return
                }
                let telegramService = try await self.startTelegramSessionIfNeeded()
                try await telegramService.submitEmailCode(code)
            } catch {
                await self?.handleTelegramFailure(
                    error,
                    fallbackState: .waitingForEmailCode(
                        message: "Enter the Telegram code sent to your email address.",
                        emailPattern: "",
                        codeLength: 0
                    )
                )
            }
        }
    }

    func submitTelegramCode() {
        guard canUseTelegram else {
            announce("Telegram credentials are unavailable in this build.")
            return
        }

        let code = signInVerificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            announce("Verification code is empty.")
            return
        }

        telegramSignInState = .working(message: "Checking the Telegram code.")
        Task { [weak self] in
            do {
                guard let self else {
                    return
                }
                let telegramService = try await self.startTelegramSessionIfNeeded()
                try await telegramService.submitCode(code)
            } catch {
                await self?.handleTelegramFailure(error, fallbackState: .waitingForCode(message: "Enter the Telegram code."))
            }
        }
    }

    func submitTelegramPassword() {
        guard canUseTelegram else {
            announce("Telegram credentials are unavailable in this build.")
            return
        }

        let password = signInPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !password.isEmpty else {
            announce("Password is empty.")
            return
        }

        telegramSignInState = .working(message: "Checking the Telegram password.")
        Task { [weak self] in
            do {
                guard let self else {
                    return
                }
                let telegramService = try await self.startTelegramSessionIfNeeded()
                try await telegramService.submitPassword(password)
            } catch {
                await self?.handleTelegramFailure(error, fallbackState: .waitingForPassword(hint: ""))
            }
        }
    }

    func signOut() {
        if sessionSource == .telegram, let telegramService {
            let announcement = "\(profileName) signed out from Telegram."
            resetToSignedOutState()
            telegramSignInState = .working(message: "Signing out from Telegram.")
            announce(announcement)

            Task { [weak self] in
                do {
                    try await telegramService.logOut()
                } catch {
                    await self?.handleTelegramFailure(error, fallbackState: .waitingForPhone)
                }

                await self?.bootstrapTelegramSessionIfNeeded()
            }
            return
        }

        resetToSignedOutState()
        announce("Signed out of the demo workspace.")
    }

    func select(tab: AppTab) {
        announce("Opened \(tab.title).")
    }

    func chat(for chatID: UUID) -> Chat? {
        chats.first { $0.id == chatID }
    }

    func markChatRead(_ chatID: UUID) {
        guard let chat = chat(for: chatID), chat.unreadCount > 0 else {
            return
        }

        mutateChat(chatID) { draft in
            draft.unreadCount = 0
        }

        if sessionSource == .telegram, let remoteChatID = chat.telegramChatID, let telegramService {
            let visibleMessageIDs = chat.messages.compactMap(\.telegramMessageID)
            Task {
                await telegramService.markViewed(chatID: remoteChatID, messageIDs: visibleMessageIDs)
            }
        }

        if accessibilityPreferences.announceUnreadMessages {
            announce("\(chat.title) marked as read.")
        }
    }

    func toggleMuted(chatID: UUID) {
        guard let chat = chat(for: chatID) else {
            return
        }

        if sessionSource == .telegram {
            announce("Telegram mute sync is not wired into this build yet.")
            return
        }

        mutateChat(chatID) { draft in
            draft.isMuted.toggle()
        }

        announce("\(chat.title) \(chat.isMuted ? "unmuted" : "muted").")
    }

    func loadConversationIfNeeded(chatID: UUID) {
        guard sessionSource == .telegram, let chat = chat(for: chatID), let remoteChatID = chat.telegramChatID else {
            return
        }

        let shouldRefresh = chat.messages.count <= 1
        if shouldRefresh {
            Task { [weak self] in
                await self?.refreshTelegramChat(remoteChatID: remoteChatID)
            }
        } else {
            markChatRead(chatID)
        }
    }

    func sendMessage(_ rawText: String, to chatID: UUID) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            announce("Message is empty.")
            return
        }

        guard let chat = chat(for: chatID) else {
            announce("Conversation is unavailable.")
            return
        }

        if sessionSource == .telegram, let remoteChatID = chat.telegramChatID, let telegramService {
            announce("Sending message to \(chat.title).")

            Task { [weak self] in
                do {
                    try await telegramService.sendText(text, to: remoteChatID)
                    await self?.refreshTelegramChat(remoteChatID: remoteChatID, successAnnouncement: "Message sent to \(chat.title).")
                    await self?.scheduleTelegramOverviewRefresh(delayNanoseconds: 150_000_000)
                } catch {
                    await self?.handleTelegramFailure(error, fallbackState: .waitingForPhone)
                }
            }
            return
        }

        appendOutgoingMessage(text: text, kind: .text, to: chatID)

        announce("Message sent to \(chat.title).")
    }

    func sendPhoto(at localFileURL: URL, size: CGSize?, caption rawCaption: String, to chatID: UUID) {
        guard let chat = chat(for: chatID) else {
            announce("Conversation is unavailable.")
            return
        }

        let caption = rawCaption.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = caption.isEmpty ? "Photo attachment" : caption

        if sessionSource == .telegram, let remoteChatID = chat.telegramChatID, let telegramService {
            announce("Sending photo to \(chat.title).")

            Task { [weak self] in
                do {
                    try await telegramService.sendPhoto(
                        from: localFileURL,
                        caption: caption,
                        size: size,
                        to: remoteChatID
                    )
                    await self?.refreshTelegramChat(
                        remoteChatID: remoteChatID,
                        successAnnouncement: "Photo sent to \(chat.title)."
                    )
                    await self?.scheduleTelegramOverviewRefresh(delayNanoseconds: 150_000_000)
                } catch {
                    await self?.handleTelegramFailure(error, fallbackState: .waitingForPhone)
                }
            }
            return
        }

        appendOutgoingMessage(
            text: description,
            kind: .photo(description: description),
            attachment: MessageAttachment(
                kind: .photo,
                mimeType: "image/jpeg",
                localPath: localFileURL.path
            ),
            to: chatID
        )
        announce("Photo sent to \(chat.title).")
    }

    func sendDocument(at localFileURL: URL, caption rawCaption: String, to chatID: UUID) {
        guard let chat = chat(for: chatID) else {
            announce("Conversation is unavailable.")
            return
        }

        let caption = rawCaption.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = localFileURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = fileName.isEmpty ? "Document attachment" : fileName
        let description = caption.isEmpty ? fallback : caption

        if sessionSource == .telegram, let remoteChatID = chat.telegramChatID, let telegramService {
            announce("Sending document to \(chat.title).")

            Task { [weak self] in
                do {
                    try await telegramService.sendDocument(
                        from: localFileURL,
                        caption: caption,
                        to: remoteChatID
                    )
                    await self?.refreshTelegramChat(
                        remoteChatID: remoteChatID,
                        successAnnouncement: "Document sent to \(chat.title)."
                    )
                    await self?.scheduleTelegramOverviewRefresh(delayNanoseconds: 150_000_000)
                } catch {
                    await self?.handleTelegramFailure(error, fallbackState: .waitingForPhone)
                }
            }
            return
        }

        appendOutgoingMessage(
            text: description,
            kind: .document(
                description: description,
                fileName: fileName.isEmpty ? nil : fileName
            ),
            attachment: MessageAttachment(
                kind: .document,
                fileName: fileName.isEmpty ? nil : fileName,
                localPath: localFileURL.path
            ),
            to: chatID
        )
        announce("Document sent to \(chat.title).")
    }

    func sendAudio(
        at localFileURL: URL,
        caption rawCaption: String,
        duration: Int,
        title rawTitle: String,
        performer rawPerformer: String,
        to chatID: UUID
    ) {
        guard let chat = chat(for: chatID) else {
            announce("Conversation is unavailable.")
            return
        }

        let caption = rawCaption.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let performer = rawPerformer.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = localFileURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = [title, performer].filter { !$0.isEmpty }.joined(separator: " by ")
        let description = caption.isEmpty ? (fallback.isEmpty ? (fileName.isEmpty ? "Audio attachment" : fileName) : fallback) : caption

        if sessionSource == .telegram, let remoteChatID = chat.telegramChatID, let telegramService {
            announce("Sending audio to \(chat.title).")

            Task { [weak self] in
                do {
                    try await telegramService.sendAudio(
                        from: localFileURL,
                        caption: caption,
                        duration: duration,
                        performer: performer,
                        title: title,
                        to: remoteChatID
                    )
                    await self?.refreshTelegramChat(
                        remoteChatID: remoteChatID,
                        successAnnouncement: "Audio sent to \(chat.title)."
                    )
                    await self?.scheduleTelegramOverviewRefresh(delayNanoseconds: 150_000_000)
                } catch {
                    await self?.handleTelegramFailure(error, fallbackState: .waitingForPhone)
                }
            }
            return
        }

        appendOutgoingMessage(
            text: description,
            kind: .audio(description: description, durationSeconds: duration),
            attachment: MessageAttachment(
                kind: .audio,
                fileName: fileName.isEmpty ? nil : fileName,
                durationSeconds: duration,
                localPath: localFileURL.path
            ),
            to: chatID
        )
        announce("Audio sent to \(chat.title).")
    }

    func sendVideo(at localFileURL: URL, size: CGSize?, duration: Int, caption rawCaption: String, to chatID: UUID) {
        guard let chat = chat(for: chatID) else {
            announce("Conversation is unavailable.")
            return
        }

        let caption = rawCaption.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = localFileURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = caption.isEmpty ? (fileName.isEmpty ? "Video attachment" : fileName) : caption

        if sessionSource == .telegram, let remoteChatID = chat.telegramChatID, let telegramService {
            announce("Sending video to \(chat.title).")

            Task { [weak self] in
                do {
                    try await telegramService.sendVideo(
                        from: localFileURL,
                        caption: caption,
                        size: size,
                        duration: duration,
                        to: remoteChatID
                    )
                    await self?.refreshTelegramChat(
                        remoteChatID: remoteChatID,
                        successAnnouncement: "Video sent to \(chat.title)."
                    )
                    await self?.scheduleTelegramOverviewRefresh(delayNanoseconds: 150_000_000)
                } catch {
                    await self?.handleTelegramFailure(error, fallbackState: .waitingForPhone)
                }
            }
            return
        }

        appendOutgoingMessage(
            text: description,
            kind: .video(description: description, durationSeconds: duration),
            attachment: MessageAttachment(
                kind: .video,
                fileName: fileName.isEmpty ? nil : fileName,
                durationSeconds: duration,
                localPath: localFileURL.path,
                width: size.map { Int($0.width.rounded()) },
                height: size.map { Int($0.height.rounded()) }
            ),
            to: chatID
        )
        announce("Video sent to \(chat.title).")
    }

    func sendVoiceNote(at localFileURL: URL, duration: Int, waveform: Data, caption rawCaption: String, to chatID: UUID) {
        guard let chat = chat(for: chatID) else {
            announce("Conversation is unavailable.")
            return
        }

        let caption = rawCaption.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = caption.isEmpty ? "Voice note" : caption

        if sessionSource == .telegram, let remoteChatID = chat.telegramChatID, let telegramService {
            announce("Sending voice note to \(chat.title).")

            Task { [weak self] in
                do {
                    try await telegramService.sendVoiceNote(
                        from: localFileURL,
                        caption: caption,
                        duration: duration,
                        waveform: waveform,
                        to: remoteChatID
                    )
                    await self?.refreshTelegramChat(
                        remoteChatID: remoteChatID,
                        successAnnouncement: "Voice note sent to \(chat.title)."
                    )
                    await self?.scheduleTelegramOverviewRefresh(delayNanoseconds: 150_000_000)
                } catch {
                    await self?.handleTelegramFailure(error, fallbackState: .waitingForPhone)
                }
            }
            return
        }

        appendOutgoingMessage(
            text: description,
            kind: .voice(transcript: description, durationSeconds: duration),
            attachment: MessageAttachment(
                kind: .voiceNote,
                durationSeconds: duration,
                localPath: localFileURL.path
            ),
            to: chatID
        )
        announce("Voice note sent to \(chat.title).")
    }

    func loadAttachment(for messageID: UUID, in chatID: UUID) async throws -> URL {
        guard let message = chat(for: chatID)?.messages.first(where: { $0.id == messageID }) else {
            throw NSError(
                domain: "UniOS.AppModel",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The selected message is unavailable."]
            )
        }

        guard let attachment = message.attachment else {
            throw NSError(
                domain: "UniOS.AppModel",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "This message has no attachment to open."]
            )
        }

        if
            let localURL = attachment.localURL,
            FileManager.default.fileExists(atPath: localURL.path)
        {
            return localURL
        }

        guard
            sessionSource == .telegram,
            let telegramService,
            let telegramFileID = attachment.telegramFileID
        else {
            throw NSError(
                domain: "UniOS.AppModel",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "The attachment is not available on this device."]
            )
        }

        let downloadedURL = try await telegramService.downloadFile(fileID: telegramFileID)
        updateAttachmentLocalPath(downloadedURL.path, for: messageID, in: chatID)
        return downloadedURL
    }

    func jumpToFirstUnreadChat() -> Chat? {
        guard accessibilityPreferences.prioritizeUnreadChatsShortcut else {
            announce("Unread shortcut is disabled in accessibility settings.")
            return nil
        }

        guard let unread = ChatFiltering.firstUnreadChat(in: chats) else {
            announce("No unread conversations.")
            return nil
        }

        selectedChatFolder = .unread
        announce("Jumping to \(unread.title).")
        return unread
    }

    func toggleMissedCallsOnly() {
        showMissedCallsOnly.toggle()
        announce(showMissedCallsOnly ? "Showing missed calls only." : "Showing all calls.")
    }

    func call(_ personName: String) {
        startCall(personName: personName, telegramUserID: nil, isVideo: false)
    }

    func call(_ contact: Contact, isVideo: Bool = false) {
        startCall(personName: contact.name, telegramUserID: contact.telegramUserID, isVideo: isVideo)
    }

    func call(_ entry: CallLog) {
        startCall(personName: entry.personName, telegramUserID: entry.telegramUserID, isVideo: entry.isVideo)
    }

    func acceptActiveCall() {
        guard let activeCallSession else {
            return
        }

        if sessionSource == .telegram, let telegramService {
            announce("Accepting call from \(activeCallSession.peerName).")

            Task { [weak self] in
                do {
                    try await telegramService.acceptCall(callID: activeCallSession.id)
                } catch {
                    await MainActor.run {
                        guard let self else {
                            return
                        }
                        self.announce(self.userFacingMessage(for: error))
                    }
                }
            }
            return
        }

        updateActiveCallSession { session in
            session.phase = .connected
            session.connectedAt = session.connectedAt ?? .now
            session.lastUpdatedAt = .now
            session.nativeMediaEngineReady = true
            session.mediaTransportState = .connected
            session.speakerEnabled = true
            if session.isVideo {
                session.localVideoEnabled = true
            }
        }
        announce("Call connected.")
    }

    func endActiveCall(isDisconnected: Bool = false) {
        guard let activeCallSession else {
            return
        }

        if sessionSource == .telegram, let telegramService {
            let action = activeCallSession.canAccept ? "Declining" : "Ending"
            announce("\(action) call with \(activeCallSession.peerName).")

            Task { [weak self] in
                do {
                    try await telegramService.endCall(
                        callID: activeCallSession.id,
                        duration: self?.activeCallDurationSeconds(for: activeCallSession) ?? 0,
                        isDisconnected: isDisconnected,
                        isVideo: activeCallSession.isVideo
                    )
                } catch {
                    await MainActor.run {
                        guard let self else {
                            return
                        }
                        self.announce(self.userFacingMessage(for: error))
                    }
                }
            }
            return
        }

        updateActiveCallSession { session in
            session.phase = .ended(
                reason: isDisconnected ? "Call disconnected" : "Call ended",
                needsRating: false,
                needsDebugLog: false
            )
            session.lastUpdatedAt = .now
            session.mediaTransportState = .stopped
            session.nativeMediaEngineReady = false
        }
        announce("Call ended.")
    }

    func dismissActiveCallPanel() {
        guard activeCallSession?.phase.isTerminal == true else {
            return
        }

        activeCallSession = nil
        announce("Call summary dismissed.")
    }

    func toggleActiveCallMuted() {
        guard let activeCallSession else {
            return
        }

        let nextValue = !activeCallSession.isMuted
        if sessionSource == .telegram, let telegramService {
            telegramService.setCallMuted(callID: activeCallSession.id, isMuted: nextValue)
            updateActiveCallSession { session in
                session.isMuted = nextValue
            }
            announce(nextValue ? "Microphone muted." : "Microphone unmuted.")
            return
        }

        updateActiveCallSession { session in
            session.isMuted = nextValue
        }
        announce(nextValue ? "Microphone muted." : "Microphone unmuted.")
    }

    func toggleActiveCallSpeaker() {
        guard let activeCallSession else {
            return
        }

        let nextValue = !activeCallSession.speakerEnabled
        if sessionSource == .telegram, let telegramService {
            telegramService.setCallSpeakerEnabled(callID: activeCallSession.id, isEnabled: nextValue)
            updateActiveCallSession { session in
                session.speakerEnabled = nextValue
            }
            announce(nextValue ? "Speaker enabled." : "Speaker disabled.")
            return
        }

        updateActiveCallSession { session in
            session.speakerEnabled = nextValue
        }
        announce(nextValue ? "Speaker enabled." : "Speaker disabled.")
    }

    func toggleActiveCallVideo() {
        guard let activeCallSession, activeCallSession.isVideo else {
            return
        }

        let nextValue = !activeCallSession.localVideoEnabled
        if sessionSource == .telegram, let telegramService {
            telegramService.setCallVideoEnabled(callID: activeCallSession.id, isEnabled: nextValue)
            updateActiveCallSession { session in
                session.localVideoEnabled = nextValue
            }
            announce(nextValue ? "Camera enabled." : "Camera paused.")
            return
        }

        updateActiveCallSession { session in
            session.localVideoEnabled = nextValue
        }
        announce(nextValue ? "Camera enabled." : "Camera paused.")
    }

#if canImport(UIKit)
    func makeActiveCallIncomingVideoView(completion: @escaping (UIView?) -> Void) {
        guard
            sessionSource == .telegram,
            let activeCallSession,
            let telegramService
        else {
            completion(nil)
            return
        }

        telegramService.makeIncomingCallVideoView(
            callID: activeCallSession.id,
            completion: completion
        )
    }

    func makeActiveCallOutgoingVideoView(completion: @escaping (UIView?) -> Void) {
        guard
            sessionSource == .telegram,
            let activeCallSession,
            let telegramService
        else {
            completion(nil)
            return
        }

        telegramService.makeOutgoingCallVideoView(
            callID: activeCallSession.id,
            completion: completion
        )
    }
#endif

    func startChat(with contact: Contact, completion: @escaping (UUID?) -> Void) {
        if sessionSource == .telegram, let userID = contact.telegramUserID, let telegramService {
            if let existing = chats.first(where: { $0.title == contact.name || $0.participants.contains(contact.name) }) {
                announce("Opening chat with \(contact.name).")
                completion(existing.id)
                return
            }

            Task { [weak self] in
                do {
                    let createdChat = try await telegramService.createPrivateChat(
                        for: userID,
                        currentUserDisplayName: self?.profileName ?? contact.name
                    )
                    await MainActor.run {
                        self?.upsertTelegramChat(createdChat)
                    }
                    await self?.refreshTelegramChat(remoteChatID: createdChat.telegramChatID)
                    await MainActor.run {
                        self?.announce("Started a new Telegram chat with \(contact.name).")
                        completion(createdChat.id)
                    }
                } catch {
                    await self?.handleTelegramFailure(error, fallbackState: .waitingForPhone)
                    await MainActor.run {
                        completion(nil)
                    }
                }
            }
            return
        }

        if let existing = chats.first(where: { $0.title == contact.name || $0.participants.contains(contact.name) }) {
            announce("Opening chat with \(contact.name).")
            completion(existing.id)
            return
        }

        let newChatID = UUID()
        let newChat = Chat(
            id: newChatID,
            title: contact.name,
            handle: "@\(contact.name.lowercased().replacingOccurrences(of: " ", with: ""))",
            summary: "New conversation started",
            folder: .personal,
            unreadCount: 0,
            isMuted: false,
            isPinned: false,
            participants: [contact.name],
            lastUpdated: Date(),
            messages: [],
            avatarHue: contact.avatarHue
        )
        chats.insert(newChat, at: 0)
        announce("Started a new chat with \(contact.name).")
        completion(newChatID)
    }

    func updateAccessibilityPreferences(_ change: (inout AccessibilityPreferences) -> Void) {
        var updated = accessibilityPreferences
        change(&updated)
        accessibilityPreferences = updated
        announce("Accessibility preferences updated.")
    }

    func demoAnnouncement() {
        let workspace = sessionSource == .telegram ? "Telegram session" : "Demo workspace"
        announce(
            "\(workspace). \(filteredChats.count) visible chats, \(filteredCalls.count) visible calls, unread shortcut \(accessibilityPreferences.prioritizeUnreadChatsShortcut ? "enabled" : "disabled")."
        )
    }

    private func bootstrapTelegramSessionIfNeeded() async {
        _ = try? await startTelegramSessionIfNeeded()
    }

    private func startTelegramSessionIfNeeded() async throws -> TelegramService {
        let telegramService = try ensureTelegramService()

        if hasBootstrappedTelegramSession {
            return telegramService
        }

        do {
            hasBootstrappedTelegramSession = true
            let state = try await telegramService.start()
            handleTelegramStateUpdate(state)
            return telegramService
        } catch {
            hasBootstrappedTelegramSession = false
            await handleTelegramFailure(error, fallbackState: .waitingForPhone)
            throw error
        }
    }

    private func prepareTelegramForPhoneAuthentication() async throws -> TelegramService {
        telegramSignInState = .working(message: "Preparing a fresh Telegram sign-in session.")
        try resetTelegramRuntimeStateForFreshAuthentication()
        let telegramService = try await startTelegramSessionIfNeeded()
        return telegramService
    }

    private func ensureTelegramService() throws -> TelegramService {
        if let telegramService {
            return telegramService
        }

        guard let telegramConfiguration else {
            throw NSError(
                domain: "UniOS.Telegram",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Telegram credentials are unavailable in this build."]
            )
        }

        let telegramService = TelegramService(configuration: telegramConfiguration)
        telegramService.delegate = self
        self.telegramService = telegramService
        return telegramService
    }

    private func resetTelegramRuntimeStateForFreshAuthentication() throws {
        telegramProfile = nil
        activeCallSession = nil
        chats = []
        contacts = []
        calls = []
        hasBootstrappedTelegramSession = false
        telegramService = nil
        try TelegramService.resetPersistentStorage()
    }

    private func handleTelegramStateUpdate(_ newState: TelegramSignInState) {
        let previousState = telegramSignInState
        telegramSignInState = newState

        switch newState {
        case .ready:
            if sessionSource != .telegram || !isAuthenticated {
                Task { [weak self] in
                    await self?.activateTelegramSession()
                }
            }

        case .waitingForEmailAddress, .waitingForEmailCode, .waitingForCode, .waitingForOtherDeviceConfirmation, .waitingForPassword, .failed:
            if previousState != newState {
                announce(newState.statusMessage)
            }

        case .waitingForPhone:
            if sessionSource == .telegram && isAuthenticated {
                isAuthenticated = false
                telegramProfile = nil
            }
            activeCallSession = nil
            signInEmailAddress = ""
            signInEmailCode = ""
            signInVerificationCode = ""
            signInPassword = ""

        case .working, .unavailable:
            break
        }
    }

    private func activateTelegramSession() async {
        guard let telegramService else {
            return
        }

        isSyncingTelegramData = true

        do {
            let profile = try await telegramService.loadCurrentProfile()
            async let loadedChats = telegramService.loadChats(limit: 40, currentUserDisplayName: profile.displayName)
            async let loadedContacts = telegramService.loadContacts(limit: 40)
            async let loadedCalls = telegramService.loadCallLogs(limit: 40, onlyMissed: false)
            let (resolvedChats, resolvedContacts, resolvedCalls) = try await (loadedChats, loadedContacts, loadedCalls)

            telegramProfile = profile
            signInName = profile.displayName
            if !profile.phoneNumber.isEmpty {
                signInPhoneNumber = profile.phoneNumber
            }
            signInEmailAddress = ""
            signInEmailCode = ""
            signInVerificationCode = ""
            signInPassword = ""
            sessionSource = .telegram
            telegramSignInState = .ready
            chats = mergeTelegramChatsPreservingLoadedMessages(resolvedChats)
            contacts = resolvedContacts
            calls = resolvedCalls
            activeCallSession = nil
            isAuthenticated = true
            selectedTab = .chats
            announce("\(profile.displayName) signed in via Telegram. \(resolvedChats.count) conversations synced.")
        } catch {
            await handleTelegramFailure(error, fallbackState: .waitingForPhone)
        }

        isSyncingTelegramData = false
    }

    private func scheduleTelegramOverviewRefresh(delayNanoseconds: UInt64 = 400_000_000) async {
        guard sessionSource == .telegram else {
            return
        }

        overviewRefreshTask?.cancel()
        overviewRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            await self?.refreshTelegramOverview()
        }
    }

    private func refreshTelegramOverview() async {
        guard let telegramService, let profile = telegramProfile, sessionSource == .telegram else {
            return
        }

        isSyncingTelegramData = true

        defer {
            isSyncingTelegramData = false
        }

        do {
            async let loadedChats = telegramService.loadChats(limit: 40, currentUserDisplayName: profile.displayName)
            async let loadedContacts = telegramService.loadContacts(limit: 40)
            async let loadedCalls = telegramService.loadCallLogs(limit: 40, onlyMissed: false)
            let (resolvedChats, resolvedContacts, resolvedCalls) = try await (loadedChats, loadedContacts, loadedCalls)
            chats = mergeTelegramChatsPreservingLoadedMessages(resolvedChats)
            contacts = resolvedContacts
            calls = resolvedCalls
        } catch {
            announce(userFacingMessage(for: error))
        }
    }

    private func refreshTelegramChat(remoteChatID: Int64?, successAnnouncement: String? = nil) async {
        guard
            let telegramService,
            let remoteChatID,
            sessionSource == .telegram,
            let profile = telegramProfile
        else {
            return
        }

        do {
            var loadedChat = try await telegramService.loadChat(
                chatID: remoteChatID,
                currentUserDisplayName: profile.displayName
            )
            let loadedMessages = try await telegramService.loadMessages(
                chatID: remoteChatID,
                currentUserDisplayName: profile.displayName
            )
            loadedChat.messages = loadedMessages
            if let lastMessage = loadedMessages.last {
                loadedChat.summary = lastMessage.text
                loadedChat.lastUpdated = lastMessage.timestamp
            }
            loadedChat.unreadCount = 0

            upsertTelegramChat(loadedChat)

            if let successAnnouncement {
                announce(successAnnouncement)
            }
        } catch {
            announce(userFacingMessage(for: error))
        }
    }

    private func mergeTelegramChatsPreservingLoadedMessages(_ incomingChats: [Chat]) -> [Chat] {
        let existingChats = Dictionary(uniqueKeysWithValues: chats.map { ($0.id, $0) })

        return incomingChats.map { incoming in
            guard let existing = existingChats[incoming.id] else {
                return incoming
            }

            var merged = incoming
            if existing.messages.count > 1 {
                merged.messages = existing.messages
            }
            return merged
        }
    }

    private func upsertTelegramChat(_ chat: Chat) {
        if let index = chats.firstIndex(where: { $0.id == chat.id }) {
            chats[index] = chat
        } else {
            chats.insert(chat, at: 0)
        }
    }

    private func handleTelegramFailure(_ error: any Swift.Error, fallbackState: TelegramSignInState) async {
        let message = userFacingMessage(for: error)
        telegramSignInState = .failed(message: message)
        if !isAuthenticated, telegramConfiguration != nil {
            sessionSource = .telegram
        }
        announce(message)
        if case .waitingForPhone = fallbackState {
            signInEmailAddress = ""
            signInEmailCode = ""
            signInVerificationCode = ""
            signInPassword = ""
        }
    }

    private func resetToSignedOutState() {
        overviewRefreshTask?.cancel()
        overviewRefreshTask = nil
        isAuthenticated = false
        telegramProfile = nil
        activeCallSession = nil
        selectedTab = .chats
        selectedChatFolder = .all
        chatSearchText = ""
        showMissedCallsOnly = false
        signInEmailAddress = ""
        signInEmailCode = ""
        signInVerificationCode = ""
        signInPassword = ""
        accessibilityPreferences = seed.accessibilityPreferences

        if telegramConfiguration != nil {
            sessionSource = .telegram
            chats = []
            contacts = []
            calls = []
            hasBootstrappedTelegramSession = false
            telegramSignInState = .waitingForPhone
        } else {
            sessionSource = .demo
            chats = seed.chats
            contacts = seed.contacts
            calls = seed.calls
            telegramSignInState = .unavailable(
                message: "Telegram credentials are not configured in this build. Run scripts/generate_telegram_secrets.sh to enable sign in."
            )
        }
    }

    private func mutateChat(_ chatID: UUID, update: (inout Chat) -> Void) {
        guard let index = chats.firstIndex(where: { $0.id == chatID }) else {
            return
        }
        var chat = chats[index]
        update(&chat)
        chats[index] = chat
    }

    private func appendOutgoingMessage(text: String, kind: MessageKind, attachment: MessageAttachment? = nil, to chatID: UUID) {
        mutateChat(chatID) { chat in
            let message = Message(
                id: UUID(),
                sender: profileName,
                text: text,
                timestamp: Date(),
                direction: .outgoing,
                status: .sent,
                kind: kind,
                attachment: attachment
            )
            chat.messages.append(message)
            chat.summary = text
            chat.lastUpdated = message.timestamp
            chat.unreadCount = 0
        }
    }

    private func updateAttachmentLocalPath(_ path: String, for messageID: UUID, in chatID: UUID) {
        mutateChat(chatID) { chat in
            guard let messageIndex = chat.messages.firstIndex(where: { $0.id == messageID }) else {
                return
            }

            var message = chat.messages[messageIndex]
            guard var attachment = message.attachment else {
                return
            }

            attachment.localPath = path
            message.attachment = attachment
            chat.messages[messageIndex] = message
        }
    }

    private func startCall(personName: String, telegramUserID: Int64?, isVideo: Bool) {
        let callKind = isVideo ? "video call" : "call"

        if sessionSource == .telegram {
            guard let telegramUserID, let telegramService else {
                announce("Telegram \(callKind) start is available only for direct contacts in this build.")
                return
            }

            announce("Starting \(callKind) with \(personName).")

            Task { [weak self] in
                do {
                    let callID = try await telegramService.startCall(to: telegramUserID, isVideo: isVideo)
                    await self?.scheduleTelegramOverviewRefresh(delayNanoseconds: 1_000_000_000)
                    await MainActor.run {
                        guard let self else {
                            return
                        }
                        self.activeCallSession = ActiveCallSession(
                            id: callID,
                            peerName: personName,
                            peerUserID: telegramUserID,
                            isOutgoing: true,
                            isVideo: isVideo,
                            phase: .requesting,
                            startedAt: .now,
                            lastUpdatedAt: .now,
                            nativeMediaEngineReady: false,
                            mediaTransportState: .initializing
                        )
                        self.selectedTab = .calls
                        self.announce("Telegram \(callKind) requested for \(personName). Call controls are available in UniOS.")
                    }
                } catch {
                    await MainActor.run {
                        guard let self else {
                            return
                        }
                        self.announce(self.userFacingMessage(for: error))
                    }
                }
            }
            return
        }

        activeCallSession = ActiveCallSession(
            id: Int.random(in: 1 ... Int.max),
            peerName: personName,
            peerUserID: telegramUserID,
            isOutgoing: true,
            isVideo: isVideo,
            phase: .connected,
            startedAt: .now,
            connectedAt: .now,
            lastUpdatedAt: .now,
            nativeMediaEngineReady: true,
            mediaTransportState: .connected,
            speakerEnabled: true,
            localVideoEnabled: isVideo
        )

        calls.insert(
            CallLog(
                id: UUID(),
                personName: personName,
                direction: .outgoing,
                time: Date(),
                durationDescription: "Connecting",
                note: isVideo ? "Video call started from the demo workspace." : "Audio call started from the demo workspace.",
                isVideo: isVideo,
                telegramUserID: telegramUserID
            ),
            at: 0
        )
        announce("Starting \(callKind) with \(personName).")
    }

    private func storeActiveCallSession(_ session: ActiveCallSession) {
        let previous = activeCallSession
        activeCallSession = session

        if session.phase == .incoming, previous?.id != session.id {
            selectedTab = .calls
            announce("Incoming \(session.isVideo ? "video" : "audio") call from \(session.peerName).")
            return
        }

        if previous?.phase != session.phase {
            announce("\(session.peerName). \(session.statusLabel).")

            if sessionSource == .telegram, session.phase.isTerminal {
                Task { [weak self] in
                    await self?.scheduleTelegramOverviewRefresh(delayNanoseconds: 200_000_000)
                }
            }
        }
    }

    private func updateActiveCallSession(_ update: (inout ActiveCallSession) -> Void) {
        guard var activeCallSession else {
            return
        }

        update(&activeCallSession)
        self.activeCallSession = activeCallSession
    }

    private func activeCallDurationSeconds(for session: ActiveCallSession) -> Int {
        let referenceDate = session.connectedAt ?? session.startedAt
        return max(Int(Date().timeIntervalSince(referenceDate).rounded(.down)), 0)
    }

    private func userFacingMessage(for error: any Swift.Error) -> String {
        let text = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Telegram request failed." : text
    }

    private func announce(_ text: String) {
        latestAnnouncement = text
        VoiceOverAnnouncer.post(text)
    }
}

extension UniOSAppModel: TelegramServiceDelegate {
    func telegramService(_ service: TelegramService, didReceive event: TelegramServiceEvent) {
        switch event {
        case let .authorizationChanged(state):
            handleTelegramStateUpdate(state)

        case .chatsChanged:
            Task { [weak self] in
                await self?.scheduleTelegramOverviewRefresh()
            }

        case .chatChanged:
            Task { [weak self] in
                await self?.scheduleTelegramOverviewRefresh()
            }

        case let .callUpdated(session):
            storeActiveCallSession(session)
        }
    }
}
