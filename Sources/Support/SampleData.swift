import Foundation

extension UniOSSeedData {
    static let preview = UniOSSeedData(
        chats: SampleData.chats,
        contacts: SampleData.contacts,
        calls: SampleData.calls,
        accessibilityPreferences: AccessibilityPreferences()
    )
}

enum SampleData {
    private static let now = Date()

    static let chats: [Chat] = [
        Chat(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000001") ?? UUID(),
            title: "Aurora Studio",
            handle: "@aurora",
            summary: "Prototype is ready for VoiceOver review.",
            folder: .groups,
            unreadCount: 3,
            isMuted: false,
            isPinned: true,
            participants: ["Lena", "Mateusz", "Nadia"],
            lastUpdated: now.addingTimeInterval(-480),
            messages: [
                Message(
                    id: UUID(uuidString: "20000000-0000-0000-0000-000000000001") ?? UUID(),
                    sender: "Lena",
                    text: "Navigation order now matches the visual hierarchy.",
                    timestamp: now.addingTimeInterval(-3600),
                    direction: .incoming,
                    status: .read,
                    kind: .text
                ),
                Message(
                    id: UUID(uuidString: "20000000-0000-0000-0000-000000000002") ?? UUID(),
                    sender: "Mateusz",
                    text: "Uploading the revised flow now.",
                    timestamp: now.addingTimeInterval(-1600),
                    direction: .incoming,
                    status: .read,
                    kind: .text
                ),
                Message(
                    id: UUID(uuidString: "20000000-0000-0000-0000-000000000003") ?? UUID(),
                    sender: "Nadia",
                    text: "Prototype is ready for VoiceOver review.",
                    timestamp: now.addingTimeInterval(-480),
                    direction: .incoming,
                    status: .sent,
                    kind: .voice(transcript: "Prototype is ready for VoiceOver review.", durationSeconds: 12)
                ),
                Message(
                    id: UUID(uuidString: "20000000-0000-0000-0000-000000000008") ?? UUID(),
                    sender: "Mateusz",
                    text: "Accessibility checklist March.pdf",
                    timestamp: now.addingTimeInterval(-420),
                    direction: .incoming,
                    status: .read,
                    kind: .document(
                        description: "Accessibility checklist March.pdf",
                        fileName: "Accessibility checklist March.pdf"
                    )
                )
            ],
            avatarHue: 0.58
        ),
        Chat(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000002") ?? UUID(),
            title: "Kasia Nowak",
            handle: "@kasian",
            summary: "Can you call after stand-up?",
            folder: .personal,
            unreadCount: 1,
            isMuted: false,
            isPinned: false,
            participants: ["Kasia"],
            lastUpdated: now.addingTimeInterval(-1200),
            messages: [
                Message(
                    id: UUID(uuidString: "20000000-0000-0000-0000-000000000004") ?? UUID(),
                    sender: "Kasia",
                    text: "Can you call after stand-up?",
                    timestamp: now.addingTimeInterval(-1200),
                    direction: .incoming,
                    status: .sent,
                    kind: .text
                )
            ],
            avatarHue: 0.12
        ),
        Chat(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000003") ?? UUID(),
            title: "Design Broadcast",
            handle: "@designbroadcast",
            summary: "New tactile motion rules published.",
            folder: .channels,
            unreadCount: 0,
            isMuted: true,
            isPinned: false,
            participants: ["Editorial bot"],
            lastUpdated: now.addingTimeInterval(-7200),
            messages: [
                Message(
                    id: UUID(uuidString: "20000000-0000-0000-0000-000000000005") ?? UUID(),
                    sender: "Editorial bot",
                    text: "New tactile motion rules published.",
                    timestamp: now.addingTimeInterval(-7200),
                    direction: .incoming,
                    status: .read,
                    kind: .photo(description: "A poster describing tactile motion spacing and timing.")
                )
            ],
            avatarHue: 0.86
        ),
        Chat(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000004") ?? UUID(),
            title: "Field Notes",
            handle: "@fieldnotes",
            summary: "Battery stable, location sync complete.",
            folder: .groups,
            unreadCount: 0,
            isMuted: false,
            isPinned: false,
            participants: ["Ola", "Rafał", "Marek"],
            lastUpdated: now.addingTimeInterval(-10800),
            messages: [
                Message(
                    id: UUID(uuidString: "20000000-0000-0000-0000-000000000006") ?? UUID(),
                    sender: "Ola",
                    text: "Battery stable, location sync complete.",
                    timestamp: now.addingTimeInterval(-10800),
                    direction: .incoming,
                    status: .read,
                    kind: .text
                ),
                Message(
                    id: UUID(uuidString: "20000000-0000-0000-0000-000000000009") ?? UUID(),
                    sender: "Rafał",
                    text: "Warehouse walkthrough",
                    timestamp: now.addingTimeInterval(-10400),
                    direction: .incoming,
                    status: .read,
                    kind: .video(description: "Warehouse walkthrough", durationSeconds: 37)
                )
            ],
            avatarHue: 0.32
        ),
        Chat(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000005") ?? UUID(),
            title: "Saved Notes",
            handle: "@me",
            summary: "Accessibility audit checklist updated.",
            folder: .personal,
            unreadCount: 0,
            isMuted: false,
            isPinned: true,
            participants: ["Me"],
            lastUpdated: now.addingTimeInterval(-14400),
            messages: [
                Message(
                    id: UUID(uuidString: "20000000-0000-0000-0000-000000000007") ?? UUID(),
                    sender: "Me",
                    text: "Accessibility audit checklist updated.",
                    timestamp: now.addingTimeInterval(-14400),
                    direction: .outgoing,
                    status: .read,
                    kind: .text,
                    isPinned: true
                )
            ],
            avatarHue: 0.48
        )
    ]

