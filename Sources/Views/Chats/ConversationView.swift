import SwiftUI

struct ConversationView: View {
    @EnvironmentObject private var appModel: UniOSAppModel

    let chatID: UUID

    @State private var draft = ""
    @AccessibilityFocusState private var composerFocused: Bool

    var body: some View {
        Group {
            if let chat = appModel.chat(for: chatID) {
                conversationBody(chat: chat)
            } else {
                ContentUnavailableView(
                    "Conversation Unavailable",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("The selected chat could not be loaded.")
                )
            }
        }
    }

    private func conversationBody(chat: Chat) -> some View {
        let messages = chat.messages.sorted { $0.timestamp < $1.timestamp }

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    headerCard(chat: chat)

                    ForEach(messages) { message in
                        MessageBubbleView(
                            message: message,
                            speakContext: appModel.accessibilityPreferences.speakMessageContext,
                            compactMediaDescriptions: appModel.accessibilityPreferences.preferCompactMediaDescriptions
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 120)
            }
            .background(UniOSTheme.canvas.ignoresSafeArea())
            .navigationTitle(chat.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(chat.isMuted ? "Unmute" : "Mute", systemImage: chat.isMuted ? "bell.fill" : "bell.slash.fill") {
                        appModel.toggleMuted(chatID: chatID)
                    }

                    Button("Focus Composer", systemImage: "keyboard.fill") {
                        composerFocused = true
                    }
                    .accessibilityHint("Moves VoiceOver focus to the message composer.")
                }
            }
            .safeAreaInset(edge: .bottom) {
                composerBar(chatTitle: chat.title)
            }
            .onAppear {
                appModel.markChatRead(chatID)
                if let lastID = messages.last?.id {
                    DispatchQueue.main.async {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
                if appModel.accessibilityPreferences.focusComposerOnOpen {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        composerFocused = true
                    }
                }
            }
            .onChange(of: messages.count) { _ in
                if let lastID = messages.last?.id {
                    DispatchQueue.main.async {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func headerCard(chat: Chat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(chat.handle)
                .font(.headline)
                .foregroundStyle(UniOSTheme.tint)

            Text("\(chat.participants.count) participant\(chat.participants.count == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(UniOSTheme.quietText)

            if !chat.accessibilityStatus.isEmpty {
                Label(chat.accessibilityStatus, systemImage: "eye.fill")
                    .font(.subheadline)
                    .foregroundStyle(UniOSTheme.quietText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .uniosCard()
        .accessibilityElement(children: .combine)
    }

    private func composerBar(chatTitle: String) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .bottom, spacing: 12) {
                TextField("Reply to \(chatTitle)", text: $draft, axis: .vertical)
                    .lineLimit(1 ... 4)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(uiColor: .systemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(UniOSTheme.tint.opacity(0.14), lineWidth: 1)
                    )
                    .accessibilityLabel("Message Input")
                    .accessibilityHint("Double tap to type a reply to \(chatTitle).")
                    .accessibilityFocused($composerFocused)

                Button {
                    appModel.sendMessage(draft, to: chatID)
                    draft = ""
                    composerFocused = true
                } label: {
                    Label("Send", systemImage: "paperplane.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .background(.ultraThinMaterial)
    }
}

