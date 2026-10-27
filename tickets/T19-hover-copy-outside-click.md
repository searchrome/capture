# T19 — Original-text hover/copy, dismiss on outside click

Read AGENTS.md first. Implement ONLY these.

1. **Hover shows the original** (`UI/TranslationOverlay.swift`): hovering a translated line (or a
   re-flowed block) shows a tooltip with that line's / block's original text. Use per-rect
   tooltips (`addToolTip(_:owner:userData:)` or tracking areas) refreshed as translations arrive.
   The overlay window must accept mouse-moved events while the app is inactive (tracking area with
   `.activeAlways`).
2. **Copy original**: the translation pill shows two buttons, "Copy translation" and
   "Copy original" (plus Open as text, Close). Show a brief "Copied ✓" on the clicked button.
3. **Dismiss on outside click** (`UI/CaptureSessionUI.swift`): while a capture session is shown,
   add a global monitor (`NSEvent.addGlobalMonitorForEvents`) for left/right/other mouse-down.
   A mouse-down outside all of this app's windows dismisses the session (bar, highlight, overlay,
   pill, result panel, chat panel). Clicks inside any of our windows (incl. Settings) never
   dismiss. Do NOT dismiss while the chat agent is executing an action or waiting on an
   Allow/Deny card (expose a flag from `ChatSession`; synthetic clicks from `InputSynthesizer` must
   be ignored). Remove the monitor on dismiss.

Run only `swift build` to check your work. Do NOT run `scripts/build-app.sh` or `codesign`.
