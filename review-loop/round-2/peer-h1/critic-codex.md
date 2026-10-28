## 1. Does the plan keep every hidden pixel hidden?

**Not if implemented by simply passing `withCovers(mergeable)` into the existing merge code.**

`withCovers` matches most of the page rules: it visits objects in page order, includes visible Hide boxes on visible layers whose bounds overlap the selected area, and does not exclude locked boxes. It excludes hidden boxes and boxes on hidden layers, which have no effect on the page. Partly overlapping boxes are included; boxes below the first selected part are not, because they cannot hide that part.

The catch is that `withCovers` is built for copy. Its result includes unselected Hide boxes, but the merge code treats every item in that result as a selected part. In particular, it uses that list to choose the merge’s bounds, placement layer and undo record, and to decide what to remove. Those uses need to distinguish the selected parts from the boxes included to render their covers.

## 2. What could break?

- **HIGH — an unselected Hide box gets removed.** A box between selected parts or above them enters the list; the current removal loop would remove it along with the selected objects. A realistic case: merge two images with a Hide box over one, then find that the box no longer hides other page content. That is easy to miss and can expose details in the document and exports.

- **MEDIUM — unmerge puts the box back as a merge part.** If the box is recorded in `MergeRecord.parts`, unmerge restores it as part of the merged layer and also conflicts with the requirement to keep the original box where it is. It can be duplicated or change stacking. Undo of the merge should work because it restores the transaction snapshot, but **unmerge requires a clean distinction**: record selected parts, not render-only covers.

- **MEDIUM — the merged picture gets larger or lands on the wrong layer.** A partially overlapping Hide box can be much larger than the selected objects. Including it when calculating bounds expands the picture, and using `ordered.last` to pick the destination can put the picture on the Hide box’s layer instead of the highest selected part’s layer. The larger raster can also make a merge fail for unusually large boxes.

- **MEDIUM — covers above the merge can be applied twice.** A nonselected Hide box above the highest selected part stays in place, as requested, but is also baked into the picture. It then paints over that picture again. This should keep details hidden, but can change the mosaic appearance.

- **LOW — a merge involving only multiply highlights may change behavior.** If a render-only Hide box is included in the list, the existing `every(...)` check will set `multiply` to false. The saved picture may therefore no longer behave like a multiply highlight outside the covered region. It is visible and recoverable by unmerging, provided the Hide box was not incorrectly added to the undo record.

**Merging with no covers should look exactly as before** if the render list is identical to the current `mergeable` list. `withCovers` returns the selected objects in page order when it finds no qualifying Hide boxes, so that condition appears achievable.

The core safeguard is to keep two lists: selected merge parts for removal, bounds, placement and `MergeRecord`; and selected parts plus qualifying Hide boxes for painting. There is a further visual detail to decide: `paintObjects` renders a Hide box against only the objects in its supplied list, without the page background or unselected underlying objects. That will reproduce hiding of selected pixels, but may not match the original mosaic’s sampled appearance where other page content contributed to those tiles.

No files were modified. Agent Office’s `begin` and read-only `peek` both failed because its log is outside the read-only filesystem.
