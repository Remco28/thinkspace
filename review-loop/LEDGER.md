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

## Peer step 1, 2026-10-27, plan at `borders-connectors/PLAN.md`
Cast:
- Critic A: Codex `gpt-6-luna`, read-only sandbox, given the plan and the repo.
- Critic B: Grok `grok-4.7`, given the plan and the repo.
- Blind solver A: Gemini via `agy`, given the problem and the rules only.
- Blind solver B: Claude subagent, given the problem and the rules only.

Reports are in `borders-connectors/peer-1/`.

## Mistakes the next author will make
(filled in as the work goes)
