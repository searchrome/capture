# T11 — In-place translation overlay (Google Lens / Live Text style)

Read SPEC.md and AGENTS.md first. T1–T10 are done. Today Translate opens a result panel next to
the selection. Add a mode that shows the translation **on top of the selection, in the same
place as the original text**. Implement ONLY this ticket.

## Settings
- `AppSettings.translationDisplay`: `.overlay` (default) or `.panel`, with a picker in Settings →
  "Text and translation" ("Show translation: Over the selection / In a panel").
- The action bar's Translate button uses this setting.

## Pipeline (`Features/InPlaceTranslator.swift`)
1. **Layout from Apple Vision (on-device)** — run `VNRecognizeTextRequest` (accurate, language
   correction, automatic language detection) on `CaptureResult.image`. Convert each observation's
   normalized, bottom-left `boundingBox` to a top-left rect in **points** inside the selection.
2. **Group lines into blocks** (paragraphs): lines whose left edges are within ~1 line height,
   whose heights are similar (±35%) and whose vertical gap is < ~0.8 line height belong to the same
   block; everything else is its own block (table cells, buttons, labels stay separate). Block rect =
   union of its line rects; keep the median line height.
3. **Translate blocks** with `OpenRouterClient.stream`, text only (no image), `settings.visionModel`,
   temperature 0, `disableReasoning` rule as elsewhere. System prompt: translate each numbered
   block into {target language}; keep meaning across blocks; keep numbers, names, codes, URLs;
   output exactly one section per block in the same order, each starting on its own line with the
   marker `⟦n⟧` followed by the translation; no other text. User message lists the blocks as
   `⟦n⟧ original text` (line breaks inside a block joined with spaces).
   Parse the stream progressively: as soon as block n's text is complete (the next marker arrived
   or the stream ended), publish it so it renders immediately.
4. If Vision finds no text, fall back to the existing panel translation (image-based) and say so.

## Rendering (`UI/TranslationOverlay.swift`)
- A borderless panel exactly covering the selection (global CG rect → AppKit frame), level just
  above the highlight, joins all Spaces, not activating. Its view draws the frozen
  `CaptureResult.image` scaled to the selection, then for each block that has a translation:
  - **Background patch**: sample the image's pixels on a ring 2–3 px outside the block rect, take
    the median color, fill the block rect (outset 2 pt, corner radius 2) with it.
  - **Text color**: among pixels inside the block rect, pick the colour furthest from the
    background (by luminance); if contrast with the background is too low, use black or white,
    whichever contrasts more.
  - **Text**: system font, starting size ≈ 0.78 × the block's median line height (points), word
    wrap inside the block rect, left-aligned (centered if the original lines were centered);
    shrink the font in 0.5 pt steps until it fits (min 7 pt); if it still does not fit, let the
    block grow downward up to 40% then truncate with "…".
  - Blocks still waiting show a subtle animated shimmer over the original text.
- **Interaction**: holding the mouse down on the overlay (or holding ⌥) shows the original image;
  release shows the translation again. Cursor is the arrow. A right-click menu offers Copy
  translation, Copy original, Open as text (opens the existing result panel with the full
  translation), Close.
- A compact pill under the overlay (reuse the action-bar placement rules; the action bar stays)
  shows status: "Translating… 3/7", then "Turkish → English · hold to see original" with buttons
  Copy, Open as text, Close. When finished and `autoCopy` is on, copy the full translation (blocks
  joined by blank lines).
- Errors (missing key, HTTP) appear in the pill with an "Open Settings" button when the key is
  missing; the original stays visible.
- The overlay and pill belong to the capture session: Esc, Close on the bar, a new capture, or
  re-running Translate (e.g. after choosing another language in the bar) replaces/dismisses them.
- Our own overlay windows must stay excluded from recaptures (they are, via the app exclusion
  in `ScreenCapturer`) and must not be hidden behind the highlight.

## DEBUG hooks
- `-debugFakeTranslation YES`: skip the network and "translate" each block by returning its
  text wrapped as `[EN] …` reversed word order, streamed block by block with a 150 ms delay, so
  layout can be tested without an API key.
- With `-debugSnapshotDir`, write `overlay` snapshots (the overlay window and pill) when all
  blocks are done, and the block list (original, translation, rect, colors) to `overlay.json`.
- `-debugAction translate` follows `translationDisplay`.

Run only `swift build` to check your work. Do NOT run `scripts/build-app.sh` or `codesign`.
