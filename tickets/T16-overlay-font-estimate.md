# T16 — In-place overlay: estimate font size with descenders in mind

Read AGENTS.md first. T15 is done. Fix ONLY this, in `Features/InPlaceTranslator.swift` and
`UI/TranslationOverlay.swift`.

Vision's line box height depends on the glyphs: "Telefon numarası" (no descenders) gets a shorter
box than "Ad Soyad" (has `y`), although both are 14 pt. So it is grouped separately and drawn
smaller.

1. Add `estimatedFontSize` to each recognized line (store it on the line next to text/rect):
   - Using system-font metrics measured once at 100 pt: `ascRatio = ascender / pointSize`,
     `fullRatio = (ascender - descender) / pointSize`.
   - If the line's text contains a descender character (any of `g j p q y ç ş ğ , ; ( ) [ ] { } |`
     or `Ç Ş Q J` – keep the set in one constant), size = height / fullRatio; otherwise
     size = height / ascRatio.
   - Clamp to 7…72 pt.
2. Use `estimatedFontSize` instead of the raw box height everywhere a "similar height" comparison
   is made: block grouping (0.8…1.25), the size clusters from T15 (±25%), the block median, and
   the font size used for drawing (drop the old `lineHeight / glyphHeightRatio` path for lines;
   re-flowed paragraphs use the block's median `estimatedFontSize`).
3. Keep the per-line 85% shrink rule, vertical centring and colours exactly as they are.

Run only `swift build` to check your work. Do NOT run `scripts/build-app.sh` or `codesign`.
