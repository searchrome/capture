# Development notes

Read [SPEC.md](../SPEC.md) for behavior and coordinate conventions. Stored rectangles use
global Core Graphics points (top-left origin); convert explicitly at AppKit boundaries.

## Source layout

| Path | Purpose |
| --- | --- |
| `Sources/Capture/main.swift`, `AppDelegate.swift` | App lifecycle and menu bar |
| `Sources/Capture/Capture/` | ScreenCaptureKit capture and selection overlays |
| `Sources/Capture/Hotkey/` | Global shortcuts |
| `Sources/Capture/Settings/` | Preferences, Keychain, settings UI |
| `Sources/Capture/LLM/` | OpenRouter streaming, types, model catalog |
| `Sources/Capture/Features/` | OCR, translation, local document reading |
| `Sources/Capture/Chat/`, `Agent/` | Chat, approvals, synthesized input |
| `Sources/Capture/UI/` | Floating action, result, translation, highlight panels |
| `Resources/`, `scripts/` | Bundle metadata/resources and build/launch helpers |
| `tickets/` | Implementation task notes |

## Debug launch arguments

Debug builds accept these arguments. Quit any running Capture instance before using `open`,
so arguments reach a new process.

```sh
scripts/build-app.sh debug
open build/Capture.app --args -debugOpenSettings YES
```

| Argument | Behavior |
| --- | --- |
| `-debugOpenSettings YES` | Open Settings at launch |
| `-debugSelectionOverlay YES` | Start interactive selection |
| `-debugCaptureRect "100,100,400,300"` | Capture a rectangle on the main display in global CG points |
| `-debugAction ocr` / `translate` / `chat` | Run an action after debug capture |
| `-debugChatMessage "Describe this selection"` | Send a message with the chat action |
| `-debugFakeTranslation YES` | Use fake in-place translations for layout work |
| `-debugSnapshotDir "/tmp/capture-debug"` | Write window snapshots, metadata, result/chat text |
| `-debugQuitAfter 10` | Quit after the given number of seconds |

Snapshot output may contain screen content, document text, translations, chat, and window
titles. Use synthetic content and keep output outside the repository. Review every artifact
before sharing it. These debug flags are compiled out of release builds.

## Validation

Run `swift build` and `scripts/build-app.sh release` to check both configurations, bundle
assembly, and local signature. Run `swift test` for missing-key regression tests, which use
injected key reads and reject network requests. GitHub Actions runs these checks without
a key or GUI permissions. Manual UI, permission, multi-monitor, and
provider checks remain necessary for changes affecting those features.
