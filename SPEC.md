# Capture — product spec

A macOS menu bar app. Press **⌘⇧6**, drag to select an area of the screen (like ⌘⇧4),
and a small floating action bar appears next to the selection with:

1. **Image → Text** — extract the text in the selection.
2. **Translate** — translate the text in the selection into the target language.
3. **Target language** — dropdown that picks the translation target (persisted).
4. **AI Chat** — chat with an AI agent about the selection. The agent knows where the
   selection is on screen, so it can later help with tasks like "help me fill this form"
   by clicking and typing into the area (with the user's approval).
5. **Settings** — opens the Settings window.
6. **Close** — dismisses the bar.

All LLM calls go through **OpenRouter** (`https://openrouter.ai/api/v1`, OpenAI-compatible
chat completions, streaming SSE).

## Platform and build

- macOS 14+ (Sonoma), Apple Silicon and Intel. Swift Package (no Xcode project), SwiftUI + AppKit.
- `Package.swift`: one executable target `Capture`, `swiftLanguageModes: [.v5]`, no third-party deps.
- `scripts/build-app.sh [debug|release]` builds with SwiftPM and assembles `build/Capture.app`:
  - copies the binary into `Contents/MacOS/Capture`, writes `Contents/Info.plist` from
    `Resources/Info.plist`, copies any resources.
  - code-signs with `$CODESIGN_IDENTITY` if set, else the first "Apple Development" identity from
    `security find-identity -v -p codesigning`, else ad-hoc (`-`). A stable identity matters:
    macOS ties the Screen Recording / Accessibility grants to the signature.
- `scripts/run.sh` = build debug + `open build/Capture.app` (kills a running instance first).
- Bundle id `com.sozay.capture`, `LSUIElement = true` (menu bar only, no Dock icon).

## Architecture (Sources/Capture/)

| Area | Files (suggested) | Notes |
|---|---|---|
| App | `main.swift`, `AppDelegate.swift` | `NSApplication` with `.accessory` policy, status item menu: "Capture Area ⌘⇧6", "Settings…", "Quit". |
| Hotkey | `Hotkey/HotkeyManager.swift` | Carbon `RegisterEventHotKey` (no Accessibility permission needed). Default ⌘⇧6, configurable. |
| Settings | `Settings/AppSettings.swift`, `Settings/Keychain.swift`, `Settings/SettingsView.swift` | `ObservableObject` backed by `UserDefaults`; API key only in Keychain. |
| Capture | `Capture/ScreenCapturer.swift`, `Capture/SelectionOverlay.swift`, `Capture/CaptureResult.swift` | ScreenCaptureKit freeze-frame + overlay selection. |
| Action bar | `UI/ActionBar.swift`, `UI/SelectionHighlight.swift` | Non-activating floating `NSPanel`s. |
| LLM | `LLM/OpenRouterClient.swift`, `LLM/ChatTypes.swift`, `LLM/ModelCatalog.swift` | URLSession async streaming. |
| Features | `Features/TextExtractor.swift`, `Features/Translator.swift`, `UI/ResultPanel.swift` | |
| Chat/agent | `Chat/ChatSession.swift`, `Chat/ChatPanel.swift`, `Agent/AgentTools.swift`, `Agent/InputSynthesizer.swift` | |

## Coordinate systems (important)

- **Global CG space**: origin top-left of the primary display, y grows down. Used by `CGEvent`,
  `SCDisplay.frame`, `CGDisplayBounds`. **All stored rects use this space.**
- **AppKit space**: origin bottom-left of the primary display, y grows up (`NSScreen.frame`,
  `NSWindow.frame`). Convert: `cgY = primaryHeight - nsY - height` where `primaryHeight` is
  `NSScreen.screens[0].frame.height`.
- `CaptureResult` = `{ image: CGImage (native pixels), rect: CGRect (global CG points),
  displayID: CGDirectDisplayID, scale: CGFloat (pixels per point) }`.
- Images sent to the LLM are downscaled so the longest side ≤ `maxImageSide` (default 2048 px);
  keep the factor so image pixel → screen point is
  `point = rect.origin + pixel * (rect.size / sentImageSize)`.

## Screen capture flow

1. Hotkey → check `CGPreflightScreenCaptureAccess()`; if false call `CGRequestScreenCaptureAccess()`
   and show an alert explaining how to enable it in System Settings → Privacy & Security →
   Screen & System Audio Recording, then stop.
2. Freeze frame: capture every display with ScreenCaptureKit (`SCShareableContent` +
   `SCScreenshotManager.captureImage`), excluding this app's own windows, at native resolution.
3. Show one borderless overlay window per screen (level `.screenSaver`, covers the full screen,
   joins all Spaces) displaying the frozen image, dimmed ~35%. Crosshair cursor.
4. Drag to select: the selected rect shows undimmed with a 1px white border and a small
   "W × H" label. Esc or right-click cancels. A selection smaller than 5×5 pt cancels.
   Selection is confined to the screen where the drag started.
5. On mouse-up: crop the frozen image of that display to the selection → `CaptureResult`,
   close overlays, show the action bar.

## Action bar

- Small rounded `NSPanel` (non-activating, floating, `.hudWindow` / vibrancy look, ~36pt tall)
  placed just below the selection, right-aligned to it; if no room below, above; if no room,
  inside the bottom-right of the selection. Always kept on-screen.
- Icon buttons (SF Symbols, with tooltips): `text.viewfinder` Image→Text,
  `translate` Translate, a compact language menu showing the target code (e.g. "EN ▾"),
  `bubble.left.and.text.bubble.right` AI Chat, `gearshape` Settings, `xmark` Close.
- A click-through highlight window draws a thin accent-colored border around the selection
  while the bar (or a result/chat panel tied to it) is open.
- Esc closes the bar and highlight. Pressing ⌘⇧6 again starts a new capture and replaces them.

## Image → Text and Translate

- Engine setting for Image→Text: **LLM (OpenRouter)** (default) or **On-device (Apple Vision)**
  (`VNRecognizeTextRequest`, accurate level, language correction on, automatic language detection).
  Translate always uses the LLM.
- LLM prompts (system):
  - OCR: "You are an OCR engine. Transcribe all text in the image exactly as written, preserving
    line breaks and reading order. Output only the text, no commentary. If there is no text,
    output nothing."
  - Translate: "Read all text in the image and translate it into {language}. Preserve the layout
    (line breaks, lists). Output only the translation, no commentary. If the text is already in
    {language}, output it unchanged."
- Request: `model = settings.visionModel`, `stream = true`, `temperature = 0`, the image as a
  `data:image/png;base64,...` content part. If `settings.disableReasoning` (default true) add
  `"reasoning": {"enabled": false}`; if the server returns HTTP 400, retry once without it.
- Result panel: floating panel next to the selection with streaming text (selectable, editable),
  header showing the mode + model, buttons Copy, "Chat about this", Close. When finished, if
  `autoCopy` (default true) copy to the clipboard and show "Copied" briefly.
- Errors (no API key, HTTP errors, network) show inline in the panel with a "Open Settings" button
  when the key is missing.

## AI Chat

- Chat panel: floating, resizable `NSPanel` (~380×520) placed beside the selection (right side,
  else left, else wherever it does not overlap the selection), never covering the selection.
- First request includes a system prompt + the selection image + context: selection rect
  (global points), screen size, sent image size, the frontmost app name under the selection.
- Message list (markdown rendering via `AttributedString(markdown:)`), streaming assistant replies,
  multiline input (Return sends, Shift+Return newline), Stop button while streaming,
  "New capture" button to re-capture the same rect into the conversation.
- Model: `settings.chatModel`.

## Agent actions (form filling)

- Tools exposed to the chat model (OpenAI function-calling format):
  - `click(x, y, button="left"|"right", count=1|2)` — x,y in pixels of the **latest screenshot**.
  - `type_text(text)` — types Unicode text into the focused field.
  - `press_key(key, modifiers=[])` — key ∈ return, tab, escape, delete, space, up, down, left,
    right, home, end, pageup, pagedown; modifiers ∈ cmd, shift, option, control.
  - `scroll(x, y, dy)` — dy in lines, negative = up.
  - `take_screenshot()` — recapture the same screen region.
- Input is synthesized with `CGEvent` (requires Accessibility: `AXIsProcessTrustedWithOptions`;
  prompt the user and explain if not granted).
- **Ask before acting** (setting, default ON): before each action show an action card in the chat
  ("Click at …", "Type '…'") plus an on-screen red ring marker at the target point; buttons
  Allow / Allow all (this task) / Deny. Deny → tool result "User denied this action."
- After the actions of an assistant turn run, wait 500 ms, recapture the region, and attach it as
  a new image in the conversation ("Updated screenshot after your actions"). Keep only the 2 most
  recent screenshots in the request history (older ones replaced by "[earlier screenshot omitted]").
- Max 25 tool steps per user message. Stop button aborts immediately. While clicking, our own
  panels must not be under the target point (temporarily hide any of ours that are).

## Settings window

SwiftUI `Form`, opened from the menu bar or the action bar:

- OpenRouter API key (SecureField, saved to Keychain), "Test" button (GET `/api/v1/key` or `/models`).
- Vision model (OCR/translate) and Chat model: pickers filled from `GET /api/v1/models`, filtered to
  models whose `architecture.input_modalities` contains "image", sorted by price, labelled with
  `$in / $out per 1M tokens`; plus a text field to type any model id. Defaults:
  `qwen/qwen3.7-flash` for both (cheapest strong vision model; alternatives:
  `google/gemini-3.1-flash-lite`, `openai/gpt-6-luna`, `anthropic/claude-haiku-5.5`).
- Disable reasoning for OCR/translate (default on).
- Target language (default English; list: English, Turkish, German, French, Spanish, Italian,
  Portuguese, Dutch, Russian, Ukrainian, Polish, Greek, Arabic, Persian, Hebrew, Hindi,
  Chinese (Simplified), Chinese (Traditional), Japanese, Korean, Indonesian, Vietnamese, Thai, Swedish).
- Image→Text engine (LLM / On-device), Auto-copy result, Max image side.
- Hotkey recorder (default ⌘⇧6) — note that macOS may reserve ⌘⇧6 for "Save picture of the
  Touch Bar" (System Settings → Keyboard → Keyboard Shortcuts → Screenshots).
- Agent: Ask before acting (default on). Permission status rows for Screen Recording and
  Accessibility with "Open System Settings" buttons.
- Launch at login (`SMAppService.mainApp`).

## Direct document text

- Menu bar command **Read Active Document Text**, global shortcut **⌘⌥7**. Existing area
  capture and its configurable shortcut (default ⌘⇧6) remain available.
- Requires Accessibility access, but no Screen Recording permission or API key.
- Targets the frontmost external app’s focused window. Reads a local PDF’s text layer with
  PDFKit when its file URL is exposed; otherwise reads document text exposed by Accessibility.
  This makes no network or AI request and does not take a screenshot.
- Accessibility text may include only the portion the source app exposes. Traversal runs off
  the main actor with time/depth/node limits, cancellation, and secure-field exclusion.
  Partial reads are explicitly labelled and are not automatically copied.
- Results are editable and support Copy and the existing auto-copy preference. If no text is
  available (including scanned PDFs), an inline explanation offers **Capture an area…**;
  the user can then choose the existing Image → Text action.
- Settings starts with separate configurable recorders for Capture area and Read document text.
  Both shortcuts persist; the recorder rejects duplicates. Registration failures are shown inline,
  and menu commands remain available if a shortcut cannot be registered.
- Files: `Features/DocumentTextReader.swift`, `Features/DocumentTextController.swift`;
  the result panel also accepts placement coordinates without a screenshot.
