# T14 — In-place overlay polish (sizes, vertical alignment, contrast)

Read AGENTS.md first. T11–T13 are done. Fix ONLY these, in `UI/TranslationOverlay.swift`.
Seen in a test on a Turkish form (title, three 14 pt labels, a two-line gray paragraph, a
white-on-blue button):

1. **Consistent size inside a block.** The three labels are all 14 pt in the original but came out
   at different sizes, because each line's font size comes from its own Vision box height (which
   varies with descenders/capitals). When a block's line heights are within ±25% of its median,
   compute ONE font size from the median line height and use it for every line of that block (the
   per-line 85% shrink rule from T13 still applies per line).
2. **Vertical alignment.** Draw each line's text vertically centred on its original line box
   (`rect.midY`), using the font's real line height (`ascender - descender + leading`) for the text
   rect, instead of top-aligning it at `rect.minY`.
3. **Draw order.** For every block, fill all background patches first, then draw all texts, so a
   later line's patch can never cover an earlier line's glyphs (the first paragraph line looked
   clipped because of this).
4. **Text colour contrast.** Keep the sampled text colour whenever its contrast ratio with the
   sampled background is ≥ 3.0 (today 4.5). White text on the blue button (ratio ≈ 4.4) was
   replaced by black. Only fall back to black/white below 3.0.

Run only `swift build` to check your work. Do NOT run `scripts/build-app.sh` or `codesign`.
