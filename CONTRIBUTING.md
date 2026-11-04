# Contributing to Capture

Bug reports, focused fixes, documentation improvements, and feature proposals are welcome.
For larger changes, open an issue first to discuss the intended behavior.
Keep discussions respectful and give actionable feedback.

## Development

Use macOS 14+ with Xcode 15.3+ or a compatible Swift 5.10+ toolchain and macOS SDK.
Read [SPEC.md](SPEC.md) before changing behavior or coordinates. Follow [AGENTS.md](AGENTS.md)
when using a coding agent. Run `scripts/run.sh` to build and launch the app; see
[development notes](docs/DEVELOPMENT.md) for source layout and debugging.

Use SwiftUI and AppKit, Swift 5 language mode, and no third-party dependencies. Keep UI code
on the main actor and use async/await for network work. API keys belong only in Keychain;
never add them to source, fixtures, or environment files.

## Before opening a pull request

```sh
swift build
swift test
scripts/build-app.sh release
git diff --check
```

Automated tests cover missing API key handling without real keys or network requests.
Manually exercise affected paths and record the
results: capture/cancellation, display placement, local OCR, translation, chat cancellation,
action approvals, document reading, or permission-denied states as relevant. AI checks need
your own key. CI cannot validate UI, permissions, or live AI responses.

Keep each pull request focused. Explain the problem, resulting behavior, and validation.
Include screenshots for visual changes using non-sensitive sample content. Update documentation
and the spec when behavior changes. Mention anything you could not verify.

## Reporting bugs

Use the bug report template. Include steps, expected and actual behavior, macOS version,
architecture, and build/commit. Include display layout and scaling for placement issues,
or the model ID and sanitized error for AI issues.

Remove API keys, personal information, private documents, and chat transcripts before sharing
diagnostics. Report security issues through [SECURITY.md](SECURITY.md).
