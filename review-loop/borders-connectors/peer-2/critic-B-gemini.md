### 1. Findings

#### Finding 1: Running `relink` in `notifyListeners()` and `endEdit()` breaks dragging, nudging, and aligning marks on pictures (Rule C6 / C16)
* **Severity:** HIGH
* **Scenario:**
  1. Frank pastes a screenshot (an `ImageObject`) and draws an arrow across a detail. Both arrow ends attach to the picture as pins (`start` and `end` have `to: imageId`, `at: [u, v]`). Under Rule C6/C16, this arrow is a "mark on a picture".
  2. Frank selects the arrow alone and presses the Down arrow key to nudge it (or clicks "Align Centre", or edits the X/Y position box in the properties panel, or drags the arrow body with the mouse).
  3. **In the code:**
     - For arrow keys: [`EditorController.nudge`](file:///home/frank/Projects/Thinkspace/lib/editor/controller.dart#L1182-L1190) executes `line.translate(d)` inside `transact('nudge')`.
     - For mouse dragging: [`CanvasInteractor._doMove`](file:///home/frank/Projects/Thinkspace/lib/editor/interactor.dart#L516-L534) calls `line.translate(step)` and then `c.notify()`.
  4. **The failure:**
     - The plan mandates that `relink(doc)` runs in an override of `notifyListeners()` (called by `c.notify()`) and at the start of [`endEdit`](file:///home/frank/Projects/Thinkspace/lib/editor/controller.dart#L484-L497) (called by `transact`).
     - `relink(doc)` derives `p1` and `p2` exclusively from the target picture's transform and the stored pin coordinates: `target.toScene(unflip(at) * size)`.
     - Because the underlying picture was not selected or moved, its center has not changed.
     - On every pointer drag event, `relink` immediately overwrites `line.p1` and `line.p2` back to the picture's stationary pin coordinates, locking the arrow in place during mouse movement.
     - In `nudge`, `alignSelection`, and property box edits, `endEdit` runs `relink(doc)` before computing the signature comparison: `relink` restores `p1` and `p2` to their pre-nudge values, `token._snap.signature == doc.signature()` evaluates to true, and the nudge/align is completely discarded without an undo step.
* **Code checked:** [`lib/editor/interactor.dart:516-534`](file:///home/frank/Projects/Thinkspace/lib/editor/interactor.dart#L516-L534) (`_doMove`), [`lib/editor/controller.dart:1182-1190`](file:///home/frank/Projects/Thinkspace/lib/editor/controller.dart#L1182-L1190) (`nudge`), [`lib/editor/controller.dart:1100-1121`](file:///home/frank/Projects/Thinkspace/lib/editor/controller.dart#L1100-L1121) (`alignSelection`), [`lib/editor/controller.dart:484-497`](file:///home/frank/Projects/Thinkspace/lib/editor/controller.dart#L484-L497) (`endEdit`), [`PLAN.md:143-147, 172-180, 181-198`](file:///home/frank/Projects/Thinkspace/review-loop/borders-connectors/PLAN.md#L143-L147).

---

#### Finding 2: Dragging an attached end handle cannot move away from its target
* **Severity:** HIGH
* **Scenario:**
  1. An arrow has an end attached to an object (e.g. `end.to = 'o1'`).
  2. Frank clicks and drags that end's handle into empty space to detach it (Rule C5).
  3. When the pointer moves, [`CanvasInteractor._doLineEnd`](file:///home/frank/Projects/Thinkspace/lib/editor/interactor.dart#L598-L615) sets `live.p2 = np` and calls `c.notify()`.
  4. `c.notify()` invokes `notifyListeners()`, which immediately runs `relink(doc)`.
  5. Because the plan states that the end only detaches *on release* ("On release, it attaches if over a target... otherwise it is free (C5)"), the line's `end` attachment is still set to `'o1'` during the drag.
  6. `relink(doc)` recomputes `live.p2` from target `'o1'` and immediately overwrites `np`. The handle refuses to leave the target outline while being dragged.
* **Code checked:** [`lib/editor/interactor.dart:598-615`](file:///home/frank/Projects/Thinkspace/lib/editor/interactor.dart#L598-L615) (`_doLineEnd`), [`PLAN.md:172-180, 207-211`](file:///home/frank/Projects/Thinkspace/review-loop/borders-connectors/PLAN.md#L172-L180).

---

#### Finding 3: Picture border is ignored by `attachTargetAt`, preventing dropping arrow ends on picture borders (Rule B11)
* **Severity:** MEDIUM
* **Scenario:**
  1. Frank applies a 20 px border to a screenshot or cut-out picture.
  2. Under Rule B11: "Clicking a border selects the object; the border also counts for dropping arrow ends."
  3. Frank draws an arrow (or drags an arrow end) and drops it on the picture's outer border band.
  4. The plan defines `EditorController.attachTargetAt`:
     `- picture: an opaque pixel is under p, by the existing alpha mask (a cut-out's transparent parts don't count);`
  5. The border sits outside the source image's pixel bounds (or outside the cutout opaque silhouette). The alpha mask at `p` is 0 (or out of bounds).
  6. `attachTargetAt` returns null (or selects an object underneath the border), leaving the arrow end detached or attached to the wrong background object.
* **Code checked:** [`PLAN.md:119-129`](file:///home/frank/Projects/Thinkspace/review-loop/borders-connectors/PLAN.md#L119-L129), [`lib/model/scene.dart:240-260`](file:///home/frank/Projects/Thinkspace/lib/model/scene.dart#L240-L260) (`ImageObject.hitTest`), [`LEDGER.md:86-87`](file:///home/frank/Projects/Thinkspace/review-loop/LEDGER.md#L86-L87) (Rule B11).

---

#### Finding 4: Stroke thickness of rectangles and ellipses (`ShapeObject`) is omitted in outline intersection, burying arrow tips (Rule C2)
* **Severity:** MEDIUM
* **Scenario:**
  1. Frank draws a rectangle or ellipse with a thick stroke (e.g. 16 px).
  2. Under Rule C2: "On text, rectangles, ellipses and markers, the end rides the outline... With a border, it touches the border's outside."
  3. Frank connects an arrow to the rectangle.
  4. The plan states in `relink` step 5: "Intersect that ray with the target's outline grown by its border width (rotated rectangle, ellipse, or marker circle)".
  5. In [`lib/model/scene.dart:460-463`](file:///home/frank/Projects/Thinkspace/lib/model/scene.dart#L460-L463), `ShapeObject` does not have a `borderWidth` field; its visual thickness is `strokeWidth`, which is drawn centered on the shape edge and extends `strokeWidth / 2` outside.
  6. Because `ShapeObject` has no border width, the ray intersects the bare geometric edge, burying the arrowhead by `strokeWidth / 2` (8 px) into the visible stroke.
* **Code checked:** [`PLAN.md:153-157`](file:///home/frank/Projects/Thinkspace/review-loop/borders-connectors/PLAN.md#L153-L157), [`lib/model/scene.dart:460-470`](file:///home/frank/Projects/Thinkspace/lib/model/scene.dart#L460-L470) (`ShapeObject.bounds`), [`lib/editor/render.dart:269-276`](file:///home/frank/Projects/Thinkspace/lib/editor/render.dart#L269-L276) (`_paintShape`).

---

#### Finding 5: Degenerate case rule in `relink` causes attached ends to jump to the top edge when connected objects overlap
* **Severity:** MEDIUM
* **Scenario:**
  1. Frank places a step marker ([`BadgeObject`](file:///home/frank/Projects/Thinkspace/lib/model/scene.dart#L544-L608)) or a text label inside or overlapping a container rectangle, and draws an arrow between them.
  2. The anchor of the badge/label (its center) is located inside the rectangle's outline.
  3. `relink` step 5 specifies:
     "Degenerate cases. If the other anchor is inside the outline, or the same as the centre, the end sits at the outline point straight above the centre."
  4. The rectangle's attached end immediately snaps to the top-center edge of the rectangle, even if the marker sits in the bottom-right corner.
  5. Similarly, when drawing an arrow starting from inside a shape, until the cursor leaves the shape's bounds, the start end is pinned straight up instead of aiming at the cursor.
  6. A ray from the center through the anchor has a well-defined direction whenever `anchor != center`; jumping to `(0, -height/2)` is only necessary when `anchor == center`.
* **Code checked:** [`PLAN.md:158-160`](file:///home/frank/Projects/Thinkspace/review-loop/borders-connectors/PLAN.md#L158-L160) (`relink` degenerate cases).

---

### 2. What is bigger than needed (What to cut)

#### Cut `anchorBend` from the document model and schema
* **Why:**
  1. **Mathematically false premise:** PLAN.md (lines 161–167) justifies `anchorBend` by stating: *"the drawn curve is the anchor-chord quadratic cut at the two outline crossings, and a piece of a quadratic is an exact quadratic."*
     This is mathematically incorrect: the quadratic Bézier curve over the anchor chord does *not* cross the outline at the ray intersection point $p_1$ (the curve bends away from the tangent ray $A_1 \to C$). Furthermore, under Frank's revision of C6, a curved connector can have **one** end attached to an outline and the other pinned to a picture. In that case, there is only one outline crossing, so cutting at "the two outline crossings" does not apply.
  2. **Unnecessary persistent state:** Storing both `bend` and `anchorBend` creates two competing sources of truth for a curve. Old files have `bend` but no `anchorBend`, requiring unstated fallback rules.
  3. **Interaction vs Document state:** Solving for the curve passing through the pointer at parameter $t$ during dragging ([`CanvasInteractor._doBend`](file:///home/frank/Projects/Thinkspace/lib/editor/interactor.dart#L620-L633)) is strictly a gesture-time solver problem. Once the user releases the bend handle, the resulting quadratic curve is fully defined by `p1`, `p2`, and `bend` (which [`LineObject`](file:///home/frank/Projects/Thinkspace/lib/model/scene.dart#L680-L745) already stores). When targets move, deriving the quadratic curve control point from the line endpoints and `bend` maintains consistency without persistent `anchorBend` state.
* **Is `attachTargetAt` also too big?** No. `attachTargetAt` is strictly necessary because [`objectsAt`](file:///home/frank/Projects/Thinkspace/lib/editor/controller.dart#L856-L867) skips locked layers and locked objects, whereas Rule C11 explicitly allows attaching to locked objects, and Rule C15 requires pass-through inside unfilled shapes.

---

### 3. What in the plan is sound

The data model for borders (`Framed` mixin, default values, backward-compatible JSON encoding without format version bump), the visual rendering and downward shadow calculation in [`render.dart`](file:///home/frank/Projects/Thinkspace/lib/editor/render.dart), replacing `bounds` with `paintBounds` for render buffers and `contentBounds`, and the batch-remapping logic for copy/paste/duplicate/unmerge are all sound and preserve existing file compatibility.
