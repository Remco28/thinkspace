The fix addresses both reported bugs, assuming “carried” includes a line with one attached end and one free end.

- **(a) Free end stays behind — fixed.** If the picture is aligned, the line moves by that picture’s shift. Its free end therefore keeps its position relative to the picture; relinking restores the pinned end.
- **(b) Mark widens the frame — fixed.** A carried mark is excluded from the frame, so the picture aligns as if the mark were absent. With just that picture and its marks selected, alignment is to the page.

### Other cases

| Case | Result and severity |
|---|---|
| Only carried lines plus their picture | **LOW / no apparent bug.** The picture is the only object counted for alignment, so it aligns to the page. Its marks follow by the picture’s shift, then their pins are restored. |
| Connector between two selected text boxes | **LOW / no apparent bug.** The connector is carried and omitted from the frame. The text boxes align; relinking puts both ends back on their outlines. For a curve, `anchorBend` keeps its bend relative to the anchors. |
| Mark pinned to two selected pictures that shift differently | **MEDIUM, visible and recoverable.** Relinking puts each end on its own picture, so the line can stretch or change direction as the pictures align. Its bend remains relative to the new line chord. This follows the pins, but may surprise someone expecting the mark to move rigidly. |
| Curved line | **LOW / no apparent new break.** Translation preserves its bend. For connectors, relinking uses the saved bend relative to the anchors. A two-picture mark can change its curve’s size or orientation when its pinned ends move differently, as above. |
| Locked objects in the selection | **MEDIUM, visible and recoverable.** Locked objects are excluded from the aligned set and frame. A selected unlocked line attached to a locked picture is therefore not carried by that picture. A pin may be removed and re-created at the line’s new endpoint; an edge-riding end will still snap to its outline. That behavior may surprise users, but is consistent with aligning only unlocked objects. |
| Undo | **LOW / no apparent bug.** `alignSelection` uses one `transact('align', ...)`; connector relinking happens as part of the edit’s finalization, so the alignment and resulting endpoint changes belong to the same undo step. |

Agent Office check-in could not run because its log is outside the read-only filesystem. I made no file changes.
