## 1. Does the placement rule work?

Yes, for the stated rule. `mergeable` is ordered bottom to top across layers, so `ordered.last` is the highest merged part. Inserting the merged image at that part’s original index, minus selected parts below it in the same layer, preserves its slot after those parts are removed. Removing parts from other layers does not change that layer’s index.

- **Parts across layers:** The merged image goes in the layer of the highest part. Objects above that part stay above; objects below it stay below.
- **Everything on a layer:** The adjusted index becomes the start of the layer once its selected objects are removed. With no unselected objects there, the placement is sound.
- **Undo and redo:** Merge runs in one `transact`; history snapshots the document, selection, and current layer. Undo restores the pre-merge state, and redo restores the merged state. Selection and current layer can remain as they are now.

Relevant code: [`controller.dart`](/home/frank/Projects/Thinkspace/lib/editor/controller.dart:2068) and [`render.dart`](/home/frank/Projects/Thinkspace/lib/editor/render.dart:48).

## 2. Risks

- **HIGH — a Hide details cover can stop covering a merged part.** For example, layer order is lower to higher: selected object A, a Hide details box H, then selected object B. H covers A, while B is above H. The merged image is inserted at B’s position, so it is also above H; because the merge renders the selected parts without H, A’s pixels can show through where H used to hide them. That can expose details in an export. **This is already possible with the current append-to-top behavior; the proposed placement does not introduce it, but it does not fix it.** A Hide details box above *all* merged parts remains above the merged image and keeps covering them.

- **MEDIUM — unmerge cannot restore original stacking across layers.** For example, A is on a lower layer and X then B are on a higher layer. Merging A and B places the image at B’s slot; unmerging replaces it there with both parts, so A ends up above X, though it was below X originally. The merge record stores the parts’ order but not their original layers, and unmerge inserts them together in the merged image’s layer. This is an existing limitation of cross-layer merges.

I inspected the code read-only and made no changes. Agent Office could not start because its log is outside the read-only filesystem.
