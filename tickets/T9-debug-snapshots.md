# T9 — DEBUG-only snapshots for automated verification

Read AGENTS.md first. Everything in this ticket is inside `#if DEBUG`. No behaviour change in
release builds.

1. Launch argument `-debugSnapshotDir <path>`: when set, the app writes verification output there.
2. `DebugSnapshots.write(name:)` renders every visible window of this app (action bar, highlight,
   result panel, chat panel, settings) into PNGs using the window's own content view
   (`bitmapImageRepForCachingDisplay` + `cacheDisplay`; no screen-recording API), named
   `<name>-<window title or kind>.png`, plus `<name>-windows.json` with each window's kind, title
   and frame in global CG coordinates.
3. Call it: 1 s after the action bar appears (`bar`), when a result stream finishes or fails
   (`result`; also write the final text or error to `result.txt`), when a chat assistant turn
   finishes or fails (`chat`; also append the transcript to `chat.txt`), and 1 s after Settings opens
   (`settings`).
4. `-debugQuitAfter <seconds>`: terminate the app that many seconds after launch.

Run only `swift build` to check your work. Do NOT run `scripts/build-app.sh` or `codesign`.
