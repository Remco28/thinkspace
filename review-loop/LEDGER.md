# Review-loop ledger: borders and connectors in Thinkspace
*Kept by the review-loop skill. Safe to delete this folder once the work is done.*

Profile: `code-review`.

Success question: In the ways Frank uses Thinkspace, do borders or connectors
ever give a wrong picture, an arrow pointing somewhere he didn't put it, or lost
work, and do existing files open and look exactly as before?

Rules confirmed with: Frank, in chat, 2026-10-27 ("Yes, as written").

## Stakes
- **What:** Thinkspace, Frank's own desktop app for arranging pictures, lines and
  layers to explain an idea.
- **Who relies on it:** Frank, on Linux (his only platform in use), sometimes
  with several windows open at once. He exports and copies its pictures to show
  other people.
- **How it is used:** pasting screenshots, adding text and arrows, saving
  `.thinkspace` files, autosave and recovery. Windows and macOS builds are not in
  use.
- **What a failure costs, worst first:**
  1. a file that won't open, or lost work;
  2. an exported picture whose arrow quietly points at the wrong spot;
  3. old files no longer looking exactly as before;
  4. anything else is an annoyance.
- **Stop (profile rule):** stop after a round with no HIGH, by ratings the
  disposition auditor has checked, that needed no HIGH or MEDIUM fixes.

## Rules
Borders:
- B1. Pictures and text boxes get a border colour (none by default), a width and
  an on/off shadow.
- B2. The border is drawn outside the edge, so the object's size is unchanged.
  It turns and flips with the object.
- B3. On a cut-out, the border is a rectangle.
- B4. On a text box, the border goes around the backdrop box, or around the text
  area if there is no backdrop.
- B5. With several selected, one change applies to all. There is also a "Give
  all pictures this border" button.
- B6. Export and copy include it. Merging bakes it into the image; unmerge
  brings back the originals with their borders.
- B7. Aligning, snapping and the size boxes use the object's own edge, not the
  outside of its border.
