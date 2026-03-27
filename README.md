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

The current build signs into real Telegram through [Swiftgram/TDLibKit](https://github.com/Swiftgram/TDLibKit) when Telegram API credentials are available locally or through CI secrets. Demo seed data remains in the repository only as an internal fallback for development and tests.

## Priorities

- Native Swift and SwiftUI
- VoiceOver clarity before visual polish
- Dynamic Type-friendly layouts
- Explicit accessibility labels, values, and hints
- Real Telegram auth, chat sync, history loading, attachment download, media sending, and call-log sync through TDLibKit when configured
- GitHub-hosted macOS CI producing an unsigned `.ipa` artifact

## Local Development

1. Install Xcode and XcodeGen.
2. Generate the local `xcconfig` from your Postmaster credentials:

```bash
./scripts/generate_telegram_secrets.sh
```

This writes `Config/TelegramSecrets.xcconfig`, which is ignored by git.

3. Build the Telegram native VoIP static libraries and generate the VoIP xcconfig:

```bash
./scripts/build_tgvoip_static_libs.sh
```

This writes `Config/VoIPEngine.xcconfig` and fills `Vendor/TgVoip/` with the static iOS libraries and public headers generated from the official `Telegram-iOS` Bazel toolchain.

4. Generate the project:

```bash
xcodegen generate
open UniOS.xcodeproj
```

If the Telegram credentials are not present, UniOS still builds but the app will stay on the unavailable Telegram sign-in screen until `Config/TelegramSecrets.xcconfig` is provided. If the VoIP engine is not built, UniOS falls back to lifecycle-only Telegram call controls.

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
- incoming and outgoing call lifecycle updates through TDLib
- answering, declining, and ending 1:1 Telegram calls from the in-app call panel
- exposing encryption emoji, server summary, and signaling activity for active calls
- full in-call audio transport through Telegram's native `TgVoipWebrtc` engine when the VoIP static libraries are built
- in-app mute, speaker, and camera controls backed by the native Telegram media engine
- in-app remote and local video rendering for Telegram video calls

Still intentionally incomplete:

- advanced Bluetooth and input-device selection beyond the default speaker / receiver route controls
- native Apple ID / Google ID auth tokens for the email branch
- registration
- production signing and App Store distribution

## Calls Architecture Note

UniOS now handles the Telegram call lifecycle with `TDLibKit` and embeds Telegram's
native `TgVoipWebrtc` stack for 1:1 calls when the static libraries are built. The
native engine is sourced from the official `TelegramMessenger/Telegram-iOS` repository
and compiled through Bazel on a macOS runner, because it is not distributed as a small
standalone Swift Package. The generated static libraries are then linked into UniOS
through `Config/VoIPEngine.xcconfig`.

## CI

The GitHub Actions workflow:

- optionally generates `Config/TelegramSecrets.xcconfig` from repository secrets
- builds `TgVoipWebrtc` static libraries from the official `Telegram-iOS` sources on a GitHub-hosted macOS runner
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
