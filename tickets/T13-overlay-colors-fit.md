# T13 — In-place overlay: color sampling bug + text fitting

Read AGENTS.md first. T11–T12 are done. Fix ONLY these, in `UI/TranslationOverlay.swift`.

1. **Color sampling is vertically mirrored (bug).** `ImagePixels.init` applies
   `translateBy(0, height)` + `scaleBy(1, -1)` before drawing into the bitmap context. A
   `CGBitmapContext` already stores row 0 as the top of the image, so this flip makes `pixel(x, y)`
   read the mirrored row. Result seen in testing: a white-on-blue button got a white patch with
   black text, and paragraph lines got the wrong patch colors. Remove the flip so `pixel(x, y)` uses
   top-left image coordinates, matching the block rects.
2. **Short lines shrink too much.** When a translated line is longer than the original line, it is
   currently squeezed into the original line's width (e.g. "Ad Soyad" → a longer English label
   becomes tiny). Per line:
   - Available width = from the line's `minX` to the nearest obstacle on the right: the `minX` of any
     other line/block rect that vertically overlaps this line (minus 6 pt), or the selection's right
     edge minus 4 pt. Never less than the original line width.
   - Draw on a single line at the computed size; if it does not fit the available width, shrink
     down to 85% of the computed size; if it still does not fit, truncate with "…".
   - The background patch covers the union of the original line rect and the drawn text rect
     (outset 2 pt), using that line's sampled background color.
3. **Font size from real metrics.** Instead of `0.78 × lineHeight`, compute the size so the
   system font's glyph height matches the Vision line box:
   `size = lineHeight / ((font.ascender - font.descender) / font.pointSize)` (measure with a 100 pt
   font once), clamped to 7…72 pt. Use the same rule for re-flowed paragraphs (per median line
   height).
4. Re-flowed paragraph blocks keep today's behaviour otherwise.

Run only `swift build` to check your work. Do NOT run `scripts/build-app.sh` or `codesign`.
