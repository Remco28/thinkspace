# Rules reader, round 4 (Claude subagent, fresh; merge only; real app + scratch tests)
B12, B13, H1, B6: PASS. Everyday case (screenshot "pass: SECRET99", Hide box, arrow on top; merge screenshot+arrow): password stays hidden; box opacity 0 → no pixel changes (painted in); merged picture dragged 200 px → still hidden; merge/move/switch off/unmerge/delete original/undo/redo → never shows. Unmerge leaves two boxes (by design). No merge path removes a Hide box.
FAIL — MEDIUM: edits made while a merge renders (2.8 s for 3800×2400; input not blocked) are thrown away: a Hide box moved during the merge → cover painted at the old spot, merged picture on top of the moved box → new spot unhidden in export; an arrow deleted during the merge came back. Visible, one undo.
LOW: B13 refusal uses bounding boxes: a label inside a diagonal arrow's box but clear of the line and screenshot is refused.
LOW: locked object between the parts: message says "Select it too", which can't help.
LOW: box switched on but its layer hidden: message says "switched-off … Switch it on".
LOW: screenshot + Hide box only: M says "Nothing to merge: select two or more things that are visible and unlocked".
LOW (older): merged picture slightly softer at edges (fractional size rounded up, resampled).
Outside the rule: hidden ordinary objects between the parts don't stop a merge; switched back on, they end up under the merged picture (Frank's call).
