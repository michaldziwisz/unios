# UniOS

VoiceOver-first native iOS MVP inspired by the feature map of the Windows client [Unigram](https://github.com/unigramdev/unigram).

This repository does not attempt a full 1:1 port of Unigram. It reinterprets the core product areas for iPhone in native SwiftUI:

- Authentication
- Chat list and folders
- Conversation view
- Contacts
- Calls
- Settings
- Accessibility center for VoiceOver users

The current build keeps a demo workspace and also includes a real Telegram bridge through [Swiftgram/TDLibKit](https://github.com/Swiftgram/TDLibKit) when Telegram API credentials are available locally or through CI secrets.

## Priorities

- Native Swift and SwiftUI
- VoiceOver clarity before visual polish
- Dynamic Type-friendly layouts
- Explicit accessibility labels, values, and hints
- Real Telegram auth, chat sync, history loading, attachment download, media sending, and call-log sync through TDLibKit when configured
- GitHub-hosted macOS CI producing an unsigned `.ipa` artifact

## Local Development

1. Install Xcode and XcodeGen.
2. Optional but recommended for real Telegram sign in: generate the local `xcconfig` from your Postmaster credentials:

```bash
./scripts/generate_telegram_secrets.sh
```

This writes `Config/TelegramSecrets.xcconfig`, which is ignored by git.

3. Generate the project:

```bash
xcodegen generate
open UniOS.xcodeproj
```

If the Telegram credentials are not present, UniOS still builds and runs in demo mode.

## Telegram Integration

The `TDLibKit` path currently covers:

- Telegram phone-number auth
- email-address step when Telegram requires it
- email-code verification
- code verification
- device-confirmation link and QR handoff for accounts that require confirmation on another logged-in device
- 2-step password verification
- restoring an already authorized TDLib session
- synced chat list
- synced chat history when a conversation opens
- sending text messages
- sending photo attachments from Photos, camera capture, or Files
- sending audio files, video files, and general documents from the Files importer
- recording and sending native voice notes
- downloading remote Telegram attachments on demand
- opening downloaded photos, videos, and documents inside UniOS
- inline playback for downloaded audio attachments and voice notes
- loading Telegram contacts into the Contacts tab
- loading Telegram call history into the Calls tab
- best-effort outgoing audio and video call requests for direct Telegram contacts

Still intentionally incomplete:

- full in-call audio and video session handling inside UniOS after Telegram accepts a call
- mute/unmute sync
- incoming-call UI and ongoing-call controls backed by Telegram's native call engine
- native Apple ID / Google ID auth tokens for the email branch
- registration
- production signing and App Store distribution

## CI

The GitHub Actions workflow:

- optionally generates `Config/TelegramSecrets.xcconfig` from repository secrets
- installs XcodeGen on a GitHub-hosted macOS runner
- generates the Xcode project
- runs unit tests on an available iPhone simulator
- archives an unsigned iOS build
- packages the `.app` into an unsigned `.ipa`
- uploads the `.ipa` and the archive as workflow artifacts

If you want the CI artifact to include a Telegram-capable build, set these repository secrets:

- `TELEGRAM_API_ID`
- `TELEGRAM_API_HASH`

## Reference

- Unigram feature map notes: [docs/unigram-mapping.md](docs/unigram-mapping.md)
- Accessibility decisions: [docs/accessibility.md](docs/accessibility.md)
