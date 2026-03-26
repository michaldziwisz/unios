import SwiftUI

private enum PreviewLength: String, CaseIterable, Identifiable {
    case short
    case balanced
    case verbose

    var id: Self { self }

    var title: String {
        rawValue.capitalized
    }
}

private struct AppearanceSettingsView: View {
    @State private var previewLength: PreviewLength = .balanced
    @State private var emphasizeUnreadBadges = true
    @State private var denserConversationRows = false

    var body: some View {
        List {
            Section("Layout") {
                Picker("Preview length", selection: $previewLength) {
                    ForEach(PreviewLength.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }

                Toggle("Emphasize unread badges", isOn: $emphasizeUnreadBadges)
                Toggle("Use denser conversation rows", isOn: $denserConversationRows)
            }
        }
        .navigationTitle("Appearance")
    }
}

private struct NotificationSettingsView: View {
    @State private var showMessagePreviews = true
    @State private var announcePinnedMessages = true
    @State private var useHaptics = true

    var body: some View {
        List {
            Section("Alerts") {
                Toggle("Show message previews", isOn: $showMessagePreviews)
                Toggle("Announce pinned messages", isOn: $announcePinnedMessages)
                Toggle("Use haptics when available", isOn: $useHaptics)
            }
        }
        .navigationTitle("Notifications")
    }
}

private struct PrivacySettingsView: View {
    @State private var lockAtLaunch = false
    @State private var hideLastSeen = true
    @State private var filterUnknownCallers = true

    var body: some View {
        List {
            Section("Safety") {
                Toggle("Require passcode at launch", isOn: $lockAtLaunch)
                Toggle("Hide last seen from non-contacts", isOn: $hideLastSeen)
                Toggle("Filter unknown callers", isOn: $filterUnknownCallers)
            }
        }
        .navigationTitle("Privacy")
    }
}

struct SettingsView: View {
    @EnvironmentObject private var appModel: UniOSAppModel

    var body: some View {
        List {
            VStack(alignment: .leading, spacing: 12) {
                Text(appModel.profileName)
                    .font(.title2.weight(.bold))
                Text(appModel.activeAccountHandle)
                    .font(.headline)
                    .foregroundStyle(UniOSTheme.tint)
                Text(appModel.latestAnnouncement.isEmpty ? "No announcements yet." : appModel.latestAnnouncement)
                    .font(.subheadline)
                    .foregroundStyle(UniOSTheme.quietText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .uniosCard()
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section("Core Settings") {
                NavigationLink {
                    AccessibilityCenterView()
                } label: {
                    Label("Accessibility", systemImage: "figure.wave.circle")
                }

                NavigationLink {
                    AppearanceSettingsView()
                } label: {
                    Label("Appearance", systemImage: "paintpalette.fill")
                }

                NavigationLink {
                    NotificationSettingsView()
                } label: {
                    Label("Notifications", systemImage: "bell.badge.fill")
                }

                NavigationLink {
                    PrivacySettingsView()
                } label: {
                    Label("Privacy & Security", systemImage: "lock.shield.fill")
                }
            }

            Section("Quick Toggles") {
                Toggle("Speak sender and time in messages", isOn: accessibilityBinding(\.speakMessageContext))
                Toggle("Focus composer on open", isOn: accessibilityBinding(\.focusComposerOnOpen))
            }

            Section("Account") {
                Button(role: .destructive) {
                    appModel.signOut()
                } label: {
                    Label(appModel.sessionSource == .telegram ? "Sign Out Of Telegram" : "Sign Out Of Demo", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .navigationTitle("Settings")
    }

    private func accessibilityBinding(_ keyPath: WritableKeyPath<AccessibilityPreferences, Bool>) -> Binding<Bool> {
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
