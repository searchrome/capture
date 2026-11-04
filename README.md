# Capture

A native macOS menu bar app for reading, translating, and chatting about what's on your screen.
Select an area with **⌘⇧6**, then extract text, translate it in place, or open an AI chat.

Built with SwiftUI and AppKit. No third-party dependencies. [MIT licensed](LICENSE).

## Features

- **Image → Text:** extract text with Apple Vision on-device or an OpenRouter vision model.
- **Translate:** show translations over the selection or in an editable result panel.
- **AI Chat:** discuss a selection with streaming replies and fresh captures.
- **Agent actions:** let the chat agent click, type, press keys, and scroll, with approval on by default.
- **Read Active Document Text:** press **⌘⌥7** to read text exposed by the focused app or a local PDF's text layer, without a screenshot or AI request.
- Configurable shortcuts, target language, models, automatic copying, and launch at login.
- Multi-display capture, including displays with different pixel densities.

## Requirements

- macOS 14 (Sonoma) or later.
- Xcode 15.3+ or a compatible Swift 5.10+ toolchain and macOS SDK. The package uses Swift 5 language mode.
- Your own OpenRouter API key for translation, chat, and LLM image-to-text. Local OCR and direct document reading do not need a key.

## Build and run

From a local checkout:

```sh
scripts/run.sh
```

This builds `build/Capture.app`, stops any running Capture instance, and launches the app.
Look for the viewfinder icon in the menu bar; Capture has no Dock icon.

Build a release app without launching it:

```sh
scripts/build-app.sh release
```

Check compilation without assembling an app bundle:

```sh
swift build
```

Use the app bundle for normal use so macOS can associate permissions and launch-at-login
with the app. Builds target the host architecture; Apple Silicon and Intel distributions
need builds for their respective architectures.

### Signing

The build script uses `CODESIGN_IDENTITY` when set, otherwise the first available Apple
Development identity, otherwise an ad-hoc signature. To select an identity:

```sh
CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" scripts/build-app.sh release
```

Keep the signing identity and app location consistent between builds because macOS permission
grants depend on app identity. The script signs locally; it does not notarize the app or create
an installer. See [the release checklist](docs/RELEASING.md) before distributing binaries.

## First-run setup

1. Open **Settings…** from Capture's menu bar icon.
2. For local OCR, select **Image → Text engine → On-device (Apple Vision)**. For AI features,
   enter your OpenRouter key and use **Test**. Select an image-capable model from the model
   list or enter a model ID available to your account.
3. Press **⌘⇧6**, grant Screen Recording access when prompted, and drag to select an area.
   The permission is under **System Settings → Privacy & Security → Screen & System Audio
   Recording** (called **Screen Recording** on some macOS versions). Reopen Capture if needed.
4. Choose **Image → Text**, **Translate**, or **AI Chat** from the floating action bar.
5. For document reading or agent input, enable Capture under **Privacy & Security →
   Accessibility** when prompted.

Translation defaults to an overlay; choose **Show translation → In a panel** in Settings
for editable text. Completed text results can copy automatically; disable **Auto-copy result**
if you prefer manual copying. Partial document reads are labelled and are not automatically copied.

Both shortcuts are configurable in Settings. If **⌘⇧6** conflicts with macOS's **Save picture
of the Touch Bar**, change it under **Keyboard → Keyboard Shortcuts → Screenshots** or choose
another Capture shortcut. Menu commands remain available if shortcut registration fails.

## Privacy and permissions

| Feature | Permission | Data sent for the action |
| --- | --- | --- |
| On-device Image → Text | Screen Recording | None; Apple Vision processes the image locally |
| Read Active Document Text | Accessibility | None; reads locally using Accessibility or PDFKit |
| LLM Image → Text / panel translation | Screen Recording | Selected image and prompt to OpenRouter |
| In-place translation | Screen Recording | Locally recognized text to OpenRouter; falls back to image translation if no text is found |
| AI Chat and agent | Screen Recording; Accessibility for input | Selection images, chat, tool results, and screen/app context to OpenRouter |

Settings fetches the model catalog from OpenRouter, and **Test** makes an authenticated key
check. AI requests are processed through OpenRouter and its model providers; their data
handling and any usage charges apply.

The API key is stored in macOS Keychain; preferences are stored in UserDefaults. Captures
and chat live in the app session. Debug builds can explicitly write screenshots and transcripts
to disk when launched with a snapshot directory. Results can also enter the system clipboard.
See [development notes](docs/DEVELOPMENT.md) before collecting debug output.

**Ask before acting** is on by default. Review proposed actions and use **Stop** to cancel a
running chat. Allowing all actions for a task or disabling the setting permits actions without
individual approval.

## Troubleshooting and limitations

- **Capture permission denied:** check Screen Recording permission, reopen Capture, and confirm
  the permission applies to the same app location and signing identity you are using.
- **Document text is missing or incomplete:** apps may expose only some text through Accessibility;
  scanned PDFs may have no text layer. Use area capture and Image → Text instead.
- **AI request fails:** check the saved key, account access, and selected model. Refresh the model
  list in Settings or enter another compatible model ID.
- **No Dock icon:** this is expected. Settings and Quit are in the menu bar.
- OCR, translations, and AI actions can make mistakes; review results and proposed input.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for reports, pull requests, and build checks.
[SPEC.md](SPEC.md) defines behavior and coordinates; [development notes](docs/DEVELOPMENT.md)
cover the source layout and debug tools. Report vulnerabilities using [SECURITY.md](SECURITY.md).

## License

Copyright © 2026 Sozay. Released under the [MIT License](LICENSE).
