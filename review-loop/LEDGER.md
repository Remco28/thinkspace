# Review-loop ledger: the selection name tag and the Ctrl+L tip
*Kept by the review-loop skill. Safe to delete this folder once the work is done.*

Success question: Looking at a selected object, can someone new to Thinkspace read the tag at its real size, tell the object's name from its layer's name, and come away knowing that the padlock or Ctrl+L locks the object in place?
Rules confirmed with: Frank, 2026-11-07 in chat. A layers icon marks the layer name (not the word "in"). The tag is bigger. The one-time tip appears with the first picture placed on the page. Only object locking is in scope; layer locking stays as it is.
Reviewing: a change, from 228c1e5 to c119f3f (branch tag-and-lock-tip). Old bugs are filed in BUGS.md (none exists yet).
Scope: visual only (readability, design coherence, clarity), as Frank asked. One pass. Frank decides any 50/50 calls.
Stakes: a single user (Frank) and anyone he shows the app to. A failure costs a moment of confusion, not data or work. Stop after one pass.

## Round 1, 2026-11-07, c119f3f
Predictions (written before the round):
- Readers will name the bold text as the object and the icon text as the layer. At most one will hesitate.
- The tip toast running into the zoom bar at the bottom left is likely to be noticed by the readability reader. I saw it myself in the shots.
- The tag in 03 (locked) floats well above the picture. The rotate handle is hidden but the gap is kept. Someone may call that a detached label.
- Expect 1 to 3 verified findings, all LOW or MEDIUM and visual.
Cast:
- A, newcomer: claude-opus-5-5, given the screenshots.
- B, readability: codex gpt-6-luna, given the screenshots attached.
- C, design coherence: claude-sonnet-5-5, given the screenshots.
- The disposition auditor, claude-opus-5-5, runs after the sorting.
