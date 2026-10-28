## Dispositions that should change

The profile defines MEDIUM as a finding that is visibly wrong and recoverable; it also says visibility or recoverability alone never makes a finding LOW. On that rule, four LOW ratings are too soft:

- **P10 and R5 — cut-out/text shadows:** rate **MEDIUM**, not LOW. The shadow visibly violates B10; “cosmetic” and “easy to fix” do not justify LOW under the profile. These are the same mechanism across rounds, so they should have the same rating. See [the severity rules](</home/frank/Projects/Thinkspace/.claude/skills/review-loop/profiles/code-review.md:32>) and [the P10/R5 entries](</home/frank/Projects/Thinkspace/review-loop/LEDGER.md:114>).
- **F2 — curved connector changes shape when an end goes free:** rate **MEDIUM**, not LOW. The reported 8–16 px change is visible, occurs in ordinary delete, merge, or partial-copy sequences, and changes a connector’s shape. Calling it “a few pixels” doesn’t answer the profile’s visible-and-recoverable rule.
- **F4 — connector tip stops short at a rounded text-box corner:** rate **MEDIUM**, not LOW. The 4–8 px gap is a visible mismatch with the stated outline behavior. The corner-specific scenario may make it uncommon, but that still supports MEDIUM, not LOW.

The F2/F4 dispositions are in [round 1’s table](</home/frank/Projects/Thinkspace/review-loop/LEDGER.md:240>).

## Ratings and declines that hold

- **Peer 3 R1: MEDIUM is fair.** Hiding a target, moving its line, then showing it is an unusual sequence, and the consequence is visible on reveal. The reviewer’s HIGH is understandable because the attachment is silently lost while hidden, but the author’s MEDIUM fits the profile’s unusual-sequence category. The current code’s `repin` explicitly preserves a hidden target; see [controller.dart](</home/frank/Projects/Thinkspace/lib/editor/controller.dart:954>).
- **Round 1 F1: MEDIUM is fair.** It is common, but the failure is visible and undoable; that matches MEDIUM. The author recorded the commonness rather than using it to minimize the issue.
- **F3 and F5: LOW is fair.** F3 is a missing convenience in a mixed selection, with another way to edit the applicable objects. F5 writes an unnecessary width field when no border is set; the current serializer omits it unless a border exists, at [scene.dart](</home/frank/Projects/Thinkspace/lib/model/scene.dart:211>). Neither report describes a comparably wrong picture or lost work.
- **Declining `movedTogetherIds` is fair.** The reason checks out: the implementation keeps pins attached to pictures that move with the line, and relinking derives the endpoints from the translated anchors. That preserves the group’s relative geometry without a separate exception. See [holdPins](</home/frank/Projects/Thinkspace/lib/editor/controller.dart:929>) and [relinkConnectors](</home/frank/Projects/Thinkspace/lib/model/connect.dart:238>).
- **Declining relink-before-export/save is fair for normal app flows.** The current document is relinked on notifications and at edit completion; `exportPng` renders without mutating the document. Adding relink to export would violate the stated export boundary if it changed document data. See [controller lifecycle](</home/frank/Projects/Thinkspace/lib/editor/controller.dart:469>) and [exportPng](</home/frank/Projects/Thinkspace/lib/editor/controller.dart:1998>).
- **Declining to cut `anchorBend` is supported.** A blind solver independently proposed it, and both fresh pass-3 critics said to keep it. The reason is substantive: preserving a clipped curve through endpoint changes requires its anchor-relative bend; current relinking stores and uses that value in [connect.dart](</home/frank/Projects/Thinkspace/lib/model/connect.dart:244>).

## Were the author’s own items treated more gently?

**Yes, in the LOW ratings for visible defects.** P10/R5, F2, and F4 all concern behavior in the author’s implementation or plan, and the ledger’s reasons (“cosmetic,” “few pixels”) conflict with the explicit profile rule. Fixing these findings does not make their original ratings fair.

The `anchorBend` decision is not, by itself, evidence of gentle treatment: it was challenged and then backed by two fresh critics.

## Any finding missing from the ledger?

I found **no separate concrete failure scenario omitted entirely**. The reports’ other actionable items are represented in the ledger or resolved in the implementation. Peer 1’s broader painted-extent warnings, for example, are reflected in the `paintBounds` findings and the current rendering, copy, and merge paths. Some reports also contain open questions and design suggestions; those are not additional verified findings.

This was a read-only audit; I changed no files.
