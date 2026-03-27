import SwiftUI

struct CallsView: View {
    @EnvironmentObject private var appModel: UniOSAppModel

    private var missedOnlyBinding: Binding<Bool> {
        Binding(
            get: { appModel.showMissedCallsOnly },
            set: { newValue in
                if newValue != appModel.showMissedCallsOnly {
                    appModel.toggleMissedCallsOnly()
                }
            }
        )
    }

    var body: some View {
        List {
            VStack(alignment: .leading, spacing: 12) {
                Text("Call Review")
                    .font(.title3.weight(.bold))
                Toggle("Show missed calls only", isOn: missedOnlyBinding)
                Text("The filter is spoken immediately so VoiceOver users know whether the list narrowed.")
                    .font(.subheadline)
                    .foregroundStyle(UniOSTheme.quietText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .uniosCard()
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            ForEach(appModel.filteredCalls) { entry in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label(entry.personName, systemImage: entry.direction.systemImage)
                            .font(.headline)
                            .foregroundStyle(entry.direction == .missed ? Color.red : Color.primary)
                        Spacer()
                        Text(entry.timeLabel)
                            .font(.caption)
                            .foregroundStyle(UniOSTheme.quietText)
                    }

                    Text("\(entry.isVideo ? "Video" : "Audio") · \(entry.direction.label) · \(entry.durationDescription)")
                        .font(.subheadline)
                        .foregroundStyle(UniOSTheme.quietText)

                    Text(entry.note)
                        .font(.caption)
                        .foregroundStyle(UniOSTheme.quietText)

                    Button {
                        appModel.call(entry)
                    } label: {
                        Label(entry.isVideo ? "Start Video" : "Call Back", systemImage: entry.isVideo ? "video.fill" : "phone.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(appModel.sessionSource == .telegram && entry.telegramUserID == nil)
                    .accessibilityHint(callButtonHint(for: entry))
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("\(entry.personName). \(entry.isVideo ? "Video" : "Audio"). \(entry.direction.label) call. \(entry.durationDescription). \(entry.timeLabel). \(entry.note)")
            }
        }
        .navigationTitle("Calls")
        .overlay {
            if appModel.filteredCalls.isEmpty {
                ContentUnavailableView(
                    "No Calls",
                    systemImage: "phone",
                    description: Text(appModel.sessionSource == .telegram ? "No Telegram call records were found for the current filter yet." : "There are no call records for the selected filter.")
                )
            }
        }
    }

    private func callButtonHint(for entry: CallLog) -> String {
        if appModel.sessionSource == .telegram, entry.telegramUserID == nil {
            return "This call can only be reviewed in the current build because Telegram can start calls only for direct contacts."
        }

        return entry.isVideo ? "Starts a video call with \(entry.personName)." : "Calls \(entry.personName) again."
    }
}
