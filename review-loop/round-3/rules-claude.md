# Rules reader, round 3 (Claude subagent, fresh; real app + scratch tests; old build 500f942 round trip)

No wrong arrow, no lost or damaged file. Old file (500f942) opens pixel-identical (max diff 0), re-saves without new keys; new file opens in the old build.
All rules PASS except B12 and H1.

A — MEDIUM (B12): things BETWEEN the merged parts end up underneath. Sample: Hide box over the window, a new arrow on the screenshot; select storefront_photo + new arrow; Merge → the merged picture takes the arrow's (top) place; label, pointer arrow and both awnings (above the photo, below the new arrow) are hidden under the opaque merged photo, canvas and export. Code does the rule's first half, breaks its purpose. The old behaviour did the same. Frank to decide what happens to unselected things between parts.
B — MEDIUM (H1): a Hide box switched off (or on a hidden layer) at merge time stops working when switched back on: it now sits under the merged picture; _withCoversBetween takes only visible boxes.
C — MEDIUM (H1 side effect, new): highlighter marks merged across a Hide box turn solid: `multiply: !covered && …` drops multiply when any box is painted in (4000/4000 px differ, up to 241).
D — LOW: right-click "Merge into one image" is offered for picture + Hide box (M key, button and panel refuse); it re-renders the picture alone and frees arrows pinned to it, with no "hidden details" message. H1's wording says boxes "over" the parts; only boxes between lowest and highest part are painted in (a box above stays on the page; no output exposes it).
LOW: Align tooltip says "Align left edges" for picture + its mark, but they align to the page now (the mark no longer counts).
LOW: merge+unmerge with a box between the parts leaves two boxes (original now below the screenshot, plus the copy); repeating piles them up. A solid box stays at the old spot if the merged picture is moved away.
Aside (older): non-integer selection bounds make a merge slightly rescale; fine text loses a little sharpness.
