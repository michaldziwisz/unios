import SwiftUI

struct MessageBubbleView: View {
    let message: Message
    let speakContext: Bool
    let compactMediaDescriptions: Bool

    var body: some View {
        HStack {
            if message.direction == .outgoing {
                Spacer(minLength: 48)
            }

            VStack(alignment: .leading, spacing: 8) {
                if message.direction == .incoming {
                    Text(message.sender)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(UniOSTheme.quietText)
                }

                content

                HStack(spacing: 8) {
                    Text(message.timestampLabel)
                        .font(.caption2)
                        .foregroundStyle(UniOSTheme.quietText)

                    if message.direction == .outgoing {
                        Text(message.status.accessibilityText)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(UniOSTheme.quietText)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(message.direction == .outgoing ? UniOSTheme.tint.opacity(0.16) : Color(uiColor: .systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .frame(maxWidth: .infinity, alignment: message.direction == .incoming ? .leading : .trailing)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(message.voiceOverLabel(speakContext: speakContext))
            .accessibilityValue(message.direction == .outgoing ? message.status.accessibilityText : "Received")
            .accessibilityHint("Message from \(message.timestampLabel).")

            if message.direction == .incoming {
                Spacer(minLength: 48)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch message.kind {
        case .text:
            Text(message.text)
                .fixedSize(horizontal: false, vertical: true)

        case let .voice(transcript, durationSeconds):
            VStack(alignment: .leading, spacing: 8) {
                Label("Voice note · \(durationSeconds)s", systemImage: "waveform")
                    .font(.subheadline.weight(.semibold))
                if !compactMediaDescriptions {
                    Text(transcript)
                }
            }

        case let .photo(description):
            VStack(alignment: .leading, spacing: 8) {
                Label("Photo attachment", systemImage: "photo.fill")
                    .font(.subheadline.weight(.semibold))
                if !compactMediaDescriptions {
                    Text(description)
                }
            }
        }
    }
}

