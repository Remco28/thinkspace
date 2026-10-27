# Plan: borders and connectors

Base commit: `500f942` (branch `polish`). Rules B1–B8 and C1–C14 are in
`../LEDGER.md`, confirmed by Frank on 2026-10-27.

## The problem, plainly

1. **Borders.** Pictures and text boxes need an optional border (colour, width)
   and an on/off soft shadow, so things on the page stand apart.
2. **Connectors.** Line and arrow ends can attach to pictures, text boxes,
   rectangles, ellipses and markers, and then follow them. On a picture an end
   pins to a spot; on the others it rides the outline. This is stored data that
   must never quietly point somewhere wrong, must survive save, load, undo,
   copy and merge, and must leave old files and older builds unaffected.

## Borders

### Data
- `ImageObject` and `TextObject` gain `border` (ARGB int, `0` = none),
  `borderWidth` (double, default 4) and `shadow` (bool). They are shared through
  a small mixin, so both write the same JSON keys: `border`, `borderWidth`,
  `shadow`, each written **only when it differs from the default**. Old files
  read with defaults. Older builds ignore unknown keys (checked: `fromJson`
  reads named keys only).
- They are not part of tool looks (`ToolStyle`): new pictures and new text start
  plain (Frank: "no border" for new pictures; text follows the same rule).

### Drawing (`render.dart`)
- In the object's own rotated (and flipped) frame:
  - **Shadow:** drawn first, as a rounded rectangle the size of the box plus the
    border, offset (0, 3) and blurred (`MaskFilter.blur`, sigma 6), black at 25%.
  - **Content.**
  - **Border:** a stroke of `borderWidth`, centred `borderWidth/2` outside the box
    edge, so it covers none of the content.
- On a text box the "box" is the text object's rectangle, which is also what the
  backdrop fills. On a cut-out it is the picture's rectangle (rule B3).
- **New `SceneObject.paintBounds`** = `bounds` by default. For a box with a border
  or shadow it is `bounds` grown by the border width plus the shadow's reach
  (offset plus 3 sigma). It is used wherever something must contain the
  *drawn* pixels:
  - the opacity/multiply `saveLayer` and the faded `saveLayer` in `paintObjects`
    (otherwise a semi-transparent bordered picture loses its border);
  - the merge rectangle (`_flattenSelection`) and the rendered-copy rectangle
    (`_copyRenderedSelection`);
  - `contentBounds` (fit page to content, auto-grow);
  - the Hide details overlap test (`o.bounds.overlaps(area)` in render.dart:181),
    so a border under a Hide box is pixelated too.
- `bounds` itself is unchanged, so selection, snapping, alignment, the size
  boxes and hit-testing use the object's own edge (rule B7).

### Panel
- One row, `Border`:
  - a small colour swatch that opens a popup with "none" plus the usual
    palette and custom colour;
  - a width box (typed value, 1–40 px, greyed when the colour is none);
  - a shadow toggle button.
- For pictures, the row sits in its own section above Edit. For text, it sits
  after Backdrop. A multi-selection of one kind (all pictures or all text) gets
  the same row and applies it to all of them, as one undo step.
- For pictures there is also a `Give all pictures this border` button (like
  `Make all markers this size`), as one undo step. Locked pictures are skipped.

### Merge
Merge paints through `paintObjects`, so the border and shadow become pixels
(B6). The merge record keeps the parts' JSON, so unmerge brings back the
originals with their borders.

## Connectors

### Data
- `LineObject` gains `start` and `end`, each a nullable `Attachment { String to;
  Offset? at }`:
  - `at == null` means the end **rides the edge** of `to`;
  - `at` set means it is **pinned** at that spot, in the target's own frame, as
    fractions of its size (`-0.5..0.5`), measured before flipping, so the pin
    flips with the picture.
- JSON keys: `start` and `end`, written only when set: `{"to": "o12"}` or
  `{"to": "o12", "at": [u, v]}`.
- **`p1` and `p2` stay real and stored.** Painting, hit-testing, bounds, export,
  copying and older builds use them as now. Attachments only *update* them.

### Which end rides or pins
An end is pinned if its target is an `ImageObject`; otherwise it rides the edge.
Attachable targets: `ImageObject`, `TextObject`, `ShapeObject` with
`highlight == none`, and `BadgeObject`. Not attachable: strokes, highlighter
boxes, Hide boxes and lines. A line never attaches to itself. Both ends may
attach to the same object only if it is a picture (two pins). A second
edge-riding end on the same text or shape is refused.

