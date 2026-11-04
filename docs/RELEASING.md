# Publishing and release checklist

## Before making the repository public

- Confirm [LICENSE](../LICENSE) and attribution cover the published code.
- Review full Git history and attachments for keys, personal data, screenshots, and transcripts.
  `.gitignore` does not remove committed files. Revoke exposed credentials before publication.
- Enable private vulnerability reporting in the GitHub repository security settings.
- Confirm issues and pull requests are enabled and templates render correctly.
- Let CI pass on the intended default branch. CI checks builds, not UI or live AI behavior.
- Check the README against shipped behavior. Add screenshots using synthetic content if desired.

## Before a binary release

1. Confirm `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`.
   Write release notes with changes, supported macOS versions, and known limitations.
2. Run `swift build` and `scripts/build-app.sh release` from the intended commit.
3. Smoke-test first-run permissions, both shortcuts, local OCR, document reading, translation,
   chat, action approval/denial, Stop, and multi-display placement using sample content.
4. Build and verify each advertised architecture separately; the script targets the host and
   does not produce a universal app.
5. Arrange Developer ID signing and Apple notarization for binary distribution, including
   hardened runtime and required entitlements, using Apple's distribution tooling. The current
   script provides local signing only and does not implement this distribution pipeline.
   Verify the final artifact on a clean machine before uploading it.
6. Include the MIT license with binary distributions, publish checksums, and attach verified
   artifacts to the matching release tag.

Source publication and notarized binary distribution are separate steps. This repository
does not automatically publish releases or upload artifacts.
