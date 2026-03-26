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

## Priorities

- Native Swift and SwiftUI
- VoiceOver clarity before visual polish
- Dynamic Type-friendly layouts
- Explicit accessibility labels, values, and hints
- GitHub-hosted macOS CI producing an unsigned `.ipa` artifact

## Local Development

1. Install Xcode and XcodeGen.
2. Generate the project:

```bash
xcodegen generate
open UniOS.xcodeproj
```

## CI

The GitHub Actions workflow:

- installs XcodeGen on a GitHub-hosted macOS runner
- generates the Xcode project
- runs unit tests on an available iPhone simulator
- archives an unsigned iOS build
- packages the `.app` into an unsigned `.ipa`
- uploads the `.ipa` and the archive as workflow artifacts

## Reference

- Unigram feature map notes: [docs/unigram-mapping.md](docs/unigram-mapping.md)
- Accessibility decisions: [docs/accessibility.md](docs/accessibility.md)

