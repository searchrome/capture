# T5 — Image → Text and Translate

Read SPEC.md ("Image → Text and Translate") and AGENTS.md first. T1–T4 are done: capture,
action bar with `extractText()` / `translate()` stubs, `OpenRouterClient.stream`, `AppSettings`.
Implement ONLY this ticket.

Deliver:
1. `Features/TextExtractor.swift`: `extract(from: CaptureResult) -> AsyncThrowingStream<String, Error>`
   (text deltas). LLM engine uses the OCR system prompt from SPEC, `settings.visionModel`,
   temperature 0, `settings.disableReasoning`, image from `CaptureResult.llmImage(maxSide:)`.
   On-device engine uses `VNRecognizeTextRequest` (accurate, language correction, automatic language
   detection, `revision` latest), joins observations top-to-bottom / left-to-right into lines, and
   yields the whole result once.
2. `Features/Translator.swift`: same shape, LLM only, translate system prompt from SPEC with the
   English name of `settings.targetLanguage`.
3. `UI/ResultPanel.swift`: FloatingPanel (titled, closable, resizable, ~420×300 default, min 280×160)
   placed beside the selection without covering it (right → left → below → above; clamp on-screen).
   Header: mode ("Text" / "Translation → Turkish") + model id (or "On-device"). Body: editable
   `TextEditor` that fills as deltas stream, a small progress indicator while streaming. Footer:
   Copy, "Chat about this" (calls `CaptureCoordinator.openChat(seed: resultText)`), Close.
   When the stream ends and `settings.autoCopy` is on, copy to the clipboard and show "Copied ✓" for
   ~1.5 s. Errors show inline in red; missing API key shows an "Open Settings" button.
   Re-running translate with a different language from the action bar reuses the same panel.
   Closing the panel cancels its streaming task.
4. Wire `CaptureCoordinator.extractText()` and `.translate()` to open/refresh the panel. The action
   bar stays open while the panel is open; dismissing the capture (Esc / Close on the bar / a new
   capture) also closes the panel. Change `openChat()` to `openChat(seed: String? = nil)` (still a stub).

Done when: `swift build` succeeds; with a valid key both actions stream text into the panel; the
on-device engine works without any key.

## Review fixes from T4 (do these too)
- `ModelCatalog`: skip models with a negative prompt or completion price (router pseudo-models
  such as `openrouter/auto` report -1).
- `SettingsView`: save the API key to the Keychain on submit / when the window closes / after a
  short debounce, not on every keystroke.

## Debug hooks (DEBUG builds only, `#if DEBUG`)
- Launch argument `-debugOpenSettings YES` opens the Settings window at launch.
- Launch argument `-debugCaptureRect "x,y,w,h"` (global CG points on the main display) skips the
  overlay at launch: it freeze-captures the displays, crops that rect, and shows the action bar as
  if the user had selected it. `-debugAction ocr|translate|chat` additionally triggers that action.
  Read them with `UserDefaults.standard` (launch arguments land in the argument domain).

## Build note
Run only `swift build` to check your work. Do NOT run `scripts/build-app.sh` or `codesign`
(signing may wait on a keychain prompt).
