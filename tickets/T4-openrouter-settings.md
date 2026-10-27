# T4 — OpenRouter client and Settings window

Read SPEC.md ("Settings window", "Image → Text and Translate" request details) and AGENTS.md
first. T1–T3 are done. Implement ONLY this ticket.

Deliver:
1. `LLM/ChatTypes.swift`: Codable types for OpenAI-compatible chat completions — messages with
   role system/user/assistant/tool, content as a string or an array of parts (`text`,
   `image_url` with a data URL), assistant `tool_calls`, tool messages with `tool_call_id`,
   tool definitions (`type: "function"`, name, description, JSON-schema parameters as a
   `[String: JSONValue]`), a small `JSONValue` enum.
2. `LLM/OpenRouterClient.swift`:
   - base `https://openrouter.ai/api/v1`; headers `Authorization: Bearer <key from Keychain>`,
     `X-Title: Capture`.
   - `func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamEvent, Error>` that parses SSE
     (`data: {...}` lines, ignore `: OPENROUTER PROCESSING` comments, stop on `[DONE]`), yielding text
     deltas, accumulated tool-call deltas (index/id/name/arguments fragments), finish reason and usage.
   - Error type with readable messages: missing API key, HTTP status + OpenRouter `error.message`,
     network failure, mid-stream `error` objects.
   - Retry rule from SPEC: if the request has `reasoning` and the server answers HTTP 400, retry once
     without it.
   - `func testKey() async throws -> String` (GET `/key`, return a short "OK — label / usage" string).
3. `LLM/ModelCatalog.swift`: GET `/models` (no auth needed), keep models whose
   `architecture.input_modalities` contains "image", expose id, name, prompt/completion price per 1M
   tokens, context length; sort by prompt+completion price; cache in memory for the app run.
4. `Settings/SettingsView.swift` + a `SettingsWindowController` (regular titled window, ~520×640,
   activates the app when shown, single instance) replacing the T1 placeholder. Sections exactly as
   in SPEC "Settings window": API key + Test, Vision model, Chat model (searchable picker over the
   catalog, shows price, plus free-text model id field; "Refresh" button), Disable reasoning,
   Target language, Image→Text engine, Auto-copy, Max image side (stepper 768…4096), Hotkey (show
   current; a "Record" button that captures the next key combo with ≥1 modifier via a local
   NSEvent monitor, then re-registers the hotkey; "Reset to ⌘⇧6"), note about the Touch Bar
   shortcut, Agent "Ask before acting", permission status rows (Screen Recording via
   `CGPreflightScreenCaptureAccess`, Accessibility via `AXIsProcessTrusted`) with "Open System
   Settings" buttons, Launch at login toggle (`SMAppService.mainApp`, show errors).

Done when: `swift build` succeeds; settings persist across launches; the API key is only in the
Keychain.

## Review fixes from T3 (do these too)
- `ActionBar.size` width is too small for its contents (5×32 pt buttons + 70 pt menu + spacing +
  padding ≈ 268 pt). Compute or set the width so nothing is compressed (e.g. 284 pt).