### Keeping the ends in step: one central pass
`EditorController.relink()` walks every line with an attachment and recomputes
its attached ends from the document:
1. **Missing target** (deleted, cut, merged away, layer deleted): drop that
   attachment; the end stays where it last was (C8, C10).
2. **Hidden target** (object hidden, or its layer hidden): leave that end
   alone (C11).
3. **Pinned:** `end = target.toScene(unflip(at) * size)`.
4. **Edge-riding:** take the reference point of the *other* end (its pin, the
   centre of its target, or its free position). If the line is curved, use the
   bend point computed over the reference chord instead. Cast a ray from the
   target's centre towards it, intersect it with the target's outline (a rotated
   rectangle, an ellipse, or a marker's circle), and push the point outward by
   the target's border width, if it has one. If the reference point is inside
   the outline, or the same as the centre, keep the previous point.
5. Write the results to `p1`/`p2`. `bend` is relative to the chord, so it keeps
   its shape.

**Where relink runs:** an override of `notifyListeners()` calls `relink()` first.
Every live gesture calls `c.notify()`, every transact ends in `endEdit`, and
sliders call `liveEditSelected`, so all of them pass through it. It also runs at
the **start of `endEdit`**, before the signature comparison, so the undo step
includes the moved ends (C12). It does not run after `_restore` (undo, redo,
load): the stored `p1`/`p2` already agree with the stored targets, and changing
them on load would mark a just-opened file as changed.

**A locked line still follows** its targets: lock stops you dragging it, not
keeping it attached. Otherwise moving an unlocked picture would leave a locked
arrow pointing at the old place.

### Interaction (`interactor.dart`)
- **Drawing a line or arrow:**
  - at press, the start end attaches to the attachable object under the
    pointer, if there is one;
  - while dragging, `c.attachHover` names the object under the far end, and the
    canvas painter outlines it;
  - on release, the far end attaches to it.
  - Ctrl at either moment means no attaching (Ctrl already turns off snapping).
- **Dragging an end handle:** at press, that end's attachment is set aside. While
  dragging, the hover target is shown. On release, the end attaches if it is over
  a target and Ctrl is not held; otherwise it is left free (C5). Attaching beats
  grid snapping and Shift angle-constraint: a pin goes exactly under the
  pointer, and an edge end goes to the edge point.
- **Body drag:** pressing on a line that has any attached end, when it is the
  only thing selected (or becomes so by the press), starts a bend drag (the same
  code as the bend handle), not a move. With a multi-selection, a move
  translates everything, then relink pulls each attached end back onto its
  target, so the free end moves, attached ends stay with their objects, and a
  line moved with both its targets moves whole (C7).
- **Handles:** an attached end's handle is drawn filled; a free one hollow, as
  now.

### Copying
`duplicateSelection`, `pasteObjects` and `duplicateLayer` build an
`old id → new id` map for the batch. A copied line's attachment is re-pointed to
its target's copy if that target was copied in the same batch; otherwise it is
dropped and the copy is a free line (C9). The clipboard (`_clip`) holds copies
with their attachments; remapping happens at paste.

### Remove marks
Lines are already removable; nothing changes (C13).

## Tests (step 0; they grow each round)
- **Model:** JSON round trip for borders and attachments; an old file without the
  keys reads with defaults and re-saves byte-identical objects; an object with a
  border and attachments written then read by today's `fromJson` loses nothing
  else.
- **Geometry:** an edge point on a rotated rectangle, an ellipse and a marker; a
  pin on a rotated, flipped, resized picture.
- **Interactor:** draw an arrow from a text box to a picture, then move each, and
  check the ends follow; Ctrl leaves the arrow free; dragging an end off detaches
  it; a body drag bends when attached and moves when free; a move with a
  multi-selection; moving a target is one undo step and undo restores both.
- **Controller:** delete, cut, merge or delete layer leaves a free line in place;
  duplicate or paste with and without the target; hidden target freezes the end;
  locked line follows.
- **Render:** export pixels show a border outside the edge, a shadow below it, a
  border on a 50% opacity picture (saveLayer bounds), and a merge that keeps the
  border.
- **Widget:** the Border row exists for pictures and text, and changes all
  selected objects as one undo step.

## Not doing
Elbow lines, routing around obstacles, connection points, attaching to lines or
strokes, borders that follow a cut-out's outline, shadow settings, any callout
tool.
