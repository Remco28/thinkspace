# Plan: borders and connectors (v2)

Base commit: `500f942` (branch `polish`). The rules (B1–B11, C1–C16) are in
`../LEDGER.md`, confirmed by Frank on 2026-10-27. v2 takes in peer pass 1 (see
the ledger for what was taken and declined, and why).

## The problem, plainly

1. **Borders.** Pictures and text boxes need an optional border (colour, width)
   and an on/off soft shadow, so things on the page stand apart.
2. **Connectors.** Line and arrow ends can attach to pictures, text boxes,
   rectangles, ellipses and markers, and then follow them. On a picture an end
   pins to a spot; on the others it rides the outline. This is stored data that
   must never quietly point somewhere wrong, must survive save, load, undo, copy
   and merge, and must leave old files and older builds unaffected.

## Borders

### Data
- **Fields.** `ImageObject` and `TextObject` gain `border` (ARGB int, `0` =
  none), `borderWidth` (double, default 4) and `shadow` (bool). They are shared
  through a mixin (`Framed`; not `Border`, which clashes with `painting.dart`).
- **JSON keys.** `border`, `borderWidth`, `shadow`, each written only when it
  differs from the default. Each key is read defensively: a value of the wrong
  type falls back to the default rather than failing the file.
- **Compatibility.** Old files read with the defaults, and the format version
  stays 1. Older builds ignore the unknown keys.
- **Not part of tool looks.** New pictures and new text start plain (B9).

### Drawing (`render.dart`)
- **Border.** In the object's own rotated (and flipped) frame, a stroke of
  `borderWidth` centred `borderWidth/2` outside the box edge, so it covers none
  of the content (B2).
  - On text, "the box" is the text object's rectangle, which is also what the
    backdrop fills (B4).
  - On a cut-out it is the picture's rectangle (B3).
- **Shadow (B10)** follows the visible shape and always falls straight down the
  page: offset (0, 3) in page space, whatever the rotation; blur sigma 6; black
  at 25%. It is drawn before the content and is made of:
  - **the border's outer rectangle**, filled, when there is a border;
  - otherwise, for a picture, **the picture itself** tinted black
    (`ColorFilter.mode(black, srcIn)`), so a cut-out's shadow follows its
    outline;
  - otherwise, for text with a backdrop, the backdrop rectangle;
  - otherwise, for text without one, the letters (painted with the same
    tinted-and-blurred paint).

  A semi-transparent picture's shadow fades with it, because the whole object
  is inside the opacity `saveLayer`.
- **Text being edited** is left out of the page paint (`hidden:` in
  `canvas_painter.dart`), and the overlay `TextField` draws only the fill. While
  typing, the canvas painter still draws the border and shadow of the hidden
  text object, so they don't blink off.
- **New `SceneObject.paintBounds`.** By default it is `bounds`. For a box with a
  border or shadow it is the axis-aligned box around the *turned* corners of the
  box grown by `borderWidth`, united with the same box moved by the shadow
  offset and grown by 3 sigma. The existing safety margins (`inflate(4)`,
  `inflate(2)`, `inflate(1)`) stay on top of it.

  `paintBounds` replaces `bounds` wherever drawn pixels must be contained:
  - the opacity, multiply and faded `saveLayer`s (render.dart);
  - the merge rectangle (`_flattenSelection`) and the copy-as-image rectangle
    (`renderObjects`);
  - `contentBounds` (fit page to content, grow to fit, the page grip's content
    snap);
  - the Hide box overlap test (render.dart) and `withCovers`.

  `bounds` is unchanged, so selection outlines, snapping, alignment and the size
  boxes use the object's own edge (B7).
- **Hit-testing (B11).** A bordered object's `hitTest` also counts the border
  band, so clicking a thick border selects the object.

### Panel
- **One `Border` row:**
  - a small colour swatch that opens a popup with "none", the usual palette and
    custom colour;
  - a width box (typed value, 1–40 px, greyed when the colour is none);
  - a shadow toggle.
- **Where it appears.** For pictures, in its own short section above Edit; for
  text, after Backdrop. Also for any selection made **only of pictures and text
  boxes**, in any mix (B5). The change applies to all of them as one undo step.
- **For pictures, a `Give all pictures this border` button**, as one undo step.
  It skips locked pictures and pictures on locked or hidden layers. Merged
  pictures are pictures and are included.

### Merge, unmerge, resize
- **Merge** paints through `paintObjects`, so the border and shadow become pixels
  (B6).
- **Unmerge** brings back the parts from their JSON, including borders. It scales
  `borderWidth` by `k`, as it already does for stroke widths and font sizes.
