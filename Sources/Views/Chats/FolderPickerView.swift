import SwiftUI

struct FolderPickerView: View {
    @Binding var selection: ChatFolder
    let counts: [ChatFolder: Int]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ChatFolder.allCases) { folder in
                    Button {
                        selection = folder
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: folder.systemImage)
                            Text(folder.title)
                                .fontWeight(.semibold)

                            if let count = counts[folder], count > 0 {
                                Text("\(count)")
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule()
                                            .fill(selection == folder ? Color.white.opacity(0.22) : UniOSTheme.tint.opacity(0.12))
                                    )
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .foregroundStyle(selection == folder ? Color.white : Color.primary)
                        .background(
                            Capsule()
                                .fill(selection == folder ? UniOSTheme.tint : Color(uiColor: .systemBackground))
                        )
                        .overlay(
                            Capsule()
                                .stroke(UniOSTheme.tint.opacity(selection == folder ? 0.0 : 0.14), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(folder.title)
                    .accessibilityValue(folderCountLabel(for: folder))
                    .accessibilityHint("Filters the conversation list.")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(.thinMaterial)
    }

    private func folderCountLabel(for folder: ChatFolder) -> String {
        let count = counts[folder] ?? 0
        if folder == .all {
            return "\(count) conversations"
        }
        return "\(count) matching conversations"
    }
}

