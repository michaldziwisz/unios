import SwiftUI

struct ChatListView: View {
    @EnvironmentObject private var appModel: UniOSAppModel
    @AccessibilityFocusState private var focusedChatID: UUID?

    private var folderCounts: [ChatFolder: Int] {
        [
            .all: appModel.chats.count,
            .unread: appModel.chats.filter { $0.unreadCount > 0 }.count,
            .personal: appModel.chats.filter { $0.folder == .personal }.count,
            .groups: appModel.chats.filter { $0.folder == .groups }.count,
            .channels: appModel.chats.filter { $0.folder == .channels }.count
        ]
    }

    var body: some View {
        List {
            summaryCard

            ForEach(appModel.filteredChats) { chat in
                NavigationLink {
                    ConversationView(chatID: chat.id)
                } label: {
                    ChatRowView(
                        chat: chat,
                        speakMessageContext: appModel.accessibilityPreferences.speakMessageContext
                    )
                }
                .accessibilityFocused($focusedChatID, equals: chat.id)
                .accessibilityAction(named: Text(chat.isMuted ? "Unmute conversation" : "Mute conversation")) {
                    appModel.toggleMuted(chatID: chat.id)
                }
                .accessibilityAction(named: Text("Mark as read")) {
                    appModel.markChatRead(chat.id)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(UniOSTheme.canvas)
        .searchable(text: $appModel.chatSearchText, prompt: "Search chats, contacts, or message text")
        .safeAreaInset(edge: .top) {
            FolderPickerView(selection: $appModel.selectedChatFolder, counts: folderCounts)
        }
        .navigationTitle("Chats")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Unread", systemImage: "text.badge.star") {
                    if let unread = appModel.jumpToFirstUnreadChat() {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            focusedChatID = unread.id
                        }
                    }
                }
                .accessibilityHint("Moves to the first unread conversation if the shortcut is enabled.")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Announce Status", systemImage: "speaker.wave.2.fill") {
                    appModel.demoAnnouncement()
                }
                .accessibilityHint("Reads the current chat and call summary through VoiceOver.")
            }
        }
        .overlay {
            if appModel.filteredChats.isEmpty {
                ContentUnavailableView(
                    "No Conversations",
                    systemImage: "tray",
                    description: Text("Try another folder or a broader search term.")
                )
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Focused Inbox")
                .font(.title3.weight(.bold))
            Text("\(appModel.filteredChats.count) conversations visible, \(folderCounts[.unread] ?? 0) still unread.")
                .foregroundStyle(UniOSTheme.quietText)
            Text("Unread triage stays available from the top bar for VoiceOver users who need quick orientation.")
                .font(.subheadline)
                .foregroundStyle(UniOSTheme.quietText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .uniosCard()
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .combine)
    }
}