- **Resizing** an object leaves `borderWidth` as it is, like line widths.

## Connectors

### Data
- **Fields.** `LineObject` gains `start` and `end`, each a nullable
  `Attachment { String to; Offset? at }`:
  - `at == null`: the end **rides the edge** of `to`.
  - `at` set: the end is **pinned** there, in the target's own frame, as
    fractions of its size, before flipping, so the pin flips with the picture.
    It is clamped to `-0.5..0.5`, so a pin never sits outside its picture.
- **JSON keys.** `start` and `end`, written only when set: `{"to": "o12"}` or
  `{"to": "o12", "at": [u, v]}`. Read defensively: a malformed one is dropped and
  leaves a free end. The key `asset` is never used inside them (`pruneAssets`
  and `MergeRecord.assets` look for it).
- **`p1`, `p2` and `bend` stay real and stored.** Painting, hit-testing, bounds,
  export, copying and older builds use them exactly as now. Attachments only
  update them.

### Targets
- **Attachable (C1):** `ImageObject`, `TextObject`, `BadgeObject`, and
  `ShapeObject` with `highlight == none`. A line never attaches to itself or to
  another line, stroke, highlight or Hide box.
- **How an end attaches:** an end on an `ImageObject` is pinned; any other
  target's end rides the edge.
- **Same object at both ends:** both ends may be on one object only if it is a
  picture (two pins). A second edge-riding end on the same object is refused,
  and that end stays free.
- **`EditorController.attachTargetAt(p, {exclude})`** is new; `objectsAt` is not
  used, because it skips locked things (C11). It walks visible layers, topmost
  first, and visible objects, topmost first, locked included, and returns the
  first attachable object where:
  - **picture:** an opaque pixel is under `p`, by the existing alpha mask (a
    cut-out's transparent parts don't count);
  - **text, marker, filled shape:** `p` is inside the box/ellipse grown by
    border width plus `9/zoom` (the handle grab radius);
  - **unfilled shape (C15):** `p` is within `9/zoom` + half the stroke width of
    its outline. Further inside, it passes through to what is below.

### Keeping the ends in step: one central pass
`relink(doc)` is a pure function in `lib/model`. It computes every attached end
**from the targets and the line's own anchor data alone, never from the line's
current `p1`/`p2`**, except where the rules say an end is frozen. On data that is
already consistent it leaves every number unchanged. A test asserts this after
load, after undo and after every step of the gesture tests.

For each line with an attachment:
1. **Missing target** (deleted, cut, merged away, layer deleted, removed by
   Remove marks or by an emptied text box): drop that attachment. The end stays
   where it last was (C8, C10).
2. **Hidden target** (the object, or its layer): that end is frozen at its
   stored point (C11).
3. **Anchors.** Each end has one:
   - a pin's anchor is its page point, `target.toScene(unflip(at) * size)`;
   - an edge end's anchor is its target's centre;
   - a free or frozen end's anchor is its stored point.
4. **Pinned end:** the end is its anchor.
5. **Edge end:**
   - **Aim.** Straight lines aim from the centre at the other end's anchor.
     Curved lines aim at the quadratic's control point, worked out over the
     anchor chord with the line's `bend`, because a quadratic's tangent at an
     end points at its control point.
   - **Meet the outline.** Intersect that ray with the target's outline grown
     by its border width (rotated rectangle, ellipse, or marker circle), so the
     tip touches the border's outside at any angle (C2).
   - **Plain ends.** A plain (non-arrowhead) end is pulled back by half the line
     width, so its round cap doesn't overlap the outline.
   - **Degenerate cases.** If the other anchor is inside the outline, or the
     same as the centre, the end sits at the outline point straight above the
     centre. That is deterministic, never "keep previous".
6. **Write back.** Write the results to `p1`/`p2`. For a curved attached line,
   recompute `bend` so the curve keeps the shape it had over the anchor chord:
   the drawn curve is the anchor-chord quadratic cut at the two outline
   crossings, and a piece of a quadratic is an exact quadratic. To let this
   recomputation be exact and repeatable, an attached curved line also stores
   `anchorBend` (the bend over the anchor chord); `bend` is derived from it.
   Older builds read `bend` and draw the same curve.

**Locked lines follow** their targets: lock stops you dragging a line, not
keeping it attached.

**Where relink runs:**
- In an override of `notifyListeners()`, before notifying. That covers every
  live gesture (`c.notify()`), sliders (`liveEditSelected`), text typing, undo,
  redo, abort, load and recovery.
- At the **start of `endEdit`**, before `_growToFit` and the signature
  comparison, so the undo step includes the moved ends (C12).
