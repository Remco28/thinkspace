# The problem (for blind solvers)

Thinkspace is a small Flutter desktop app (repository: `/home/frank/Projects/Thinkspace`,
commit `500f942`) for arranging pictures, text, lines and arrows on a page to
show someone what you mean. Read `README.md` and `docs/ARCHITECTURE.md` first;
`CLAUDE.md` has the project's rules.

Two features are to be added. The owner has decided the behaviour; the rules
below are confirmed.

1. **Borders.** Pictures and text boxes get an optional border (colour, width)
   and an on/off soft shadow, so things on the page stand apart.
2. **Connectors.** Line and arrow ends can attach to objects and then follow
   them.

## Confirmed rules

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
- B9. New pictures get no border automatically.

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
- C6. A line with any end riding an outline (text, shape, marker) is a connector: dragging its body bends it; arrow keys and align move only its pinned and free ends, edge-riding ends stay on their outlines. A line whose attached ends are all pinned on pictures is a mark on a picture: dragging it, arrow keys and align move it as today, and it re-pins where it lands.
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
- C15. An end dropped inside an unfilled rectangle or ellipse attaches to it only near its outline; further inside it passes through to what is below.
- B10. The shadow follows the visible shape (a cut-out's outline; the letters of text without a backdrop; otherwise the box) and always falls downward on the page.
- B11. Clicking a border selects the object; the border also counts for dropping arrow ends.

What matters most to the owner, worst first:
1. a file that won't open, or lost work;
2. an exported picture whose arrow quietly points at the wrong spot;
3. old files no longer looking exactly as before.
