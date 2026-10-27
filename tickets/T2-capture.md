# T2 — Area selection overlay and screen capture

Read SPEC.md ("Coordinate systems", "Screen capture flow") and AGENTS.md first. T1 is done
(menu bar app, hotkey, `CaptureCoordinator.startCapture()` stub). Implement ONLY this ticket.

Deliver:
1. `Capture/CaptureResult.swift`: struct from SPEC (`image: CGImage`, `rect: CGRect` in global CG
   points, `displayID`, `scale`) plus a helper `func llmImage(maxSide:) -> (png: Data, size: CGSize)`
   that downscales (keeping aspect) only when the longest side exceeds `maxSide`, and a helper that
   maps a pixel point in that sent image back to a global CG screen point.
2. `Capture/ScreenCapturer.swift`:
   - permission helpers: `hasPermission` (`CGPreflightScreenCaptureAccess`) and `requestPermission()`
     (`CGRequestScreenCaptureAccess` + an `NSAlert` explaining System Settings → Privacy & Security →
     Screen & System Audio Recording, with a button that opens
     `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`).
   - `func captureAllDisplays() async throws -> [CGDirectDisplayID: (image: CGImage, frame: CGRect)]`
     using `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)`, one
     `SCContentFilter(display:excludingApplications: [this app], exceptingWindows: [])` per display,
     `SCStreamConfiguration` sized to the display's native pixels (points × backingScaleFactor of the
     matching NSScreen), `showsCursor = false`, then `SCScreenshotManager.captureImage`.
   - `func capture(rect: CGRect, displayID:) async throws -> CaptureResult` to re-capture a region
     later (used by the agent): use `sourceRect` in display-local points.
3. `Capture/SelectionOverlay.swift`: one borderless `NSWindow` subclass per screen
   (canBecomeKey true, level `.screenSaver`, `collectionBehavior` [.canJoinAllSpaces, .fullScreenAuxiliary],
   opaque, frame = screen.frame) with a custom `NSView` that draws the frozen image, a 35% black dim
   everywhere except the selection, a 1 pt white border around the selection and a small rounded
   "W × H" label (points) near the cursor. Crosshair cursor. Drag selects (confined to that screen);
   Esc or right-click cancels; selections < 5×5 pt cancel. Map NSScreen → displayID via
   `deviceDescription["NSScreenNumber"]`.
   Provide `SelectionOverlayController.run(frozen:) async -> (rect: CGRect /*global CG*/, displayID)?`.
4. Wire `CaptureCoordinator.startCapture()`: permission check → freeze frame → overlay → crop the
   frozen display image to the selection (pixel rect = (rect - displayFrame.origin) × scale) →
   `CaptureResult`. Ignore new hotkey presses while an overlay is already open. Activate the app
   (`NSApp.activate`) so the overlay gets key events. Keep the latest `CaptureResult` in
   `CaptureCoordinator.current` and, for now, log its rect and pixel size and put the PNG on the
   clipboard (temporary, so the capture can be checked by pasting into Preview).

Done when: `swift build` succeeds; selection math is correct for Retina and for a second display
placed left of / above the primary one (negative origins).
