import SwiftUI

struct AccessibilityCenterView: View {
    @EnvironmentObject private var appModel: UniOSAppModel

    var body: some View {
        List {
            Section("VoiceOver Behavior") {
                Toggle("Announce unread status changes", isOn: binding(\.announceUnreadMessages))
                Toggle("Speak sender and time in messages", isOn: binding(\.speakMessageContext))
                Toggle("Prefer compact media descriptions", isOn: binding(\.preferCompactMediaDescriptions))
                Toggle("Focus composer when a chat opens", isOn: binding(\.focusComposerOnOpen))
                Toggle("Keep unread jump shortcut enabled", isOn: binding(\.prioritizeUnreadChatsShortcut))
            }

            Section("Live Status") {
                LabeledContent("Latest announcement", value: appModel.latestAnnouncement.isEmpty ? "Nothing announced yet" : appModel.latestAnnouncement)

                Button {
                    appModel.demoAnnouncement()
                } label: {
                    Label("Play VoiceOver Status", systemImage: "speaker.wave.2.fill")
                }
            }

            Section("Manual Verification") {
                Text("Check rotor order, Dynamic Type at accessibility sizes, and Switch Control on a physical device before shipping.")
                    .foregroundStyle(UniOSTheme.quietText)
            }
        }
        .navigationTitle("Accessibility")
    }

    private func binding(_ keyPath: WritableKeyPath<AccessibilityPreferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { appModel.accessibilityPreferences[keyPath: keyPath] },
            set: { newValue in
                appModel.updateAccessibilityPreferences { preferences in
                    preferences[keyPath: keyPath] = newValue
                }
            }
        )
    }
}
