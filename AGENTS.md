# Agent guide

- Read `SPEC.md` first. It is the source of truth for behaviour, coordinates and file layout.
- Work only on the ticket you are given. Do not start later tickets or rewrite unrelated files.
- Swift Package, SwiftUI + AppKit, macOS 14+, Swift 5 language mode, no third-party dependencies.
- UI code runs on the main actor (`@MainActor`); network work uses async/await.
- Keep files small and focused; follow the file layout in `SPEC.md`.
- Never hard-code API keys. The OpenRouter key lives only in the Keychain.
- Before finishing, run `swift build` and make sure it compiles with no errors. If the sandbox
  blocks the build, say so in your final message.
- Finish with a short summary: files changed, what works, anything left undone or unverified.
