# T15 — In-place overlay: share font size among similar lines

Read AGENTS.md first. T14 is done. Fix ONLY this, in `UI/TranslationOverlay.swift` (and the
grouping threshold in `Features/InPlaceTranslator.swift`).

In a test, one block contained a 22 pt title plus three 14 pt labels. Because the block's line
heights are not all within ±25% of the block median, T14's "one size per block" rule did not apply
and the three labels were drawn at visibly different sizes (Vision box heights vary with
capitals/descenders).

1. Font size per line = computed from the **median height of the lines in the same block whose
   height is within ±25% of this line's height** (a size cluster). The title then keeps its own
   size and the labels share one size. Re-flowed paragraphs keep using the block median.
2. In `InPlaceTranslator.makeBlocks`, tighten the "similar height" grouping rule from
   0.65…1.35 to 0.8…1.25, so a large heading is less likely to be merged with the smaller lines
   below it.

Run only `swift build` to check your work. Do NOT run `scripts/build-app.sh` or `codesign`.
