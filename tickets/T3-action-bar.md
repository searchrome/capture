# T3 — Floating action bar and selection highlight

Read SPEC.md ("Action bar", "Coordinate systems") and AGENTS.md first. T1–T2 are done: a capture
produces `CaptureCoordinator.current: CaptureResult`. Implement ONLY this ticket.

Deliver:
1. `UI/FloatingPanel.swift`: reusable `NSPanel` subclass — borderless or titled per init flag,
   `.nonactivatingPanel`, `isFloatingPanel = true`, level `.floating`, `hidesOnDeactivate = false`,
   `collectionBehavior` [.canJoinAllSpaces, .fullScreenAuxiliary], hosting a SwiftUI view.
   Helper to convert a global-CG rect to an AppKit frame (SPEC formula) and to clamp a frame to the
   visible frame of the screen containing the selection.
2. `UI/SelectionHighlight.swift`: click-through window (`ignoresMouseEvents = true`, transparent)
   drawing a 2 pt accent-color rounded border just outside the selection rect.
3. `UI/ActionBar.swift`: SwiftUI bar inside a FloatingPanel (rounded, `.regularMaterial`, ~36 pt high)
   with icon buttons + `.help` tooltips: Image→Text (`text.viewfinder`), Translate (`translate`),
   language `Menu` showing a short code for `AppSettings.targetLanguage` (e.g. "EN", "TR"; picking
   one updates the setting), AI Chat (`bubble.left.and.text.bubble.right`), Settings (`gearshape`),
   Close (`xmark`). Placement rules from SPEC (below the selection right-aligned → above → inside
   bottom-right; always on-screen).
4. `UI/CaptureSessionUI.swift` (or inside CaptureCoordinator): owns highlight + bar for the current
   capture; `show(for:)`, `dismiss()`. Esc dismisses (local key monitor while our app is active is
   fine). A new capture dismisses the previous one first. Before the freeze-frame capture, hide our
   existing panels so they are not in the screenshot.
   Action callbacks for now: Image→Text / Translate / Chat call
   `CaptureCoordinator.extractText()`, `.translate()`, `.openChat()` stubs that log; Settings calls the
   existing settings-window opener.
5. Remove the temporary "copy PNG to clipboard" behaviour from T2.

Done when: `swift build` succeeds and the bar + highlight appear correctly positioned next to a
selection on any screen.
