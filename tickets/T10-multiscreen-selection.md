# T10 — Selection must work on every screen

Read AGENTS.md first. Bug: with several displays, the area selection only works on the screen
that had focus when the hotkey was pressed. On the other screens the first click is swallowed
(it only makes that overlay window key), so dragging does nothing, and the crosshair cursor only
shows on the key overlay. Fix ONLY this, in `Capture/SelectionOverlay.swift`:

1. `SelectionOverlayView`: override `acceptsFirstMouse(for:)` to return `true`, so the first
   mouse-down on any overlay starts the drag immediately.
2. Crosshair everywhere: replace the cursor-rect approach with an `NSTrackingArea`
   (`.activeAlways, .inVisibleRect, .cursorUpdate, .mouseEnteredAndExited, .mouseMoved`) and set
   `NSCursor.crosshair` in `cursorUpdate`, `mouseEntered` and `mouseMoved`. Also set it once when
   the overlays open.
3. When the mouse enters an overlay (or on mouse-down), make that overlay window key and first
   responder, so Esc cancels from whichever screen the user is on.
4. Create each overlay with `NSWindow(contentRect:styleMask:backing:defer:screen:)` passing its
   `NSScreen`, then `setFrame(screen.frame, display: false)` as now.
5. Keep the existing rule that a selection is confined to the screen where the drag started
   (same as macOS ⌘⇧4). Selection math, freeze-frame and cropping must not change.

Run only `swift build` to check your work. Do NOT run `scripts/build-app.sh` or `codesign`.