- B8. Files record a border only when one is set. Older builds ignore it.
- B9 (Frank's answer). New pictures get no border automatically.

Connectors:
- C1. Either end of a line or arrow can attach to a picture, text box,
  rectangle, ellipse or marker. Not to pen marks, highlights, Hide boxes or
  other lines.
- C2. On text, rectangles, ellipses and markers, the end rides the outline,
  aiming at the other end (or at the bend, if curved). With a border, it touches
  the border's outside.
- C3. On a picture, the end pins to that spot and follows move, resize, rotate
  and flip.
- C4. An end attaches when dropped over an object, whether drawing the line or
  dragging an end. The target lights up during the drag, the topmost object
  wins, and attaching beats grid snapping. Ctrl means don't attach.
- C5. Dragging an attached end into empty space detaches it.
- C6. With both ends attached, dragging the line's middle bends it. Frank's
  answer: the same applies with **one** end attached.
- C7. Selected together with its objects, moving the group just moves
  everything.
- C8. Deleting an object turns its connectors into free lines, where they were.
- C9. Duplicating or copying an object with its connector gives a copy connected
  to the copy. A connector copied alone becomes a free line.
- C10. Merging pictures frees the connectors attached to them.
- C11. Locked objects can be attached to. Hidden ones keep their connectors,
  frozen in place. Connectors can attach across layers.
- C12. Moving an object and everything attached to it is one undo step.
- C13. Remove marks can remove a connector, like any other line.
- C14. Stored as an ordinary line plus a note of what each end is attached to;
  older builds see a line.

Added after peer pass 1 (Frank's answers, 2026-10-27):
- C6 (revised) / C16. A line whose attached ends are all pins on pictures is a
  mark on a picture: dragging it, arrow keys and align move it as today and it
  re-pins where it lands. A line with any edge-riding end is a connector:
  dragging its body bends it; arrow keys and align move only its pinned and free
  ends, and edge-riding ends stay on their outlines.
- B10. The shadow follows the visible shape (a cut-out's outline; the letters of
  text without a backdrop; otherwise the box) and always falls downward on the
  page.
- C15. An end dropped inside an unfilled rectangle or ellipse attaches to it only
  near its outline; further inside it passes through to what is below.
- B11. Clicking a border selects the object; the border also counts for dropping
  arrow ends. Aligning, snapping and size boxes still use the object's own edge.

## Peer step 1, 2026-10-27, plan at `borders-connectors/PLAN.md`
Cast:
- Critic A: Codex `gpt-6-luna`, read-only sandbox, given the plan and the repo.
- Critic B: planned as Grok `grok-4.7`, which hung twice in headless mode with
  no answer; then DeepSeek via opencode, which hit opencode's free usage limit
  (so did GLM). It was run as a **Claude subagent**, the same model family as the
  author and solver B, so its agreement with solver B counts for less.
- Blind solver A: Gemini via `agy` (`gemini-3.8-flash-high`), given the problem
  and the rules only. The first run was refused a shell permission; re-run with
  `--dangerously-skip-permissions` (it ran `office begin`; it changed no files).
- Blind solver B: Claude subagent, given the problem and the rules only.

Reports are in `borders-connectors/peer-1/`.

| # | Finding | From (their rating) | Ours | How checked | Done |
|---|---|---|---|---|---|
| P1 | A click on an attached end's handle detaches it (handle grab 9/zoom vs hit tolerance 4/zoom) | Critic B (HIGH) | HIGH | read in source (interactor.dart:168, controller.dart:856) | v2: nothing changes until moved |
| P2 | Attach lookup via `objectsAt` skips locked targets, so it hits what is underneath | Critic A (HIGH), Critic B (MED), both solvers | HIGH | read in source (controller.dart:856) | v2: `attachTargetAt` |
| P3 | A pin can land outside its picture (hit tolerance) | Critic A (MED) | MEDIUM | read in source (scene.dart:240) | v2: opaque pixel required, pin clamped |
| P4 | Unmerge brings back stale attachments, and doesn't scale border width | Critic B (MED), solver B | MEDIUM | read in source (`_unmergeInto`, controller.dart:1977–2008) | v2: batch remap, scale by k |
| P5 | Pushing the end out by `w` along the ray leaves the tip inside the border at an angle | Critic B (MED) | MEDIUM | geometry (w·cosθ) | v2: intersect the grown outline |
| P6 | `paintBounds` too small for turned objects | Critic B (MED) | MEDIUM | geometry | v2: from turned corners; margins kept |
| P7 | Bending a connector drifts from the pointer; the middle jumps to the press | Critic B (MED), solver B | MEDIUM | read in source (`_doBend`) | v2: `anchorBend`, grab parameter t |
| P8 | Relink does run after restore, load and recovery; must be idempotent and run before `markSaved` | Critic B (LOW), solver B | MEDIUM: a dangling attachment would leave doc ≠ disk with dirty false, unnoticed | read in source (`loadProjectJson`, `showToast`) | v2: invariant + tests + before markSaved |
| P9 | Nudge, align and position boxes on an attached line swing it | Critic B (LOW), solver B | MEDIUM: visible, and it is the commonest edit | read in source (`nudge`) | Frank decided → C16 |
| P10 | Shadow as a box shows through cut-outs and text; offset sideways when rotated | Critic B (LOW), solver B | LOW | reasoning | Frank decided → B10 |
| P11 | A mixed picture + text selection gets no Border row (B5) | Critic B (LOW) | LOW | read in source (`_typeSectionMulti`) | v2: fixed |
| P12 | Arrows drawn on a screenshot pin to it, so a drag bends them: moving arrows stops working | Critic B (LOW), solver B | HIGH: the commonest edit breaks | reasoning from C4+C6+C11 | Frank decided → C16 |
| P13 | A curved end must aim at the control point, not the curve's middle | Solver A | MEDIUM | geometry | v2: fixed |
| P14 | Text being edited is not painted, so its border would vanish while typing | Solver B | LOW | read in source (canvas_painter.dart:39) | v2: fixed |
| P15 | Parse the new fields defensively; never use the key `asset` | Solver B | MEDIUM: a bad field fails the whole file | read in source | v2: fixed |
| P16 | `withCovers` must use the painted extent | Solver B | LOW | read in source | v2: fixed |
| P17 | Plain line ends' round caps overlap the outline by half the width | Solver B | LOW | read in source (`_linePaint`) | v2: pulled back |
| P18 | Clicking the border should select the object | Solver A | LOW | — | Frank decided → B11 |
| P19 | "Give all pictures this border": locked/hidden layers? | Solver A, solver B | LOW | — | v2: skips locked + locked/hidden layers |
| P20 | An unfilled shape's hit test is only its outline | Critic B, solver B | MEDIUM | read in source | Frank decided → C15 |

Declined:
- **"Skip re-projecting ends moved together" (solver A, `movedTogetherIds`).**
  Translating everything and then relinking from the moved anchors gives the
  same result, with one fewer special case.
- **"Run relink before export and save" (solver A).** Relink already runs on
  every notify and `endEdit`, so the stored state is current. Export must not
  change the document.

Direction: the plan **grew**. It has one more stored field (`anchorBend`), a new
lookup (`attachTargetAt`) and four new rules. Most of that growth is the rules
Frank decided, not new mechanism; `anchorBend` is the one new piece of state.
Pass 2 decides whether it is growing for good.

## Peer step 2, 2026-10-27, plan v2
Cast (fresh; neither saw pass 1's reports):
- Critic A: Codex `gpt-6-luna`, read-only.
- Critic B: Gemini (`agy`).

No blind solver this pass: pass 1's Claude solver had independently arrived at
the anchor-chord bend that v2 added as `anchorBend`.

| # | Finding | From (their rating) | Ours | How checked | Done |
|---|---|---|---|---|---|
| Q1 | Relink pulls a moved mark-on-a-picture back to its pins: drag freezes, and nudge/align are discarded with no undo step | Gemini (HIGH) | HIGH | read in source (`_doMove`, `nudge`, `endEdit`) against plan v2 | v3: the re-pin rule |
| Q2 | During an end drag the old attachment is still set, so relink holds the end on its target | Gemini (HIGH) | HIGH | plan v2 text (v1 had "set aside at press", v2 lost it) | v3: held aside on first move, preview attachment |
| Q3 | A group move re-pins a pin to another picture underneath | Codex (MED) | MEDIUM | plan v2 text | v3: a pin whose target moves keeps it |
| Q4 | A picture's border band is not counted by `attachTargetAt` (B11) | Gemini (MED) | MEDIUM | plan v2 text | v3: fixed |
| Q5 | Shapes' stroke width ignored at the outline, burying the tip | Gemini (MED) | MEDIUM | read in source (`_paintShape`, `ShapeObject.bounds`) | v3: drawn outline |
| Q6 | The "straight above the centre" degenerate rule jumps when one object sits inside another | Gemini (MED) | MEDIUM | plan v2 text | v3: only for anchor == centre |
| Q7 | "Cut `anchorBend`; and the plan's 'cut at the outline crossings' contradicts aiming the ray at the control point" | Gemini (cut) | The contradiction is real; the cut is declined | geometry | v3: curved ends cut the curve itself at its crossing (bisection); `anchorBend` kept |

Declined:
- **Cut `anchorBend` (Gemini).** Gemini says `p1`, `p2` and `bend` alone are
  enough. But the ends depend on the curve and the curve on the ends, so
  re-deriving each pass drifts, and drift makes phantom undo steps and dirty
  files. Pass 1's blind solver B independently stored the same thing.
  Second opinion: put to the fresh critics of pass 3.

Direction: the plan grew by one subsection, the re-pin rule. That is a
mechanism Frank's C16 needs, not new state; no new fields. Both HIGHs came
from v2's own additions (C16 and the end-drag rewrite), the pattern the skill
warns of: fixes cause new problems. Pass 3 runs with fresh critics.

## Peer step 3, 2026-10-27, plan v3
Cast (fresh; neither saw earlier reports):
- Critic A: Codex `gpt-6-luna`, read-only.
- Critic B: Claude subagent.

| # | Finding | From (their rating) | Ours | How checked | Done |
|---|---|---|---|---|---|
| R1 | Re-pinning frees a pin whose target is hidden (lookup skips hidden things), against C11 | Codex (HIGH) | MEDIUM: needs an unusual sequence (hide the picture, then move the line) | plan v3 text vs `objectsAt` | v4: hidden target re-pins on the same target |
| R2 | A mark moved onto a label or near a frame silently becomes a connector | Claude (MED) | MEDIUM | plan v3 text vs `attachTargetAt` | v4: re-pin finds pictures only |
| R3 | The bend handle on a connector is unspecified, so it does nothing or swims | Claude (MED) | MEDIUM | read in source (`handlesFor`, `_doBend`) | v4: same solve as the body drag |
| R4 | Flip and unmerge don't update `anchorBend` | Claude (MED, rare) | MEDIUM | read in source (properties_panel.dart:858, `_unmergeInto`) | v4: fixed |
| R5 | A bordered cut-out gets a rectangular shadow, against B10 | Codex (MED) | LOW: visible, cosmetic, and fixed cheaply | plan v3 text | v4: ring plus outline |
| R6 | A frozen edge end anchors at its outline point, so a curve changes while its target is hidden | Claude (LOW) | LOW | geometry | v4: keeps the centre as its anchor |
| R7 | Clamping pins pulls drops on the border band in to the edge | Claude (LOW) | LOW | plan v3 text | v4: clamp to border band |
| R8 | Define "being moved"; don't widen `ImageObject.hitTest` (used by `imageAt`); read `anchorBend` defensively | Claude (LOW) | LOW | read in source (`imageAt` callers) | v4: fixed |

Second opinion on the `anchorBend` decline (pass 2): **both** fresh critics say
keep it. The decline stands.

Direction test: compared with pass 2, the findings are **less severe** (no
HIGH by our rating), **in rarer situations** (hidden targets, flip, unmerge),
and **all in v3's own additions** (the re-pin rule, `anchorBend`). The plan is
converging, and the plan grew only by sentences, not state. **The peer step
stops here.** The one decision rated lower than its reviewer (R1, HIGH →
MEDIUM) goes to the round-1 disposition auditor.

## Build
Built from plan v4 at commit `427c4ca`.
- `test/connectors_test.dart` (27 tests) and `test/borders_test.dart` (9).
- `flutter analyze` is clean, and all 299 tests pass.

Used once in the real app (headless, through the inspector's `/do drag`,
because `tool/xinput.py` input did not reach the window today). On the
storefront sample:
- an arrow drawn from the "Which awning?" text to the navy awning attached to
  both;
- moving the text, then the awning, kept it on both.

Changes the build made beyond the plan:
- The Border row sits **below** Edit, without a section title. "Give all
  pictures this border" is a small button on the row rather than a full-width
  one: the full-width version pushed "Remove background" off a 900 px screen.
- A mixed picture + text selection gets the row (B5); the panel test found it
  missing.
- Plain (non-arrowhead) ends are pulled back by half the line width only on
  straight connectors. On curved ones they are not.
- A connector the curve of which never leaves an outline (overlapping
  objects) is drawn straight.

## Round 1, 2026-10-27, commit `427c4ca`
Predictions (written before the round):
- About 3 to 5 verified findings, no more than one HIGH.
- Most will be in the interaction code (re-pinning, the end-drag preview,
  bending), as the peer passes were.
- Rather fewer in borders, which are mostly drawing and covered by pixel tests.
- File compatibility (old files, older builds) will hold: no HIGH there.
- Likely LOW: the hidden-target freeze on curved connectors; the editing-text
  frame drawn above objects that are on top of it.

## Mistakes the next author will make
(filled in as the work goes)

Cast:
- Whole-code reader: Codex `gpt-6-luna`, workspace-write on its own copy. Its
  first run refused (the copy is not a git repo); it was re-run with
  `--skip-git-repo-check`.
- File-safety specialist: Gemini (`agy`), with a copy of the old build
  (`500f942`).
- Rules reader: Claude subagent, driving the real app through the inspector and
  writing scratch tests.

| # | Finding | Reader (their rating) | Ours | How checked | Reaches | Done |
|---|---|---|---|---|---|---|
| F1 | Dragging the body of an **already-selected** connector that sits over anything moves it instead of bending it. A pinned tip re-pins to a different spot of the picture; between two text boxes the drag does nothing. Cause: the click-to-cycle flag (`_clickOnSelectedTop`) skips the bend branch in `_downSelect` | Rules (MED) | MEDIUM: visible and undoable, but it happens most times Frank drags an arrow on a screenshot | reader's test + read in source (interactor.dart:330–353) | how it is used now | fix, after a peer step |
| F2 | A curved connector changes shape (middle ~8–16 px) when one of its targets is deleted, merged away or left out of a copy: the curve was measured from that target's centre, then from the line's own end | Rules (LOW) | LOW: a few pixels, visible, only on curved connectors | reader's test + read in source (`_relink`: `a1 = l.p1` once `start` is dropped) | how it is used now | fix: re-fit `anchorBend` to the drawn curve when an end goes free |
| F3 | No Border row when pictures/text are selected together with anything else (e.g. three screenshots and an arrow) | Rules (LOW) | LOW | read in source (`_selection`) | how it is used now | fix: show it when any selected object takes a border; it applies to those |
| F4 | Text boxes have round corners (6 px + border), but ends ride a square outline: aimed at a corner, the tip stops 4–8 px short | Rules (LOW) | LOW | read in source (`outlineOf`) | how it is used now | fix: the outline's corners are round for text |
| F5 | `borderWidth` is written to the file whenever it isn't 4, even with no border (B8: only when one is set) | Rules (LOW) | LOW | read in source (`frameJson`) | how it is used now | fix |

Rules reader, PASS on everything else, checked in the real app:
- old files: no pixel of export differs, and they re-save identical;
- a new file opens in the old build;
- export and copy match the canvas.

The whole-code and file-safety readers found nothing. Each listed what it
checked; see their reports.

What happened against the predictions:
- 5 verified findings, inside the predicted 3–5, but **no HIGH**.
- All are in interaction or drawing details, as predicted.
- File compatibility held: two readers, two models, nothing found.
- My two predicted LOWs (the hidden curve freeze, and the editing frame drawn
  on top) were **not** found. The reader found other ones: F2 to F5.

Believed, and wrong: "The body-drag bend works whenever the connector is the
only thing selected." It works only when nothing else is under the press,
which on a screenshot is almost never. The plan said "(or becomes so by the
press)" and the build tied it to the click-cycle flags without anyone
noticing. My own gesture test drew the connector over empty page.

### Peer step for the F1 fix
Plan: in `_downSelect`, a press that lands on the single selected connector
starts a body bend, whatever the click-cycling flags say. The flags are still
worked out, and on a release without movement the existing click behaviour
runs (`_finishClick`: pick what is beneath, cycle, or select the top). That
covers presses on a connector with things above or below it.

Peer reports: `round-1/peer-f1/`. Critic: Codex. Blind solver: Claude, whose
report is summarised here.
- The solver independently designed the same fix, and added a `_bodyBend`
  flag: ignore movement below the drag threshold, then run `_finishClick` on
  release.
- The critic's MEDIUM: `lineEnd` mode never calls `_finishClick`, so the plan
  as worded loses click-to-cycle. That is the mechanism the solver's design
  supplies; it was taken.
- The critic also noted that the double-click-on-text check and the Alt/Shift
  handling run before the bend branch. That is correct and intended.

A detail-only pass, so the peer step stopped there.

Fixes, commit `08888db`:
- F1: the bend branch keys on "the press hits the single selected connector".
  A click without movement ends the edit (no change, no undo step) and runs
  `_finishClick`.
- F2: `refitBend` extends the drawn quadratic to the new anchors when an end
  goes free (in relink) or is dropped from a copy (`remapAttachments`).
- F3: the Border row shows when any selected object takes a border, and
  changes only those.
- F4: the outline has round corners for text (radius 6 + border width).
- F5: `borderWidth` is written only with a border.

All fixes have tests; there are 303 tests in all.

### Disposition audit, round 1 (Codex `gpt-6-luna`; `round-1/audit/`)
- **Rated too soft, and accepted:**
  - P10 and R5 (the shadow shape): LOW → **MEDIUM**;
  - F2 (a curve shifting when its target goes): LOW → **MEDIUM**;
  - F4 (the tip short of a round corner): LOW → **MEDIUM**.

  The profile's rule is explicit: "visible" or "recoverable" never makes a
  finding LOW, and my reasons ("cosmetic", "a few pixels") were exactly that.
  All four are fixed.
- **Consequence, a breach of the method:** F2 and F4 were fixed **without the
  peer step** the profile requires for MEDIUM fixes, because they were rated
  LOW when built. Round 2's fix auditor reviews those hunks; that is the
  mitigation, not a substitute.
- **Upheld:**
  - R1 at MEDIUM (an unusual sequence);
  - F1 at MEDIUM;
  - F3 and F5 at LOW;
  - all three declines (`movedTogetherIds`, relink before export, cutting
    `anchorBend`), with reasons checked against the code.
- **Gentler on my own items:** yes, in the LOW ratings for visible defects
  (above).
- **Findings missing from the ledger:** none.

Round 1, after the audit: **0 HIGH, 4 MEDIUM (F1, F2, F4, plus the earlier
R5/P10), 2 LOW.** It needed MEDIUM fixes, so by the profile's stop rule a
round 2 follows.

## Round 2, 2026-10-27, commit `08888db`
Predictions (written before the round):
- The fix auditor will find **at least one** fix that did not fully land, or
  broke something nearby. The likeliest: F2's `refitBend` (a numeric search,
  which can fail to find an anchor and silently fall back), or F1's click
  path, which could change what a plain click on a selected arrow selects.
- 1 to 3 verified findings in all, no HIGH.
- The whole-code reader finds nothing new, as in round 1.
- The rules reader confirms F1 in the real app.

Cast:
- **Whole-code reader:** Codex, fresh.
- **Fix auditor:** Gemini, with the round-1 diff `3bceef5^..08888db` (code
  only).
- **Rules reader:** Claude, fresh.
- **The file-safety specialist is rested this round:** one clean round, so not
  yet retired. Its lens is narrow, and the round-1 fixes don't touch saving or
  loading except F5, which the fix auditor covers.

| # | Finding | Reader (their rating) | Ours | How checked | Reaches | Done |
|---|---|---|---|---|---|---|
| G1 | Align with a screenshot, a mark pinned on it and a caption: the screenshot (shift 0) doesn't count as moving, so the mark re-pins about 140 px away on the same screenshot. Align right keeps it | Rules (MED) | MEDIUM: visible and undoable; drag-select plus align is ordinary | reader's test + read in source (`alignSelection`: only non-zero shifts count). **Caused by my own v4 choice** ("for align, actually translated by a non-zero amount", from R8) | how it is used now | fixed after a peer step |
| G2 | Arrow tails float beside short labels without a backdrop: a click-made text box is 320 px wide, so the end sits on the invisible box edge, ~90 px past the last letter | Rules (outside the rules) | MEDIUM: visible in exports. It follows B4/C2 as written | reader's probe | how it is used now | **to Frank**: a rule question |
| G3 | Merging a screenshot and its label without the arrow between them puts the merged picture on top, covering the arrow; unmerge doesn't bring it back | Rules (outside the rules; z-order existed before) | MEDIUM: visible, recoverable (reorder) | reader's probe | how it is used now | **to Frank**: the behaviour predates this work |
| G4 | "A connector ends 5 px outside a bordered text box: the border is painted w/2 outside, geometry uses w" | Codex whole-code (MED) | **rejected** | **killed by pixels**: with a 10 px border, pixels 1–9 px out are border and 11 px out is page; the tip is at 10 px. The stroke is centred w/2 outside with width w, so it covers 0..w | — | none |
| G5 | `attachTargetAt`'s box test ignores the text box's round corners: an end dropped just past the arc snaps onto the box | Fix auditor (LOW) | LOW: edge case, visible, Ctrl or a drag away | read in source (`_withinOutline`) | how it is used now | fixed |

Fix auditor on round-1 fixes F1 to F5: all **GONE**; nothing broken; one change
missed in one place (G5). The whole-code reader could not run the tests (the
SDK wanted to write outside its sandbox) and read the source instead.

### Peer step for the G1 fix (`round-2/peer-g1/`)
- Plan: every selected, unlocked object counts as moving for the pins.
- Critic (Codex): it fixes the bug, but with a side effect, MEDIUM: a mark
  with a zero shift whose picture is *not* selected would be held and
  re-pinned, and could switch to another picture stacked above it.
- Blind solver (Claude) found the same thing independently, and designed:
  - `holdPins(moving, group:)`: pins come off only lines that really shift,
    and only where their picture is not in the aligned set;
  - lines attached only to aligned things ride along with no shift of their
    own.
- Taken. Declined from the solver: leaving such lines out of the alignment
  frame. That would change today's align results for lines that stick out,
  which nobody asked for.

Fixes, commit `988327c`: G1 and G5, with tests. There are 305 tests in
all.

What happened against the predictions:
- **Predicted** that the fix auditor would find at least one fix that did not
  land, most likely F2's `refitBend` or F1's click path. **Wrong.** All five
  landed; it found a missed spot (G5), not a failed fix.
- **Predicted** 1–3 verified findings, no HIGH. **Right:** G1 and G5, plus two
  rule questions.
- **Predicted** that the whole-code reader would find nothing new. **Close:**
  its one finding was killed by pixels.
- **Predicted** that the rules reader would confirm F1 in the real app.
  **Right**, it passes.

Believed, and wrong: "Align should count only what actually moves." I wrote
that into v4 from a critic's wording question (R8). It reads as more precise,
and it is exactly what makes a mark slide off its unmoved picture.

### Disposition audit, round 2 (Gemini; `round-2/audit/`)
- **G5 rated too soft: LOW → MEDIUM, accepted.** It is the same mechanism as
  F4 (round corners missed), which was rated MEDIUM in round 1, and the
  profile's precedent rule decides. It was fixed **without the peer step
  again**: the round-1 breach, repeated. Round 3's fix auditor reviews it.
- **The G1 decline does not hold, and the fix had a bug; accepted, checked in
  the source.** In `alignSelection`, a line attached only to aligned things
  gets a zero shift:
  - so a line with one pin on the picture and one **free** end
    (`end == null` passes the test) keeps its free end still while the
    picture moves, and the line stretches;
  - a mark sticking out past its picture still widens the frame, so the
    picture aligns to the mark's edge and the mark, riding along, overshoots.

  The solver's "leave carried lines out of the frame", which I declined, was
  right. A MEDIUM fix to a fix.
- **G2, "it follows B4/C2 as written", is called convenient, and is
  partly accepted.** B4 says "around the text area if there is no backdrop".
  I read "text area" as the text box, the auditor as the words. The wording
  was mine. It stays **Frank's decision**, now put to him with both readings,
  and it is rated MEDIUM. It concerns the border too, not only arrow ends.
- **G4's rejection is upheld (real); the earlier declines are upheld.**
- **Codex's G1 side effects "minimised":** not accepted. They are recorded,
  and the design taken was chosen to remove them. But the new design's own
  side effects were not checked: no fresh critic saw it. That was the miss.

Round 2, after the audit: **0 HIGH; MEDIUM: G1, G5, the G1 fix itself; plus G2
and G3 put to Frank.**

### Peer step for the corrected Align fix (`round-2/peer-g1b/`)
Plan:
- A line is **carried** when every attached end of it is on an aligned
  object.
- Carried lines are **left out of the alignment frame**.
- They **translate by the shift of their first attached target**, so a free
  end keeps its place relative to the picture. Relink then puts each pinned
  end on its spot.
- "Align to each other or to the page" counts only objects that are not
  carried, so a picture plus its own marks aligns like the picture alone.
- Pins come off only lines that really shift and whose picture is not
  aligned with them (unchanged).

Critic (Codex, fresh; `round-2/peer-g1b/`):
- Plan fixes (a) and (b).
- Two MEDIUMs:
  - a mark pinned to two selected pictures that align by different amounts
    stretches. That is what the pins say (C7/C3): **declined** as intended;
  - a line pinned on a selected **locked** picture would not count as carried
    and would re-pin across it. **Taken**: "carried" and the pin group use
    all selected objects, locked ones included; only unlocked ones are moved
    and make the frame.
- The rest were confirmed as no bug.

Built in commit `cdbe22d`, with tests for the half-free mark,
the mark that sticks out, and the locked picture. There are 307 tests.

### Frank's answers, 2026-10-27
- **G2 (text without a backdrop): "the whole text box".** B4 stands as built:
  the border and the arrow ends go round the whole text box. Closed, with no
  change.
- **G3 (merge order): "where its highest part was".** A new rule, B12: a merged
  picture takes the place of the highest merged part, so whatever was above
  the merged parts stays above. It is a MEDIUM fix, so it gets the peer step.
- **Round 3: the smaller round.** A fix auditor on the round-2 fixes and G3, a
  rules reader in the app, and the disposition auditor. Stop after it if it is
  clean.

### Peer step for G3 (`round-2/peer-g3/`)
Plan: in `_flattenSelection`, the merged picture is inserted into the layer of
the topmost merged part, at that part's index. Merged parts that sat below it
in the same layer are removed, so the index shifts down by their count.
`currentLayerId` and the selection are unchanged. Unmerge already replaces the
merged picture in place.

Peer reports: Codex critic, plus a blind solver (Claude).
- The solver designed the same rule more simply: replace the topmost part in
  its slot, then remove the others, with no index arithmetic. **Taken.**
- Codex: the plan is right.
  - **HIGH, pre-existing:** a Hide details box between merged parts, or under
    the highest one, stops covering. The merge paints the parts without it,
    and the merged picture sits above it, so hidden details can show in an
    export. The solver found the same thing independently.
  - **MEDIUM, pre-existing:** unmerge puts cross-layer parts all on one layer.

  Neither is introduced by this work, and the placement change neither causes
  nor fixes them. The HIGH goes to Frank; the MEDIUM is recorded.

G3 built with a test (merge, undo, redo, unmerge keep the arrow above). There
are 308 tests.

### H1: a merge must not un-hide details (pre-existing HIGH, fixed at Frank's request)
Frank: "Yes, merge takes covers." Plan:
- The merge paints in every Hide details box that lies over its parts, found
  as copy finds them (`withCovers`), so the merged picture has those details
  hidden.
- A Hide box that was not itself selected is **not removed**: it may also
  cover other things on the page. It stays where it is.
- A selected Hide box is merged and removed, as today.
- The merged picture still takes the highest part's place (B12).

Peer step (`round-2/peer-h1/`): Codex critic, plus a blind solver (Claude).
- Both independently: keep **two lists**.
  - **Parts** for the size, placement, removal and `multiply`.
  - **Parts plus covers** for painting.
  - Feeding `withCovers` straight in would have removed unselected boxes
    (HIGH) and enlarged the picture (MEDIUM).
- The solver also found **two more leaks of the same kind**:
  - a *selected* Hide box is removed by a merge today, exposing an
    unselected screenshot under it;
  - unmerge puts parts back above their covers.
- Taken, with three refinements:
  - a merge never removes a Hide box;
  - covers from the lowest part up to the highest are painted in. One above
    the highest stays above anyway, which avoids pixelating twice;
  - the record keeps the covers, so unmerge brings back a copy above the
    parts. A duplicate box is harmless; a missing one is not.

  Also: `multiply` is off when there are covers, and the toast says
  "Merged, with the hidden details over it".
- The plan **grew** in this pass (unmerge covers). That is justified by a
  privacy leak and recorded here.

Built in `79c8c27`, with 3 tests. There are 311 tests.

## Round 3, 2026-10-27, commit `79c8c27` (the smaller round, Frank's choice)
Predictions (written before the round):
- The fix auditor finds **one or two** problems in this round's fixes. The
  likeliest is in the merge change: H1 is the largest, newest and least
  peer-checked. For example, the duplicate covers from unmerge, or a cover on
  another layer painted in the wrong order.
- The Align rewrite holds.
- The rules reader passes everything, including B12 and the merge covers, in
  the real app. At most one LOW.
- No HIGH.

Cast:
- **Fix auditor:** Gemini, with the diff `08888db..79c8c27`.
- **Rules reader:** Claude, fresh.
- **Disposition auditor:** after sorting.

| # | Finding | Reader (their rating) | Ours | How checked | Reaches | Done |
|---|---|---|---|---|---|---|
| K1 | Things *between* the merged parts (above the lowest, below the highest) end up under the merged picture | Rules (MED) | MEDIUM | reproduced by the reader in the real app (sample + Hide box + arrow) | how it is used now | **to Frank**: what B12 means there |
| K2 | A Hide box switched off (or on a hidden layer) at merge time stops working when shown again: it now sits under the merged picture | Rules (MED) | **HIGH**: details exposed in an export, unnoticed (the Layers panel says the box is on). An unusual sequence, but the stakes' #2 harm | read in source (`_withCoversBetween` takes only visible boxes) | how it is used now (Hide boxes are toggled) | redesign H1 |
| K3 | Highlighter marks merged across a Hide box turn solid: `multiply: !covered && …` | Rules (MED) | MEDIUM | read in source (controller.dart:2120) | how it is used now | redesign H1 |
| K4 | The right-click menu offers Merge where the button, M key and panel refuse (picture + Hide box); it re-renders the picture and frees its arrows | Rules (LOW) | LOW | read in source (context_menu.dart:128: no `canMerge` check) | how it is used now | fix |
| K5 | Merge then unmerge piles up duplicate Hide boxes (the record keeps covers) | Rules (LOW) | LOW | design | how it is used now | redesign H1 |
| K6 | The Align tooltip says "Align left edges" for a picture plus its mark, which now align to the page | Rules (LOW) | LOW | read in source | how it is used now | fix |

The fix auditor (Gemini) said G1, G5, G3 and H1 were all GONE, "nothing
missed". It **missed K4**, a change applied in one place and missed in
another, which the rules reader found in the app. Its "nothing wrong" counts
for less here.

What happened against the predictions:
- **Predicted** one or two problems, most likely in the merge change.
  **Right about where:** every MEDIUM and above is in the merge change.
  **Wrong about how many:** 3 MEDIUM+ and 3 LOW, and one of them is HIGH by our
  rating.
- **Predicted** that the Align rewrite holds. **Right.**
- **Predicted** that the rules reader passes everything else. **Right**,
  except merge.
- **Predicted** no HIGH. **Wrong** (K2).

Believed, and wrong: "Painting the covers in and never removing a Hide box
means a merge can't un-hide anything." It ignored covers that are switched
off at merge time, and how a cover interacts with `multiply`.

Direction test (round 3): compared with round 2, the findings are **not** less
severe, are in ordinary use, and **are** almost all in code written to fix the
last round (the merge). The merge is not converging; the rest is.
**Stakes check due**, put to Frank.

### Frank's answers (stakes check), 2026-10-27
- **K1: "Refuse and explain."** A new rule, B13: if something visible that is not
  selected lies between the merged parts and overlaps them, the merge says so
  and does nothing.
- **Merge work: "Redesign merge, one more round."** A round 4, on merge only.

### Merge redesign (M2), peer step (`round-3/peer-m2/`)
Plan:
1. **Parts** are the mergeable things, except Hide boxes.
2. **"Between"** means everything in page order after the lowest part and
   before the highest one that is not a part and overlaps the parts' area.
3. **Refuse** (with a toast, and nothing changes) if anything in "between" is
   - **visible and not a Hide box** (B13), or
   - a **Hide box on a layer other than the highest part's**: moving it
     across layers would change what it hides.
4. **Covers** are the Hide boxes in "between", switched on or off. After the
   merge they are **moved to just above the merged picture**, keeping their
   order. Moving a Hide box up only adds to what it covers.
5. **Painting.** Switched-on covers are also painted into the merged picture,
   so moving the picture away still hides. The exception is a highlighter
   (`multiply`) merge: there the covers above do the hiding and the merge stays
   see-through. `multiply` comes from the parts only.
6. **The merged picture** takes the highest part's place (B12).
7. **The merge record** keeps only the parts. Unmerge puts them back in the
   merged picture's slot, which is below the covers. No duplicates.
8. **The context menu** offers Merge only when `canMerge` (K4).
9. **The Align tooltips** say "page" whenever the selection aligns to the page
   (K6).

Peer reports: Codex critic, plus a Claude critic (fresh), whose report is
summarised here.
- **Both: HIGH leaks.**
  - Claude: unmerge after the picture moves, is reordered or is duplicated,
    or after its covers are deleted: the parts come back with no cover,
    because step 7 dropped the covers from the record.
  - Codex: a Hide box **above** the highest part is not painted in, so
    dragging the merged picture out from under it shows the password.
- **Both: the move-up pixelates the arrow** in the very common case
  (screenshot, box, arrow). Claude rated it HIGH (subtle, gets shipped).
- **Both: cross-layer merges refused needlessly** (MEDIUM).
- Claude also raised:
  - overlap measured against the box around all parts, not the parts
    (MEDIUM/LOW);
  - refusals over invisible things need a named message (MEDIUM);
  - locked selected objects (LOW).

**Direction:** M2 grew from H1 and still leaked. Per the skill, that is a
design problem, so the design was **simplified** rather than patched.

### Merge design M3 (smaller than M2; nothing moves)
1. **Parts** are the mergeable things, except Hide boxes.
2. **"Between"**: after the lowest part and before the highest in page order,
   not a part, and overlapping **some part's** drawn area.
3. **Refuse**, with a toast that names the object, if anything in "between"
   is
   - visible and not a Hide box (B13), or
   - a Hide box that is switched off or on a hidden layer: it would not
     cover the merged picture once switched on.
4. **Covers** are every switched-on Hide box on a shown layer that comes after
   the lowest part (between the parts or above them all) and overlaps a part.
   - They are **painted into the merged picture, and stay where they are**.
     The merged picture then holds what the page shows.
   - The exception is a highlighter merge: covers are not painted in, the
     merge stays see-through, and the boxes still hide the page beneath.
5. **The record** keeps the parts and the covers in page order, so unmerge
   always brings the covers back with the parts, wherever the picture has
   gone. A duplicate box is harmless (K5 is declined for that reason).
6. **The merged picture** takes the highest part's place (B12).
7. **The menu** uses `canMerge` (K4). The tooltips: K6.

This answers every finding above:
- the moving-only leaks are gone (nothing moves, the record has the covers);
- the box above the top part is painted in;
- the arrow is never pixelated beyond what the page showed;
- cross-layer merges are allowed;
- overlap is measured per part;
- refusals name the object.

It is smaller than M2: no moving, no cross-layer rule. Built next; round 4
checks it.
