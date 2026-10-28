The change **fixes the reported bug**. `holdPins` decides which pins to keep from the IDs it receives, not from whether an object actually shifts. Including every selected, unlocked object means a selected picture counts as moving even when its alignment shift is zero. The mark stays attached, and `relinkConnectors` puts its endpoint back on that picture. The same applies to a connector with one end pinned to the selected picture: that end stays pinned while its other end follows the connector’s shift.

The main side effect is a **zero-shift selected line whose picture is not selected**. The new code holds and re-pins it even though it didn’t move. `repin` searches for the topmost picture under each endpoint, so if another picture overlaps the mark, the pin can silently switch to that picture—or be dropped if no picture is found.

- **Mark aligned on its own — MEDIUM, rare edge case.** If the mark already needs no shift, an overlapping picture can take its pin. If it shifts, behavior is unchanged.
- **Mark and an unrelated picture — MEDIUM, rare edge case.** If the mark needs no shift and another picture covers its endpoint when repinning happens, the mark can switch pins. With no such overlap, there’s no change.
- **Two pictures and a mark pinned to one — nothing wrong with the proposed fix under C7.** The mark stays with its selected picture, including when that picture’s shift is zero. Alignment may therefore leave the mark’s visible bounds out of line with the other selected objects; that follows from preserving the attachment. A one-ended pinned connector likewise keeps that end attached while its free end moves.

I could not start or peek at Agent Office: its log is outside the read-only filesystem, so no numbered run was available. No files were modified.
