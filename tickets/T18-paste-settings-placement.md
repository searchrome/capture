# T18 — Paste in text fields, Settings placement, overlay debug hook

Read AGENTS.md first. Implement ONLY these.

1. **Paste/copy don't work** (user cannot paste the API key into Settings; same for the chat
   input). The app is `LSUIElement` and has no main menu, so ⌘V/⌘C/⌘X/⌘A/⌘Z have no Edit-menu
   key equivalents. In `AppDelegate`, install an `NSApp.mainMenu` with an app menu (About/Quit)
   and a standard Edit menu: Undo (⌘Z), Redo (⇧⌘Z), Cut, Copy, Paste, Select All, using the
   standard selectors (`undo:`, `redo:`, `cut:`, `copy:`, `paste:`, `selectAll:`) with nil target.
   It must work in SecureField, TextField and TextEditor in Settings, chat and result panels.
2. **Settings must not cover the selection.** When Settings opens while a capture session is
   showing (from the action bar or the menu bar), place the Settings window where it does not
   overlap the selection rect (use `FloatingPanel.frameBeside`-style placement on the selection's
   screen, else another screen; avoid the action bar/panels too if possible). If it cannot fit
   without overlapping, hide the session's highlight, action bar and panels (`orderOut`) while
   Settings is open and restore them when Settings closes. With no capture session, keep centering.
3. **DEBUG hook** `-debugSelectionOverlay YES`: at launch run the real `startCapture()` path
   (freeze-frame + selection overlay windows on every screen) and, if `-debugQuitAfter` is set,
   just let the app quit with the overlay open. Log "selection overlay shown on N screens".

Run only `swift build` to check your work. Do NOT run `scripts/build-app.sh` or `codesign`.
