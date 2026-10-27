# T12 — In-place translation: keep line placement + review fixes

Read AGENTS.md first. T11 is done (`Features/InPlaceTranslator.swift`, `UI/TranslationOverlay.swift`).
Implement ONLY the items below.

1. **Keep line structure.** Today all lines of a block are joined with spaces and the translation
   is re-flowed, so stacked labels ("Name / Email / Phone") or an invoice's separate lines turn
   into one sentence and lose their placement.
   - Keep each line's text and rect inside `TranslationBlock` (`lines: [(text, rect)]`).
   - Send each block to the model with its lines separated by `\n` (after the `⟦n⟧` marker).
     Prompt: if the lines of a block are separate items (headings, labels, list entries, table
     cells, address/invoice lines), return exactly the same number of lines in the same order;
     if they are one wrapped sentence or paragraph, return flowing text.
   - Rendering: if a block's translation has the same number of lines as the original, draw each
     translated line inside its own original line rect (same font-fit rules per line, shrinking only
     that line; background patch per line). Otherwise re-flow inside the block rect as now.
2. **Shimmer timer**: stop it as soon as every block is translated or an error occurs; do not
   redraw while idle.
3. **⌥ to peek** must keep working without the timer: poll `NSEvent.modifierFlags` every 0.1 s
   with a cheap timer that only calls `needsDisplay` when the ⌥ state changes (stop it on close).
4. **Partial results**: if the model omits some blocks, keep showing every block that was
   translated, leave the missing ones as the original, and show a warning in the pill
   ("2 of 9 blocks were not translated") instead of hiding everything behind an error. Only real
   failures (network, HTTP, missing key) are errors, and even then keep already-translated blocks.
5. `TranslationCanvas`: override `acceptsFirstMouse(for:)` → `true`, so press-and-hold works on the
   first click.
6. Pill status: when the detected source language equals the target, say
   "Already in {target}" instead of "X → X".
7. **Readability**: reformat `InPlaceTranslator.swift` and `TranslationOverlay.swift` to match the
   rest of the codebase — one statement per line, lines ≤ 120 columns, short helpers instead of long
   closures. No behaviour change beyond the items above.
8. `-debugFakeTranslation` must return one line per original line for multi-line blocks (so the
   per-line path can be tested), e.g. `[EN] <line reversed>` per line.

Run only `swift build` to check your work. Do NOT run `scripts/build-app.sh` or `codesign`.
