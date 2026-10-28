# Plan: borders and connectors (v4)

Base commit: `500f942` (branch `polish`). The rules (B1–B11, C1–C16) are in
`../LEDGER.md`, confirmed by Frank on 2026-10-27. v2 took in peer pass 1, v3 took in peer pass 2,
v4 takes in peer pass 3 (see the ledger for what was taken and declined, and why).

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
  - **the border's ring** (outer rectangle minus the box), when there is a
    border, plus the content's own shape below;
  - plus, for a bordered picture, the picture itself tinted black (so a
    bordered cut-out's shadow is the border ring and its outline, never its
    transparent inside: the ring is filled as a ring, not a solid rectangle);
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
- **Hit-testing (B11).** Selecting (`objectsAt`) and `attachTargetAt` also count
  a bordered object's border band, so clicking a thick border selects the
  object. `ImageObject.hitTest` itself is unchanged, because `imageAt` (used by
  cut-out and remove-colour) must only find points on the picture.

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
    It is clamped to the picture plus its border band, so a pin never sits
    outside what is drawn of its picture.
- **JSON keys.** `start`, `end` and `anchorBend`, written only when set: `{"to": "o12"}` or
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
    cut-out's transparent parts don't count), or `p` is on its border band
    (B11);
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
   - a free end's anchor is its stored point;
   - a frozen end (hidden target) keeps the anchor it would have if visible
     (its pin's page point, or its target's centre), while the end itself stays
     at its stored point.
4. **Pinned end:** the end is its anchor.
5. **Edge end:**
   - **Aim.** Straight lines aim from the centre at the other end's anchor.
     Curved lines aim at the quadratic's control point, worked out over the
     anchor chord with the line's `bend`, because a quadratic's tangent at an
     end points at its control point.
   - **Meet the outline.** Intersect with the target's *drawn* outline: grown
     by `borderWidth` for text, by `strokeWidth/2` for a rectangle or ellipse,
     and by the ring's outer half for a marker. The outline is a rotated
     rectangle, an ellipse or a circle. This way the tip touches what you see,
     at any angle (C2).
     - Straight: the ray from the centre towards the aim.
     - Curved: the anchor-chord quadratic itself (control point from
       `anchorBend`). The crossing is found by bisection on the curve's
       parameter, from the anchor outwards. There is one crossing per
       edge-riding end; a pinned or free end is the curve's end itself.
   - **Plain ends.** A plain (non-arrowhead) end is pulled back by half the line
     width, so its round cap doesn't overlap the outline.
   - **Degenerate cases.**
     - If the other anchor is inside the outline, the ray is still well
       defined and is used as it is.
     - Only when the other anchor is exactly the centre does the end sit at the
       outline point straight above the centre.
     - Both are deterministic, never "keep previous".
6. **Write back.** Write the results to `p1`/`p2`. A curved attached line also
   stores `anchorBend`, the bend over the anchor chord, which is the line's
   authoritative shape.
   - The drawn curve is the piece of the anchor-chord quadratic between the
     crossings found in step 5. A piece of a quadratic is an exact quadratic, so
     `bend` (over `p1`–`p2`) is recomputed from that piece and stored.
   - Older builds read `bend` and draw the same curve; when they save, they drop
     `start`, `end` and `anchorBend` together, leaving a free curved line.
   - **Why not derive the shape from `p1`, `p2`, `bend` alone?** The ends depend
     on the curve and the curve on the ends. Re-deriving each pass drifts, and
     drift would make phantom undo steps and dirty files.
   - **When a curved line gets its first attachment**, or is bent while
     attached, `anchorBend` is set from the current curve over the anchor chord.
     A straight line writes no `anchorBend`.

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

### Gestures that move a line itself: re-pinning
Relink derives pinned ends from their targets. A gesture that moves the *line*
without moving its target must therefore first change the pin, or relink pulls
the end straight back.
- **"Being moved"** means selected and unlocked, and, for align, actually
  translated by a non-zero amount.
