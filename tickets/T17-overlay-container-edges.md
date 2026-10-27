# T17 — In-place overlay: don't expand past the line's background container

Read AGENTS.md first. T16 is done. Fix ONLY this, in `UI/TranslationOverlay.swift`.

A translated line may expand to the right into free space (T13). Today that free space only stops
at other text lines or the selection edge, so in a test the translated label of a blue button
grew past the button's right edge and its blue patch stuck out over the page background.

1. When computing a line's available width, also scan to the right of the original line rect, one
   image-pixel column at a time across the line's vertical band (inset 15% top and bottom), and
   stop at the first column whose median colour differs from the line's sampled background colour
   by more than a small threshold (e.g. Euclidean RGB distance > 0.12), or at the existing
   obstacle/selection limits — whichever comes first. Subtract a 4 pt margin from that edge.
   Never return less than the original line width. Use `ImagePixels` for the scan (add a helper).
2. Centred lines (`block.centered`) and single-line blocks whose background differs from the
   surrounding page (a button or chip) should expand symmetrically: apply the same scan to the
   left, and centre the text between the two edges.
3. Everything else (85% shrink, truncation, vertical centring, colours, draw order) stays as is.

Run only `swift build` to check your work. Do NOT run `scripts/build-app.sh` or `codesign`.
