import SwiftUI

struct MessageBubbleView: View {
    let message: Message
    let speakContext: Bool
    let compactMediaDescriptions: Bool
    let isAttachmentLoading: Bool
    let isAttachmentActive: Bool
    let attachmentActionLabel: String?
    let attachmentActionHint: String?
    let attachmentAction: (() -> Void)?

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
            .accessibilityHint(accessibilityHint)
            .modifier(
                AttachmentActivationModifier(
                    attachmentAction: attachmentAction
                )
            )

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
            attachmentCard(
                title: "Voice note · \(durationSeconds)s",
                systemImage: "waveform",
                primaryText: compactMediaDescriptions ? nil : transcript
            )

        case let .photo(description):
            attachmentCard(
                title: "Photo attachment",
                systemImage: "photo.fill",
                primaryText: compactMediaDescriptions ? nil : description
            )

        case let .document(description, fileName):
            attachmentCard(
                title: "Document",
                systemImage: "doc.fill",
                primaryText: compactMediaDescriptions ? nil : description,
                secondaryText: compactMediaDescriptions ? nil : fileName
            )

        case let .audio(description, durationSeconds):
            attachmentCard(
                title: durationSeconds.map { "Audio attachment · \($0)s" } ?? "Audio attachment",
                systemImage: "waveform",
                primaryText: compactMediaDescriptions ? nil : description
            )

        case let .video(description, durationSeconds):
            attachmentCard(
                title: durationSeconds.map { "Video attachment · \($0)s" } ?? "Video attachment",
                systemImage: "video.fill",
                primaryText: compactMediaDescriptions ? nil : description
            )
        }
    }

    private func attachmentCard(
        title: String,
        systemImage: String,
        primaryText: String?,
        secondaryText: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))

            if let primaryText, !primaryText.isEmpty {
                Text(primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let secondaryText, !secondaryText.isEmpty {
                Text(secondaryText)
                    .font(.caption)
                    .foregroundStyle(UniOSTheme.quietText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isAttachmentLoading {
                ProgressView()
                    .accessibilityLabel("Attachment is loading")
            } else if let attachmentActionLabel, let attachmentAction {
                Button(action: attachmentAction) {
                    Label(attachmentActionLabel, systemImage: actionSystemImage)
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .accessibilityHint(attachmentActionHint ?? "Opens the attachment.")
            }
        }
    }

    private var actionSystemImage: String {
        if isAttachmentActive {
            return "pause.fill"
        }

        switch message.attachment?.kind {
        case .audio, .voiceNote:
            return "play.fill"
        case .document:
            return "arrow.down.doc.fill"
        case .photo:
            return "arrow.down.circle.fill"
        case .video, .videoNote:
            return "play.rectangle.fill"
        case .none:
            return "paperclip"
        }
    }

    private var accessibilityHint: String {
        let baseHint = "Message from \(message.timestampLabel)."
        guard let attachmentActionHint, attachmentAction != nil else {
            return baseHint
        }
        return "\(baseHint) \(attachmentActionHint)"
    }
}

private struct AttachmentActivationModifier: ViewModifier {
    let attachmentAction: (() -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let attachmentAction {
            content
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    attachmentAction()
                }
        } else {
            content
        }
    }
}