    static let contacts: [Contact] = [
        Contact(id: UUID(), name: "Kasia Nowak", role: "Product lead", presence: .online, isFavorite: true, avatarHue: 0.12, note: "Fast feedback on navigation and copy."),
        Contact(id: UUID(), name: "Lena Zielińska", role: "Accessibility QA", presence: .online, isFavorite: true, avatarHue: 0.58, note: "Tracks VoiceOver regressions."),
        Contact(id: UUID(), name: "Marek Lis", role: "Backend", presence: .away, isFavorite: false, avatarHue: 0.31, note: "Handles sync and caching."),
        Contact(id: UUID(), name: "Nadia Borkowska", role: "Motion design", presence: .focus, isFavorite: false, avatarHue: 0.79, note: "Prefers annotated prototypes."),
        Contact(id: UUID(), name: "Ola Jurczak", role: "Operations", presence: .away, isFavorite: false, avatarHue: 0.19, note: "Coordinates release windows.")
    ]

    static let calls: [CallLog] = [
        CallLog(id: UUID(), personName: "Kasia Nowak", direction: .outgoing, time: now.addingTimeInterval(-5400), durationDescription: "14 minutes", note: "Reviewed onboarding"),
        CallLog(id: UUID(), personName: "Lena Zielińska", direction: .incoming, time: now.addingTimeInterval(-12600), durationDescription: "8 minutes", note: "VoiceOver sweep", isVideo: true),
        CallLog(id: UUID(), personName: "Unknown caller", direction: .missed, time: now.addingTimeInterval(-18400), durationDescription: "No answer", note: "Potential recruitment spam"),
        CallLog(id: UUID(), personName: "Nadia Borkowska", direction: .missed, time: now.addingTimeInterval(-24800), durationDescription: "No answer", note: "Prototype sync", isVideo: true),
        CallLog(id: UUID(), personName: "Aurora Studio", direction: .incoming, time: now.addingTimeInterval(-43200), durationDescription: "22 minutes", note: "Sprint planning")
    ]
}
