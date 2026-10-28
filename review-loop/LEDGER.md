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

## Mistakes the next author will make
(filled in as the work goes)
