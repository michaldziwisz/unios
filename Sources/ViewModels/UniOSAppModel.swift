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
    @Published var chats: [Chat]
    @Published var contacts: [Contact]
    @Published var calls: [CallLog]
    @Published var accessibilityPreferences: AccessibilityPreferences
    @Published private(set) var latestAnnouncement = ""

    private let seed: UniOSSeedData

    init(seed: UniOSSeedData = .preview) {
        self.seed = seed
        self.chats = seed.chats
        self.contacts = seed.contacts
        self.calls = seed.calls
        self.accessibilityPreferences = seed.accessibilityPreferences
    }

    var profileName: String {
        let trimmed = signInName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "VoiceOver Pilot" : trimmed
    }

    var filteredChats: [Chat] {
        ChatFiltering.apply(chats: chats, folder: selectedChatFolder, searchQuery: chatSearchText)
    }

    var filteredCalls: [CallLog] {
        let items = showMissedCallsOnly ? calls.filter { $0.direction == .missed } : calls
        return items.sorted { $0.time > $1.time }
    }

    func signInDemo() {
        isAuthenticated = true
        announce("\(profileName) signed in. \(filteredChats.count) conversations ready.")
    }

    func signOut() {
        isAuthenticated = false
        selectedTab = .chats
        selectedChatFolder = .all
        chatSearchText = ""
        showMissedCallsOnly = false
        chats = seed.chats
        contacts = seed.contacts
        calls = seed.calls
        accessibilityPreferences = seed.accessibilityPreferences
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

        mutateChat(chatID) { chat in
            chat.unreadCount = 0
        }

        if accessibilityPreferences.announceUnreadMessages {
            announce("\(chat.title) marked as read.")
        }
    }

    func toggleMuted(chatID: UUID) {
        guard let chat = chat(for: chatID) else {
            return
        }
        mutateChat(chatID) { draft in
            draft.isMuted.toggle()
        }
        announce("\(chat.title) \(chat.isMuted ? "unmuted" : "muted").")
    }

    func sendMessage(_ rawText: String, to chatID: UUID) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            announce("Message is empty.")
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

        if let chat = chat(for: chatID) {
            announce("Message sent to \(chat.title).")
        }
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

    func startChat(with contact: Contact) -> UUID {
        if let existing = chats.first(where: { $0.title == contact.name || $0.participants.contains(contact.name) }) {
            announce("Opening chat with \(contact.name).")
            return existing.id
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
        return newChatID
    }

    func updateAccessibilityPreferences(_ change: (inout AccessibilityPreferences) -> Void) {
        var updated = accessibilityPreferences
        change(&updated)
        accessibilityPreferences = updated
        announce("Accessibility preferences updated.")
    }

    func demoAnnouncement() {
        announce(
            "VoiceOver status. \(filteredChats.count) visible chats, \(filteredCalls.count) visible calls, unread shortcut \(accessibilityPreferences.prioritizeUnreadChatsShortcut ? "enabled" : "disabled")."
        )
    }

    private func mutateChat(_ chatID: UUID, update: (inout Chat) -> Void) {
        guard let index = chats.firstIndex(where: { $0.id == chatID }) else {
            return
        }
        var chat = chats[index]
        update(&chat)
        chats[index] = chat
    }

    private func announce(_ text: String) {
        latestAnnouncement = text
        VoiceOverAnnouncer.post(text)
    }
}
