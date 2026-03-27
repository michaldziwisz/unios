import SwiftUI

struct ActiveCallVideoStageView: View {
    @EnvironmentObject private var appModel: UniOSAppModel

    let session: ActiveCallSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                CallVideoHostView { completion in
                    appModel.makeActiveCallIncomingVideoView(completion: completion)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(session.remoteVideoState.summary, systemImage: "video.fill")
                            .font(.caption.weight(.semibold))
                        Text(session.remoteAudioMuted ? "Remote microphone muted" : "Remote audio active")
                            .font(.caption)
                    }
                    .foregroundStyle(Color.white)
                    .padding(12)
                    .background(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.72),
                                Color.black.opacity(0.12)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityHidden(true)

                CallVideoHostView { completion in
                    appModel.makeActiveCallOutgoingVideoView(completion: completion)
                }
                .frame(width: 112, height: 148)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
                .padding(12)
                .accessibilityHidden(true)
            }

            Text(session.localVideoEnabled ? "Camera is on." : "Camera is paused.")
                .font(.caption)
                .foregroundStyle(UniOSTheme.quietText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(session.peerName) video stage. \(session.remoteVideoState.summary). \(session.remoteAudioMuted ? "Remote microphone muted." : "Remote audio active."). \(session.localVideoEnabled ? "Camera on." : "Camera off.")"
        )
        .accessibilityHint("Video surfaces are visual only. Use the call controls below for mute, speaker, and camera actions.")
    }
}
