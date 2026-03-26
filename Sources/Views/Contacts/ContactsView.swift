import SwiftUI

private struct ContactConversationRoute: Identifiable, Hashable {
    let id: UUID
}

struct ContactsView: View {
    @EnvironmentObject private var appModel: UniOSAppModel
    @State private var route: ContactConversationRoute?

    private var favoriteContacts: [Contact] {
        appModel.contacts.filter { $0.isFavorite }
    }

    private var otherContacts: [Contact] {
        appModel.contacts.filter { !$0.isFavorite }
    }

    var body: some View {
        List {
            if !favoriteContacts.isEmpty {
                Section("Favorites") {
                    ForEach(favoriteContacts) { contact in
                        contactRow(contact: contact, route: $route)
                    }
                }
            }

            Section("All Contacts") {
                ForEach(otherContacts) { contact in
                    contactRow(contact: contact, route: $route)
                }
            }
        }
        .navigationTitle("Contacts")
        .navigationDestination(item: $route) { route in
            ConversationView(chatID: route.id)
        }
        .overlay {
            if favoriteContacts.isEmpty && otherContacts.isEmpty {
                ContentUnavailableView(
                    "No Contacts",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text(appModel.sessionSource == .telegram ? "Telegram contacts are still syncing or unavailable for this account." : "There are no contacts in the current demo workspace.")
                )
            }
        }
    }

    private func contactRow(contact: Contact, route: Binding<ContactConversationRoute?>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                AvatarView(initials: contact.initials, hue: contact.avatarHue, size: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(contact.name)
                        .font(.headline)
                    Text("\(contact.role) · \(contact.presence.description)")
                        .font(.subheadline)
                        .foregroundStyle(UniOSTheme.quietText)
                    Text(contact.note)
                        .font(.caption)
                        .foregroundStyle(UniOSTheme.quietText)
                }
            }

            HStack {
                Button {
                    appModel.startChat(with: contact) { chatID in
                        guard let chatID else {
                            return
                        }
                        route.wrappedValue = ContactConversationRoute(id: chatID)
                    }
                } label: {
                    Label("Message", systemImage: "bubble.left.fill")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    appModel.call(contact.name)
                } label: {
                    Label("Call", systemImage: "phone.fill")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(contact.name). \(contact.role). \(contact.presence.description). \(contact.note)")
        .accessibilityHint("Message or call actions are available below.")
    }
}
