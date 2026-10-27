# T1 — Scaffold, menu bar app, global hotkey, app bundle script

Read SPEC.md and AGENTS.md first. Implement ONLY this ticket.

Deliver:
1. `Package.swift` (swift-tools-version 5.10, macOS 14, executable target `Capture`,
   `swiftLanguageModes: [.v5]` or the 5.10 equivalent, link AppKit, Carbon, ScreenCaptureKit, Vision,
   ServiceManagement as needed).
2. `Resources/Info.plist`: bundle id `com.sozay.capture`, name "Capture", `LSUIElement` true,
   `LSMinimumSystemVersion` 14.0, version 0.1.0, `NSHumanReadableCopyright`.
3. `Sources/Capture/main.swift` + `AppDelegate.swift`: accessory activation policy, `NSStatusItem`
   with SF Symbol `viewfinder` and a menu: "Capture Area" (shows the current hotkey as key
   equivalent text), "Settings…" (for now opens a placeholder window), separator, "Quit Capture".
4. `Hotkey/HotkeyManager.swift`: Carbon `RegisterEventHotKey` wrapper. A `Hotkey` value type
   (keyCode: UInt32, modifiers: carbon flags) that is Codable, has a display string like "⌘⇧6",
   default ⌘⇧6 (kVK_ANSI_6). `register(_:handler:)`, `unregister()`, re-registering replaces the old one.
   Log (os.Logger, subsystem com.sozay.capture) if registration fails.
5. `Settings/AppSettings.swift`: `@MainActor final class AppSettings: ObservableObject` singleton
   with UserDefaults-backed properties from SPEC "Settings window" (hotkey, visionModel,
   chatModel, disableReasoning, targetLanguage, ocrEngine enum, autoCopy, maxImageSide,
   askBeforeActing). Include the language list from SPEC as a static array.
6. `Settings/Keychain.swift`: tiny generic-password helper (service "com.sozay.capture",
   account "openrouter-api-key"): read / save / delete.
7. `CaptureCoordinator.swift`: `@MainActor final class CaptureCoordinator` with `startCapture()`
   which for now just logs "capture requested". Hotkey and menu item both call it.
8. `scripts/build-app.sh` and `scripts/run.sh` exactly as described in SPEC "Platform and build"
   (bash, `set -euo pipefail`, work from any cwd). The signing step must not fail the build when no
   identity exists (fall back to ad-hoc).

Done when: `swift build` succeeds and `scripts/build-app.sh` produces a signed `build/Capture.app`.
