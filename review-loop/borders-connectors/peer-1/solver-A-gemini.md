Working on Thinkspace within Agent Office (antigravity-9825).

Here is the design for **Borders** and **Connectors** tailored to Thinkspace’s architecture and priorities.

---

### 1. Document Storage and Backward Compatibility

#### Borders (B1, B8, B9)
Store border and shadow attributes directly on [`ImageObject`](file:///home/frank/Projects/Thinkspace/lib/model/scene.dart#L200) and [`TextObject`](file:///home/frank/Projects/Thinkspace/lib/model/scene.dart#L332):
```dart
int? borderColor;    // null or 0 = none
double borderWidth;  // default e.g. 3.0
bool shadow;         // default false
```

- **JSON Serialization:** In `toJson()`, emit these fields only when a border or shadow is active (`if (borderColor != null && borderColor != 0) ...`).
- **Old Files in New Builds:** Old `.thinkspace` files lack these keys; `fromJson()` defaults `borderColor` to `null` and `shadow` to `false`, preserving exact pixel-identical rendering with zero migration needed.
- **New Files in Older Builds:** In [`SceneObject.fromJson`](file:///home/frank/Projects/Thinkspace/lib/model/scene.dart#L50), unknown JSON keys are ignored during deserialization. Older builds will open the file without error.

#### Connectors (C1, C2, C3, C14)
Keep [`LineObject`](file:///home/frank/Projects/Thinkspace/lib/model/scene.dart#L680) as the single source of truth for line geometry. In the file and in memory, `p1` and `p2` **always store the evaluated, actual page coordinates**.

Store attachment metadata as optional fields on `LineObject`:
```dart
class Attachment {
  final String targetId;
  /// For images (C3): normalized local offset in the image's coordinate space ([-0.5, 0.5]).
  /// For outline riders (C2: text, rect, ellipse, badge): null.
  final Offset? pin; 
}

Attachment? attachStart;
Attachment? attachEnd;
```

- **Serialization:** Only write `attachStart` and `attachEnd` when present:
  ```dart
  if (attachStart != null) 'attachStart': {'target': attachStart!.targetId, if (attachStart!.pin != null) 'pin': [attachStart!.pin!.dx, attachStart!.pin!.dy]},
  ```
- **Old Files & Older Builds:** Older builds read and write `p1`, `p2`, and `bend` as an ordinary line and ignore the attachment metadata. Older files open with `attachStart == null && attachEnd == null`.
- **Integrity Guarantee:** Because `p1` and `p2` always hold the true coordinates on disk, an exported image or an older build opening the file will never render a dangling line at `(0, 0)` or point at the wrong spot.

---

### 2. Keeping Line Ends in Step Across Document Changes

#### Architectural Strategy: Centralized Resolution
Rather than scattering ad-hoc mutation logic across dozens of editing sites, introduce a single coordinator method on [`Document`](file:///home/frank/Projects/Thinkspace/lib/model/scene.dart#L946) / [`EditorController`](file:///home/frank/Projects/Thinkspace/lib/editor/controller.dart#L35):

```dart
void resolveConnectors({Set<String>? movedTogetherIds})
```

For every [`LineObject`](file:///home/frank/Projects/Thinkspace/lib/model/scene.dart#L680):
1. **Target Lookup:** Resolve `target = doc.objectById(attachment.targetId)`.
   - If `target == null`: clear the attachment (Rule C8: turning deleted targets into free lines).
   - If target is hidden or on a hidden layer: freeze the end in place (Rule C11).
   - If both the target and the line are in `movedTogetherIds`: skip re-projecting that end (Rule C7: moving the group rigidly preserves the relative layout).
2. **Endpoint Calculation:**
   - **Pinned Picture (C3):** Transform `target.center + rotateOffset(pin.scale(size), target.rotation)` (respecting `target.flipX`).
   - **Outline Rider (C2):** Ray-cast from target center towards the other endpoint (or towards [`LineObject.control`](file:///home/frank/Projects/Thinkspace/lib/model/scene.dart#L736) if curved), intersecting the target's geometric boundary inflated by its `borderWidth`.
3. If both ends are outline riders, resolve the chord angle iteratively (1–2 passes) or directly via their center-to-center line.

#### Code Paths Identified and Where `resolveConnectors` Hooks In:
- **Interactive Dragging (`interactor.dart`):**
  - [`_doMove`](file:///home/frank/Projects/Thinkspace/lib/editor/interactor.dart#L516): passes `movedTogetherIds = c.selection.toSet()`. Connectors whose target moved but the line didn't will follow live.
  - [`_doResize`](file:///home/frank/Projects/Thinkspace/lib/editor/interactor.dart#L536) & [`_doRotate`](file:///home/frank/Projects/Thinkspace/lib/editor/interactor.dart#L584): attached connectors update live as the object is scaled or turned.
- **Nudge & Alignment (`controller.dart`):**
  - [`nudge`](file:///home/frank/Projects/Thinkspace/lib/editor/controller.dart#L1182) and [`alignSelection`](file:///home/frank/Projects/Thinkspace/lib/editor/controller.dart#L1100): invoke `resolveConnectors` inside the `transact` block.
- **Properties & Sliders (`controller.dart`):**
  - [`editSelected`](file:///home/frank/Projects/Thinkspace/lib/editor/controller.dart#L1193) & [`liveEditSelected`](file:///home/frank/Projects/Thinkspace/lib/editor/controller.dart#L1205): invoked as sliders move (size, rotation, width) or when buttons flip/rotate.
- **Text Changes (`controller.dart`):**
  - [`updateEditingText`](file:///home/frank/Projects/Thinkspace/lib/editor/controller.dart#L1290) & [`finishTextEdit`](file:///home/frank/Projects/Thinkspace/lib/editor/controller.dart#L1297): text height re-measures; `resolveConnectors` adjusts any lines riding the text box.
- **Deletion & Sweeping (`controller.dart` & `interactor.dart`):**
  - [`deleteSelection`](file:///home/frank/Projects/Thinkspace/lib/editor/controller.dart#L1154), [`deleteLayer`](file:///home/frank/Projects/Thinkspace/lib/editor/controller.dart#L1060), and [`finishRemove`](file:///home/frank/Projects/Thinkspace/lib/editor/controller.dart#L782): detaches lines pointing to deleted objects into free lines where they sit (C8, C13).
- **Duplicate & Paste (`controller.dart`):**
  - [`duplicateSelection`](file:///home/frank/Projects/Thinkspace/lib/editor/controller.dart#L1166) & [`pasteObjects`](file:///home/frank/Projects/Thinkspace/lib/editor/controller.dart#L1801): when cloning objects, map `oldId -> newId`. If both target and connector are cloned together, point the cloned connector to the cloned target. If the connector is duplicated/pasted alone, clear its attachments to make it a free line (C9).
- **Merge & Unmerge (`controller.dart`):**
  - [`flattenSelection`](file:///home/frank/Projects/Thinkspace/lib/editor/controller.dart#L1843): clear attachments for any lines attached to the merged items (C10). Merged items preserve borders in [`MergeRecord.parts`](file:///home/frank/Projects/Thinkspace/lib/model/scene.dart#L154) (B6).
- **Undo / Redo (`controller.dart`):**
  - [`_restore`](file:///home/frank/Projects/Thinkspace/lib/editor/controller.dart#L523): snapshots captured by [`_capture`](file:///home/frank/Projects/Thinkspace/lib/editor/controller.dart#L508) already serialize `p1`, `p2`, and attachment states. Restoring JSON automatically brings back the exact consistent state without extra calculations.
- **Pre-Export / Pre-Save Verification:**
  - Before [`exportPng`](file:///home/frank/Projects/Thinkspace/lib/editor/controller.dart#L1819), [`copyPageToClipboard`](file:///home/frank/Projects/Thinkspace/lib/editor/controller.dart#L1830), and [`projectJson`](file:///home/frank/Projects/Thinkspace/lib/editor/controller.dart#L2446), a final `resolveConnectors()` runs so an export never has an arrow pointing at stale coordinates.

---

### 3. Drag Interactions in `lib/editor/interactor.dart`

1. **Attaching & Target Highlight (C4):**
   - In [`_doLineEnd`](file:///home/frank/Projects/Thinkspace/lib/editor/interactor.dart#L598) and line creation in [`_doCreate`](file:///home/frank/Projects/Thinkspace/lib/editor/interactor.dart#L644):
     If `!m.ctrl`, query candidate targets under the pointer using a new helper `c.connectorTargetAt(p)`.
     *Note:* Unlike [`objectsAt`](file:///home/frank/Projects/Thinkspace/lib/editor/controller.dart#L856), this helper checks locked objects (C11), skips hidden layers, and only matches images, text, rects, ellipses, and badges.
   - If a target is found:
     - Set `c.hoverAttachTarget = target` so [`CanvasPainter._paintOverlays`](file:///home/frank/Projects/Thinkspace/lib/editor/canvas_painter.dart#L79) lights up its outline.
     - **Attaching beats grid snapping:** bypass `_snapPoint(p, m)`.
2. **Detaching (C5):**
   - When dragging an attached handle into empty space (no candidate under the pointer, or `m.ctrl` is pressed): set `c.hoverAttachTarget = null`. On [`pointerUp`](file:///home/frank/Projects/Thinkspace/lib/editor/interactor.dart#L808), the line end detaches to a free line.
3. **Midpoint Bending vs Moving (C6, C7):**
   - In [`_downSelect`](file:///home/frank/Projects/Thinkspace/lib/editor/interactor.dart#L247): when clicking a line, check if either end is attached.
   - If attached, and the line is **not** part of a multi-selection with its targets (C7): dragging the line body switches mode to `_Mode.lineEnd` targeting [`HandleKind.lineBend`](file:///home/frank/Projects/Thinkspace/lib/editor/controller.dart#L876) instead of `_Mode.move`. Dragging the middle immediately bends the line via [`_doBend`](file:///home/frank/Projects/Thinkspace/lib/editor/interactor.dart#L620).

---

### 4. Where Borders and Shadows Must Be Accounted For Outside Painting

Rule B7 states: *"Aligning, snapping and the size boxes use the object's own edge, not the outside of its border."*
Therefore, keep [`SceneObject.bounds`](file:///home/frank/Projects/Thinkspace/lib/model/scene.dart#L34) as the intrinsic geometric bounds, and add a separate `visualBounds` (or `extentBounds`) property for rendering and clipping boundaries:

1. **`saveLayer` Rectangles in [`render.dart`](file:///home/frank/Projects/Thinkspace/lib/editor/render.dart#L112):**
   Faded objects and semi-transparent objects use `canvas.saveLayer(o.bounds.inflate(4), ...)`. A wide border or soft shadow will be clipped unless inflated to cover `o.visualBounds` (including shadow blur radius + offset).
2. **Selection / Clipboard Image Renders in [`controller.renderObjects`](file:///home/frank/Projects/Thinkspace/lib/editor/controller.dart#L1768):**
   `unionRects(objs.map((o) => o.bounds)).inflate(2)` calculates the image dimensions for copying the selection to the clipboard. It must use `visualBounds` so the border and shadow are not clipped at the image edges.
3. **Merge Bounds in [`controller._flattenSelection`](file:///home/frank/Projects/Thinkspace/lib/editor/controller.dart#L1861):**
   Flattening computes the canvas slice using `unionRects`. It must measure `visualBounds` so borders and shadows bake cleanly into the new merged asset.
4. **Hide Details Box Overlap in [`render._paintHide`](file:///home/frank/Projects/Thinkspace/lib/editor/render.dart#L180):**
   Hide boxes filter objects using `o.bounds.overlaps(area)`. An object whose border or shadow reaches into the Hide box must be detected using `visualBounds`.
5. **Connector Outline Intersections (C2):**
   When computing intersection points for connectors riding text or shape outlines, the contact point must be shifted outward by `borderWidth`.
6. **Hit-Testing on Borders:**
   [`SceneObject.hitTest`](file:///home/frank/Projects/Thinkspace/lib/model/scene.dart#L36) should accept clicks on the drawn border so clicking a thick border selects the object instead of clicking through to the canvas underneath.

---

### 5. Ambiguities, Conflicts, and Edge Cases

1. **Curve Tangent vs "Aiming at the Bend" (C2 vs C6):**
   - *Conflict:* Rule C2 specifies: *"aiming at the other end (or at the bend, if curved)."* In a quadratic Bézier curve, the tangent at $p_1$ points directly toward the **control point** ($C = 2 \cdot \text{mid} - \frac{p_1 + p_2}{2}$), **not** toward `mid`.
   - *Resolution:* The outline intersection ray must aim towards `control`. If it aimed at `mid`, the curve would visibly bend away from the contact point with an awkward kink.
2. **Cutouts and Transparent Pixel Hit-Testing (C1, C3 vs C4):**
   - *Ambiguity:* [`ImageObject.hitTest`](file:///home/frank/Projects/Thinkspace/lib/model/scene.dart#L240) ignores transparent cutout pixels so users can click through them. Does dropping a connector over a transparent cutout area attach to the image?
   - *Resolution:* Target detection should follow `hitTest`: only opaque pixels attach. Dropping over transparent cutout areas should pass through to objects below or remain a free line.
3. **Partial Group Dragging (C7):**
   - *Case Left Open:* What happens if Object A and the connector are selected, but Object B (attached at the other end) is not?
   - *Resolution:* End A moves with Object A, while End B stays pinned to unmoved Object B (the line stretches). Rule C7's *"just moves everything"* applies specifically to the endpoints whose attached targets are also part of the moving selection.
4. **Scope of "Give all pictures this border" (B5):**
   - *Ambiguity:* Does this button affect locked objects or pictures on locked/hidden layers?
   - *Resolution:* Consistent with Thinkspace conventions ([`removable`](file:///home/frank/Projects/Thinkspace/lib/editor/controller.dart#L770), [`mergeable`](file:///home/frank/Projects/Thinkspace/lib/editor/controller.dart#L1920)), it should only apply to pictures that are unlocked and reside on unlocked, visible layers.
