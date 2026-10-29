# Record: light review of "picking a drawing tool shows its settings"
*Kept by the review-loop skill (light review). Safe to delete this folder once the work is done.*

Reviewing: a change, from `a6a8103`; change commit `09782a1`. Old bugs filed in: none found.
Decision confirmed with: Frank, 2026-10-29 (in chat).

## Checks (step 0 and step 3)
- format, analyze: clean. `flutter test`: 321 passed.
- New test fails on the code before the change (`Expected: empty, Actual: ['b']`), passes after.
- Used once in the headless app: drew an arrow, picked the arrow tool again; the
  panel showed "New arrow" with "Reset to default", the arrow unselected.

## Peer step
Skipped: no stored or computed data changes. Second opinion (fix auditor, Sonnet): holds,
"slightly overstated": the real risk was tools that act on the selection (Cut out), which
the change exempts and tests.

## Fix auditor (Sonnet 5.5, read the diff and code; did not run tests)
Every route to a tool (toolbar, keys, Hide, context menu, image panel, cut-out card,
inspector) goes through `setTool`; all behave as the plan says. No HIGH or MEDIUM.

| Finding | Reviewer (rating) | Ours | From | How checked | Done |
|---|---|---|---|---|---|
| A tool key pressed by accident drops a multi-selection | LOW, "intended" | LOW | new | read | Declined: the behaviour Frank chose. Second opinion: see below |
| With a locked tool, clicking an object may select it | LOW, pre-existing, "did not check" | none | n/a | read `interactor.dart` pointerDown: drawing tools go to their own `_downX`, none selects | Declined: not a fault. Second opinion: see below |

Second opinion on both declines (same fix auditor, sent back once): both hold; it
withdrew the locked-tool point after reading `pointerDown`.

## Outcome
No HIGH, no MEDIUM, no old bugs, nothing to fix. The light review stayed light: no HIGH,
the plan did not grow, and the decision was Frank's.

## Cleanup
Removed the reviewer's scratch copy (`/tmp/claude-review-copy`, a git worktree) and the
headless app's temporary data folder and screenshots. This folder is the record.
