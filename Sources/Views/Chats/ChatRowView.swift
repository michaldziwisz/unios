import SwiftUI

struct ChatRowView: View {
    let chat: Chat
    let speakMessageContext: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            AvatarView(initials: chat.initials, hue: chat.avatarHue)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(chat.title)
                        .font(.headline)
                        .lineLimit(1)

                    if chat.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(UniOSTheme.quietText)
                    }

                    Spacer(minLength: 12)

                    Text(chat.lastUpdatedLabel)
                        .font(.caption)
                        .foregroundStyle(UniOSTheme.quietText)
                }

                Text(chat.summary)
                    .font(.subheadline)
                    .foregroundStyle(UniOSTheme.quietText)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(chat.handle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(UniOSTheme.tint)

                    if chat.isMuted {
                        Label("Muted", systemImage: "bell.slash.fill")
                            .font(.caption)
                            .foregroundStyle(UniOSTheme.quietText)
                    }

                    Spacer()

                    if chat.unreadCount > 0 {
                        Text("\(chat.unreadCount)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(UniOSTheme.badge))
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chat.voiceOverLabel(speakContext: speakMessageContext))
        .accessibilityValue(chat.accessibilityStatus.isEmpty ? "No unread messages" : chat.accessibilityStatus)
        .accessibilityHint("Opens the conversation.")
    }
}

