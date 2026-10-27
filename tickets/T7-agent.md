# T7 — Agent actions for form filling (click / type / keys / scroll)

Read SPEC.md ("Agent actions", "Coordinate systems") and AGENTS.md first. T1–T6 are done
(`ChatSession` streams replies, `ScreenCapturer.capture(rect:displayID:)` recaptures, settings
has `askBeforeActing`). Implement ONLY this ticket.

Deliver:
1. `Agent/AgentTools.swift`: tool definitions exactly as in SPEC (`click`, `type_text`, `press_key`,
   `scroll`, `take_screenshot`) with JSON-schema parameters and clear descriptions. State that x,y
   are integer pixel coordinates in the most recent screenshot, whose size is given in the
   accompanying text. Parse/validate arguments into an `AgentAction` enum; invalid args → a tool
   result describing the error so the model can retry.
2. `Agent/InputSynthesizer.swift`: `CGEvent`-based actions on the main actor:
   - click: move → down → up (count 2 sets `mouseEventClickState` = 2), left or right button.
   - type_text: `CGEvent(keyboardEventSource:virtualKey:0,keyDown:)` +
     `keyboardSetUnicodeString` in chunks of ≤ 20 UTF-16 units, small delay between chunks.
   - press_key: virtual key map for the SPEC key list, modifier flags.
   - scroll: `CGEvent(scrollWheelEvent2Source:units: .line, ...)` at the point.
   - Accessibility: `AXIsProcessTrustedWithOptions` with the prompt option; if not trusted, return
     an error result and show a chat notice with an "Open Accessibility Settings" button
     (`x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`).
   - Before a click/scroll, if any of our windows contains the target point, `orderOut` them for the
     action and restore them after.
3. `Agent/TargetMarker.swift`: click-through overlay showing a red ring (≈ 28 pt) with a centre dot
   at a global CG point; used for confirmation previews and briefly (0.4 s) when an action runs.
4. Agent loop in `ChatSession`: include the tools in every chat request; when the stream finishes
   with tool calls, append the assistant message (with `tool_calls`), then for each call:
   map image pixels → screen point with `CaptureResult` (using the size of the latest screenshot
   actually sent), and if `askBeforeActing` and not "allow all" for this user turn, show an action
   card in the chat ("Click at (x, y) on <app>", "Type “…”", "Press ⌘↩", "Scroll down 3") with the
   marker visible, and Allow / Allow all / Deny buttons; run or deny; append a `tool` message with the
   result. Then wait 500 ms, recapture the region, append it as a user image message
   ("Updated screenshot after your actions. Size W×H px.") unless the last action was
   `take_screenshot` (which already did), and continue the loop. Max 25 tool steps per user message,
   then stop with a notice. Stop button cancels at any point (also dismisses marker / pending card).
   Extend the system prompt: the assistant can operate on the selected area via the tools to help
   fill forms; it must only act inside the selection, explain briefly what it will do, ask the user
   for any personal data it does not know instead of guessing, and never submit/send a form or
   enter passwords or payment details unless the user explicitly asked in this chat.
5. Show tool activity compactly in the message list (a small grey row per executed action).

Done when: `swift build` succeeds; with Accessibility granted, asking "fill this form with name
Ada Lovelace and email ada@example.com" on a captured web form clicks the right fields and types,
with confirmation cards when "Ask before acting" is on.

## Review fixes from T6 (do these too)
- Esc handling in `CaptureSessionUI`: when the chat panel or result panel is the key window, Esc
  must not dismiss the whole capture session. In the chat panel Esc stops the running response /
  agent task (and denies a pending action card); otherwise it does nothing. Esc still dismisses
  the session when the action bar is the only thing open or none of our panels is key.
- The result panel and chat panel both use `frameBeside` and can open on top of each other; when
  both are open, place the second one so it does not overlap the first (or the selection).

## Build note
Run only `swift build` to check your work. Do NOT run `scripts/build-app.sh` or `codesign`.
