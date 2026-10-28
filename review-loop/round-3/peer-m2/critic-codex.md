## 1. H1: there is a real leak

**HIGH severity:** a Hide box above the highest part is outside the design’s “between” range, so it is neither painted into the merged picture nor moved with it.

Concrete case: a screenshot has a Hide box over a password, and an arrow sits above both. Select and merge the screenshot and arrow. The Hide box stays above the merged picture, so the page still looks protected. Move the merged picture out from under the box, and the password appears: the merged bitmap contains the screenshot’s unpixelated pixels because the box was above the parts when they were flattened.

Undo restores the original arrangement. Redo restores the vulnerable merge. Unmerge after moving the picture also puts the parts in its moved slot, where they can remain outside the Hide box. A layer above the highest part can cause the same problem when turned back on.

Hide boxes **between** parts are safer: switched-on boxes are baked into ordinary merges, and the boxes left above the picture protect it when switched on later. A multiply merge leaves those boxes above the picture; moving the strokes does not reveal page details baked into the strokes, since the merge contains only the multiply parts.

## 2. What the design refuses or changes

- **MEDIUM — cross-layer merge refused:** Put the screenshot on a background layer, its Hide box on a privacy layer, and an arrow on an annotations layer. Selecting the screenshot and arrow triggers refusal because the between Hide box is on a different layer from the highest part. That’s a conservative limitation on a common layer-organizing workflow, not a B13 requirement.

- **MEDIUM — the arrow can become hidden:** In the common same-layer order, screenshot → Hide box → arrow, the merge is allowed. The bitmap paints the Hide box before the arrow, then the design moves the box above the merged picture. The Hide box now also pixelates the arrow where they overlap. Unmerge puts both parts below the box, so it does not restore their original layering. This is visible and recoverable by changing the box’s order, but can spoil an annotation.

- **LOW — extra hiding outside the merged area:** A Hide box can be larger than the selected parts. Moving it above the merged picture may also cover an intervening object that overlaps the box but not the parts’ combined area. That object escapes the refusal check, yet becomes hidden after the move. This is visible and recoverable.

The rule requiring refusal for a visible, overlapping non-part is consistent with B13. The above-highest leak is the serious gap: H1 needs to account for Hide boxes above the highest part too.

One implementation detail to keep in mind: the current context menu shows Merge whenever the selection is nonempty and is not a mergeable image, without checking `canMerge`. The proposed rule 8 would correct that. I read the repository only; no files were changed.
