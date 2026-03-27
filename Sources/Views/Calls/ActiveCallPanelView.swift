import SwiftUI

struct ActiveCallPanelView: View {
    @EnvironmentObject private var appModel: UniOSAppModel
    @State private var showsDetails = false

    var body: some View {
        if let session = appModel.activeCallSession {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: session.isVideo ? "video.fill" : "phone.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(session.needsAttention ? Color.red : UniOSTheme.tint)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(session.peerName)
                            .font(.headline)

                        Text(session.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(UniOSTheme.quietText)

                        Text(session.statusLabel)
                            .font(.subheadline)
                            .foregroundStyle(session.needsAttention ? Color.red : UniOSTheme.quietText)
                    }

                    Spacer()
                }

                Text(session.mediaEngineSummary)
                    .font(.subheadline)
                    .foregroundStyle(UniOSTheme.quietText)
                    .accessibilityHint("This explains whether UniOS is carrying the media stream itself or only the Telegram call lifecycle.")

                DisclosureGroup(showsDetails ? "Hide Technical Details" : "Show Technical Details", isExpanded: $showsDetails) {
                    VStack(alignment: .leading, spacing: 8) {
                        if !session.encryptionEmoji.isEmpty {
                            detailRow(title: "Encryption", value: session.encryptionEmoji.joined(separator: " "))
                        }

                        if let serverSummary = session.serverSummary, !serverSummary.isEmpty {
                            detailRow(title: "Servers", value: serverSummary)
                        }

                        detailRow(title: "Signaling", value: session.signalingSummary)

                        if let allowsPeerToPeer = session.allowsPeerToPeer {
                            detailRow(
                                title: "Peer to Peer",
                                value: allowsPeerToPeer ? "Allowed" : "Relay only"
                            )
                        }

                        if session.supportsGroupUpgrade {
                            detailRow(
                                title: "Upgrade",
                                value: "The peer can upgrade this call to a group call."
                            )
                        }

                        if session.customParametersAvailable {
                            detailRow(
                                title: "Custom Parameters",
                                value: "Telegram provided custom media parameters for an external call engine."
                            )
                        }
                    }
                    .padding(.top, 4)
                }
                .tint(UniOSTheme.tint)

                HStack(spacing: 10) {
                    if session.canAccept {
                        Button {
                            appModel.acceptActiveCall()
                        } label: {
                            Label("Answer", systemImage: "phone.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityHint("Accepts the incoming Telegram call.")
                    }

                    if session.canDeclineOrEnd {
                        Button(role: .destructive) {
                            appModel.endActiveCall()
                        } label: {
                            Label(session.canAccept ? "Decline" : "End Call", systemImage: "phone.down.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .accessibilityHint(session.canAccept ? "Declines the incoming Telegram call." : "Ends the current Telegram call.")
                    } else {
                        Button {
                            appModel.dismissActiveCallPanel()
                        } label: {
                            Label("Dismiss", systemImage: "xmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityHint("Dismisses the finished call summary.")
                    }
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(UniOSTheme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 10, y: 4)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(session.accessibilitySummary)
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(UniOSTheme.quietText)

            Text(value)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