- **The re-pin rule.** For each moved line, each pinned end whose **target is not
  itself being moved** re-pins:
  - during a live drag, the end's attachment is held aside in the interactor and
    the end is treated as free, so relink leaves it alone;
  - on release, and at once for arrow keys, align and the position boxes, the
    end looks for a **picture** at its new point (`attachTargetAt` restricted to
    pictures, passing through text, shapes and markers). It pins there (a new
    `at`, on the same or another picture) or becomes free. A mark on a picture
    never turns into a connector by being moved.
  - **If the pin's target is hidden**, the end re-pins on that same target (a
    new `at`, no lookup), so it stays attached to it (C11).
- **A pin whose target moves with it keeps its attachment unchanged.** Relink
  carries it, so a group move never re-attaches it to a different picture
  underneath (C7).
- **Edge-riding ends** are never held aside by a move. Relink keeps them on their
  outline.

### Moving connectors (C6, C7, C16)
A line whose attached ends are **all pins** (or that has none) is a mark on a
picture. A line with **any edge-riding end** is a connector between things.
- **Dragging the body.** When the line is the only thing selected (or becomes so
  by the press):
  - **mark on a picture:** it moves as today, using the re-pin rule above.
  - **connector:** it bends. The grabbed point stays under the pointer: the
    press position becomes a fixed parameter `t` along the curve (clamped to
    0.2–0.8). During the drag, `anchorBend` is solved so that the point at `t`
    follows the pointer, and relink then places the ends. The existing
    snap-straight slack applies, measured over the anchor chord.
- **Multi-selection moves, arrow keys, align, typed position boxes.** Everything
  selected translates. Pinned and free ends of selected lines take the
  translation, with the re-pin rule for pins whose target did not move.
  Edge-riding ends stay on their outlines. So a line moved with all its targets moves whole (C7), and
  a connector nudged on its own changes only its free ends.
- **The bend handle** on a connector goes through the same solve as the body
  drag (the handle's own `t`, solving `anchorBend`). On a free line or a mark
  on a picture, it works as today and sets `bend`; on a mark, `anchorBend` is
  then recomputed from the new curve over the anchor chord. The pins are the
  ends, so that is exact.
- **Flip** of a picture negates `anchorBend.dy` (and `bend.dy`) of lines
  pinned at both ends to it, so a curve mirrors with its picture. **Unmerge**
  maps `anchorBend` the way it maps `mid`.
- **End handles.** An attached end's handle is drawn filled; a free one hollow,
  as now.

### Dragging an end, and drawing (C4, C5)
- **Drawing a line or arrow.** At press, the start end attaches to
  `attachTargetAt` under the pointer, unless Ctrl is held. While dragging,
  `c.attachHover` names the target under the far end, and the canvas painter
  outlines it. On release, the far end attaches there, unless Ctrl is held.
- **Dragging an end handle.** Nothing changes until the pointer has actually
  moved (`_moved`): a click on a handle leaves the attachment exactly as it was.
  - On the first movement, the end's attachment is removed from the line and
    held in the interactor; Escape puts it back (`abortEdit`).
  - On each move, the line's end gets a **preview attachment** for the hover
    target (so relink shows it on the pin or edge point), or none, in which case
    the end is free and snapped under the pointer.
  - On release, the preview stays if there is one and Ctrl is not held;
    otherwise the end is free (C5).
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
  - malformed `border`, `start` or `anchorBend` values load as defaults, free
    ends or a straight anchor chord.
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
  - a mark on a picture moves by drag, arrow keys and align, and re-pins;
  - a group move with the pin's target keeps the same target even over another
    picture;
  - an end dragged off its target follows the pointer during the drag;
  - an arrow end attaches on a picture's border band, and stays there;
  - a mark dragged onto a label stays a mark, pinned to the picture below;
  - a mark on a hidden picture, nudged, stays attached to it;
  - the bend handle on a connector follows the pointer;
  - flipping a picture mirrors a curved mark pinned to it;
  - an arrow tip on a thick-stroked rectangle touches the stroke's outside;
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
