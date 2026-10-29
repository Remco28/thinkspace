# Plan: picking a drawing tool shows that tool's settings
*Kept by the review-loop skill (light review). Safe to delete this folder once the work is done.*

Version before: `a6a8103` (main). Branch: `tool-shows-settings`.

## The problem
The right-hand panel shows a tool's settings for the next thing drawn
(colour, width, ... and "Reset to default") only when nothing is selected.
Drawing leaves the new object selected and returns to Select, so picking a tool
again usually shows the selected object's panel instead, and "Reset to default"
is never seen. Reported by Frank on 2026-10-29.

## The decision (Frank, 2026-10-29)
Picking a drawing tool clears the selection, so the panel shows that tool's
settings. What was drawn stays on the page, just unselected.

## The change
In `EditorController.setTool`: when the tool picked is a drawing tool (anything
but Select and Cut out), clear the selection, as Remove marks already does.
- Select keeps the selection (pressing V or Esc-to-select must not lose it).
- Cut out keeps it: it cuts from the selected image (`_downCutout`, the
  "Cut out..." button in the image panel).
- A second tap that locks the tool (top bar) also clears; harmless.
- After drawing with a locked tool, the drawn object is still selected (unchanged).

Nothing stored in the document changes; selection is view state, and undo
already records it per edit.

## Checks
- `dart format lib test && flutter analyze && flutter test`.
- New widget test: select an object, pick a drawing tool, the panel shows the
  tool's settings with "Reset to default"; Cut out and Select keep the selection.
- Use it once in the headless app: draw, pick the tool again, see Reset.

## Stakes
One user (Frank), Linux desktop, daily use. A wrong result here is a selection
lost or kept unexpectedly: annoying, never data loss. Peer step skipped: the
change alters no stored or computed data (light review step 2). This decision
goes to the fix auditor for a second opinion.
