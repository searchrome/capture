# T6 — AI Chat panel (no agent actions yet)

Read SPEC.md ("AI Chat") and AGENTS.md first. T1–T5 are done. Implement ONLY this ticket;
tool calling / input synthesis is T7, but design `ChatSession` so T7 can add tools to the loop.

Deliver:
1. `Chat/ChatSession.swift`: `@MainActor final class ChatSession: ObservableObject` holding the
   `CaptureResult`, the API message history, a UI message list (`id`, role, text, optional image
   thumbnail, `isStreaming`, error), `isBusy`, and a cancellable current task.
   - System prompt: you are an assistant built into a macOS screen-capture tool; the user selected
     an area of their screen (image attached); answer about its content; be concise; reply in the
     user's language. Include context: selection rect in global screen points, screen size,
     sent image size in pixels, and the name of the app that owns the window under the selection
     centre (`CGWindowListCopyWindowInfo`, skip our own pid) when available.
   - First user turn = the selection image + the user's text (or, if `seed` text was passed from a
     result panel, prefill the input box with nothing but add the seed as context: "Text extracted
     from the selection: …").
   - `send(_ text:)` streams the assistant reply via `OpenRouterClient.stream` with
     `settings.chatModel`; `stop()` cancels; `recapture()` re-captures the same rect via
     `ScreenCapturer.capture(rect:displayID:)` and appends it as a new user image message
     ("Here is an updated screenshot of the same area.").
   - Keep only the 2 most recent images in the request history (older image parts replaced by the
     text "[earlier screenshot omitted]"), per SPEC.
2. `Chat/ChatPanel.swift`: FloatingPanel (titled "Capture Chat", closable, resizable, ~380×520, min
   320×360) placed beside the selection without covering it (same placement helper as the result
   panel). SwiftUI: a thumbnail of the selection at the top (click toggles a larger preview), a
   scrolling message list (user bubbles right, assistant left, markdown via
   `AttributedString(markdown:, options: .inlineOnlyPreservingWhitespace)`, selectable text, copy
   button on assistant messages), auto-scroll to bottom while streaming, error rows with "Retry".
   Input: multiline `TextField(axis: .vertical)` (Return sends, Shift/Option+Return newline),
   Send / Stop button, a "Recapture" button (`camera.viewfinder`), and a "New chat" button.
   The panel must accept keyboard input: make it key and activate the app when it opens.
3. Wire `CaptureCoordinator.openChat(seed:)`: one chat panel per capture; reopening focuses it.
   Dismissing the capture closes it.

Done when: `swift build` succeeds; with a valid key you can ask "what is this?" about a selection
and get a streamed answer; multi-turn works; Stop works.

## Review fixes from T5 (do these too)
- `ResultPanel`: skip auto-copy (and the "Copied ✓" flash) when the finished text is empty or
  whitespace only.
- Make `-debugAction chat` open the real chat panel, and add `-debugChatMessage "..."` (DEBUG only)
  that sends that message automatically once the panel opens.

## Build note
Run only `swift build` to check your work. Do NOT run `scripts/build-app.sh` or `codesign`.