- In `loadProjectJson` and `restoreRecovery`, **before `markSaved`**, so a file
  with a dangling attachment is cleaned before its saved signature is taken.

### Moving connectors (C6, C7, C16)
A line whose attached ends are **all pins** (or that has none) is a mark on a
picture. A line with **any edge-riding end** is a connector between things.
- **Dragging the body.** When the line is the only thing selected (or becomes so
  by the press):
  - **mark on a picture:** it moves as today. On release, each pinned end
    re-pins to whatever attachable object is under it then (by
    `attachTargetAt`), or becomes free if there is none.
  - **connector:** it bends. The grabbed point stays under the pointer: the
    press position becomes a fixed parameter `t` along the curve (clamped to
    0.2–0.8). During the drag, `anchorBend` is solved so that the point at `t`
    follows the pointer, and relink then places the ends. The existing
    snap-straight slack applies, measured over the anchor chord.
- **Multi-selection moves, arrow keys, align, typed position boxes.** Everything
  selected translates; then pinned and free ends of selected lines take the
  translation, and pinned ends re-pin on finish as above. Edge-riding ends stay
  on their outlines. So a line moved with all its targets moves whole (C7), and
  a connector nudged on its own changes only its free ends.
- **Ends handles.** An attached end's handle is drawn filled; a free one hollow,
  as now.

### Dragging an end, and drawing (C4, C5)
- **Drawing a line or arrow.** At press, the start end attaches to
  `attachTargetAt` under the pointer, unless Ctrl is held. While dragging,
  `c.attachHover` names the target under the far end, and the canvas painter
  outlines it. On release, the far end attaches there, unless Ctrl is held.
- **Dragging an end handle.** Nothing changes until the pointer has actually
  moved (`_moved`): a click on a handle leaves the attachment exactly as it was.
  Once moving, the end is shown where release would put it: on the hover
  target's pin or edge point, or free and snapped. On release, it attaches if
  over a target and Ctrl is not held; otherwise it is free (C5).
- **Precedence.** Attaching beats grid snapping and the Shift angle constraint.
  Ctrl means neither attaching nor snapping, as Ctrl already means for snapping.

### Copying (C9)
- **The batch rule.** `duplicateSelection`, `pasteObjects`, `duplicateLayer` and
  `_unmergeInto` each build an `old id → new id` map for their batch. A copied
  line's attachment is re-pointed to its target's copy if that target is in the
  same batch; otherwise it is dropped, and that end is a free line.
- **What the batches cover:**
  - for paste, `_clip` keeps the attachments and remapping happens at paste;
  - for unmerge, links between parts merged together come back, and links to
    anything outside the merge are dropped (C10).

### Remove marks
Lines are already removable; nothing changes (C13).

## Tests (step 0; they grow each round)
- **Model:**
  - JSON round trip for borders, attachments and `anchorBend`;
  - an old file reads with defaults and re-encodes identically;
  - malformed `border` or `start` values load as defaults or free ends.
- **Geometry:**
  - edge points on rotated rectangles, ellipses and markers, with and without a
    border, at oblique angles (the tip on the border's outside);
  - pins on rotated, flipped, resized pictures;
  - curved attached lines;
  - `paintBounds` of a 45° picture with a thick border.
- **Idempotence:** relink twice leaves the signature unchanged; load, undo and
  redo leave the signature unchanged and `dirty` false.
- **Interactor:**
  - draw an arrow from text to a picture, move each, and the ends follow;
  - Ctrl leaves the arrow free;
  - a click on an attached handle changes nothing; a drag into empty space
    detaches;
  - a body drag bends a connector, keeping the grab point under the pointer, and
    moves a mark on a picture;
  - a multi-selection move; arrow keys on a connector;
  - an end dropped inside an unfilled frame pins to the picture below, and near
    its line rides it;
  - a locked background takes a pin;
  - moving a target is one undo step.
- **Controller:**
  - delete, cut, merge, delete layer and Remove marks each leave a free line in
    place;
  - duplicate, paste, duplicate layer and unmerge, with and without the target;
  - a hidden target freezes the end;
  - a locked line follows;
  - "Give all pictures this border" skips locked pictures.
- **Render (export pixels):**
  - a border outside the edge;
  - a shadow below it, including on a rotated picture;
  - a cut-out's shadow following its outline;
  - a border on a 50% opacity picture;
  - a merge and a copy that keep a rotated picture's border corners.
- **Widget:**
  - the Border row for pictures, text and a mix, changing all of them as one
    undo step;
  - the border is visible while editing text.

## Not doing
Elbow lines, routing around obstacles, connection points, attaching to lines or
strokes, borders that follow a cut-out's outline, shadow settings, any callout
tool.
