import SwiftUI

@MainActor
final class UniOSAppModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var selectedTab: AppTab = .chats
    @Published var selectedChatFolder: ChatFolder = .all
    @Published var chatSearchText = ""
    @Published var showMissedCallsOnly = false
    @Published var signInPhoneNumber = "+48 600 000 000"
    @Published var signInName = "VoiceOver Pilot"
    @Published var signInVerificationCode = ""
    @Published var signInPassword = ""
    @Published var chats: [Chat]
    @Published var contacts: [Contact]
    @Published var calls: [CallLog]
    @Published var accessibilityPreferences: AccessibilityPreferences
    @Published private(set) var latestAnnouncement = ""
    @Published private(set) var sessionSource: SessionSource = .demo
    @Published private(set) var telegramSignInState: TelegramSignInState
    @Published private(set) var telegramProfile: TelegramAccountProfile?
    @Published private(set) var isSyncingTelegramData = false

    private let seed: UniOSSeedData
    private let telegramService: TelegramService?
    private var overviewRefreshTask: Task<Void, Never>?

    init(seed: UniOSSeedData = .preview) {
        self.seed = seed
        self.chats = seed.chats
        self.contacts = seed.contacts
        self.calls = seed.calls
        self.accessibilityPreferences = seed.accessibilityPreferences

        if let configuration = TelegramAppConfiguration.load() {
            let service = TelegramService(configuration: configuration)
            self.telegramService = service
            self.telegramSignInState = .working(message: "Checking the Telegram session.")
            service.delegate = self

            Task { [weak self] in
                await self?.bootstrapTelegramSession()
            }
        } else {
            self.telegramService = nil
            self.telegramSignInState = .unavailable(
                message: "Telegram credentials are not configured in this build. Run scripts/generate_telegram_secrets.sh or continue with the demo workspace."
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
        telegramService != nil
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
        isAuthenticated = true
        announce("\(profileName) signed in. \(filteredChats.count) conversations ready.")
    }

    func submitTelegramPhoneNumber() {
        guard let telegramService else {
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
                try await telegramService.submitPhoneNumber(phoneNumber)
            } catch {
                await self?.handleTelegramFailure(error, fallbackState: .waitingForPhone)
            }
        }
    }

    func submitTelegramCode() {
        guard let telegramService else {
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
                try await telegramService.submitCode(code)
            } catch {
                await self?.handleTelegramFailure(error, fallbackState: .waitingForCode(message: "Enter the Telegram code."))
            }
        }
    }

    func submitTelegramPassword() {
        guard let telegramService else {
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

                await self?.bootstrapTelegramSession()
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

        mutateChat(chatID) { chat in
            let message = Message(
                id: UUID(),
                sender: profileName,
                text: text,
                timestamp: Date(),
                direction: .outgoing,
                status: .sent,
                kind: .text
            )
            chat.messages.append(message)
            chat.summary = text
            chat.lastUpdated = message.timestamp
            chat.unreadCount = 0
        }

        announce("Message sent to \(chat.title).")
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
        announce("Calling \(personName).")
    }

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

    private func bootstrapTelegramSession() async {
        guard let telegramService else {
            return
        }

        do {
            let state = try await telegramService.start()
            handleTelegramStateUpdate(state)
        } catch {
            await handleTelegramFailure(error, fallbackState: .waitingForPhone)
        }
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

        case .waitingForCode, .waitingForPassword, .failed:
            if previousState != newState {
                announce(newState.statusMessage)
            }

        case .waitingForPhone:
            if sessionSource == .telegram && isAuthenticated {
                isAuthenticated = false
                telegramProfile = nil
            }

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
            let loadedChats = try await telegramService.loadChats(limit: 40, currentUserDisplayName: profile.displayName)
            let loadedContacts = try await telegramService.loadContacts(limit: 40)

            telegramProfile = profile
            signInName = profile.displayName
            if !profile.phoneNumber.isEmpty {
                signInPhoneNumber = profile.phoneNumber
            }
            signInVerificationCode = ""
            signInPassword = ""
            sessionSource = .telegram
            telegramSignInState = .ready
            chats = mergeTelegramChatsPreservingLoadedMessages(loadedChats)
            contacts = loadedContacts
            calls = []
            isAuthenticated = true
            selectedTab = .chats
            announce("\(profile.displayName) signed in via Telegram. \(loadedChats.count) conversations synced.")
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
            let loadedChats = try await telegramService.loadChats(limit: 40, currentUserDisplayName: profile.displayName)
            let loadedContacts = try await telegramService.loadContacts(limit: 40)
            chats = mergeTelegramChatsPreservingLoadedMessages(loadedChats)
            contacts = loadedContacts
            calls = []
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

    private func handleTelegramFailure(_ error: Error, fallbackState: TelegramSignInState) async {
        let message = userFacingMessage(for: error)
        telegramSignInState = .failed(message: message)
        if !isAuthenticated {
            sessionSource = .demo
        }
        announce(message)
        if case .waitingForPhone = fallbackState {
            signInVerificationCode = ""
            signInPassword = ""
        }
    }

    private func resetToSignedOutState() {
        overviewRefreshTask?.cancel()
        overviewRefreshTask = nil
        isAuthenticated = false
        sessionSource = .demo
        telegramProfile = nil
        selectedTab = .chats
        selectedChatFolder = .all
        chatSearchText = ""
        showMissedCallsOnly = false
        signInVerificationCode = ""
        signInPassword = ""
        chats = seed.chats
        contacts = seed.contacts
        calls = seed.calls
        accessibilityPreferences = seed.accessibilityPreferences

        if telegramService != nil {
            telegramSignInState = .waitingForPhone
        } else {
            telegramSignInState = .unavailable(
                message: "Telegram credentials are not configured in this build. Run scripts/generate_telegram_secrets.sh or continue with the demo workspace."
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

    private func userFacingMessage(for error: Error) -> String {
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
        }
    }
}
