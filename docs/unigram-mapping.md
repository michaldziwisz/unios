# Unigram To UniOS Mapping

UniOS is based on the public feature map exposed by the Windows client [Unigram](https://github.com/unigramdev/unigram), especially the visible module breakdown in `Telegram/ViewModels`.

## Mapped Areas

- `Authorization/*ViewModel.cs`
  - UniOS: `Sources/Views/Auth/SignInView.swift`
  - Goal: establish the entry path and accessible orientation before the user reaches the main product shell.

- `ChatListViewModel.cs`
  - UniOS: `Sources/Views/Chats/ChatListView.swift`
  - Goal: folder filters, search, unread triage, and a VoiceOver-readable conversation summary.

- `DialogViewModel*.cs`
  - UniOS: `Sources/Views/Chats/ConversationView.swift`
  - Goal: readable message transcript, explicit metadata, and a composer that can receive accessibility focus on open.

- `ContactsViewModel.cs`
  - UniOS: `Sources/Views/Contacts/ContactsView.swift`
  - Goal: expose direct message and call actions without requiring hidden gestures.

- `CallsViewModel.cs`
  - UniOS: `Sources/Views/Calls/CallsView.swift`
  - Goal: make missed-call review simple, filterable, and clearly announced.

- `SettingsViewModel.cs` and `Settings/*ViewModel.cs`
  - UniOS: `Sources/Views/Settings/SettingsView.swift`
  - Goal: centralize accessibility, appearance, notifications, and privacy flows in a touch-first form factor.

## Deliberate Scope Reduction

This first public iteration does not attempt to port:

- network stack and Telegram authentication
- media upload pipeline
- real-time sync
- business, premium, stories, or payments
- desktop-only interaction patterns

The current codebase is an iPhone-native MVP that proves layout, navigation, accessibility, and CI packaging in a form that can be extended safely.

