# Rules reader, round 2 (Claude subagent, fresh; real app via the inspector + scratch tests; built 500f942 to compare)

All rules PASS except C7/C16 under Align. Old files (three, incl. two found on this machine and one with every object type and a merge) render pixel-identical and re-save unchanged; a new file opens in the old build with lines in place. C4's hover highlight NOT CHECKED in the real app (the inspector's drag is one burst).

FAIL 1 — MEDIUM (C7/C16, Align): select a screenshot, a mark pinned on it, and a label; Align left. The screenshot (already leftmost) doesn't move; the mark gets its own shift and re-pins ~140 px away on the same screenshot. Align right (screenshot moves) keeps the mark on its spot. Cause: alignSelection counts only non-zero shifts as moving, so pins on an unmoved selected picture are lifted and re-placed. Visible, one undo fixes it.

Outside the rules, visible in an export:
1. Arrow tails start in empty space beside short labels without a backdrop: the click-made text box is 320 px wide, so an arrow from "Look here" to the right starts ~90 px past the last letter. Follows B4/C2 as written ("the text area").
2. Merging puts unselected arrows underneath: the merged picture goes to the top of its layer, so an arrow between a merged screenshot and label (not selected) disappears under it; unmerge doesn't bring it back on top. Pre-existing placement, but it now hits connectors.
Scratch: /tmp/claude-3645/r2/claude/test/zz_*_test.dart, scratch/ (incl. scratch/old).
