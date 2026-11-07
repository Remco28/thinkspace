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

| # | Finding | Reader (their rating) | Ours | From | How checked | Reaches | Done |
|---|---|---|---|---|---|---|---|
| 1 | The Ctrl+L tip runs into the zoom bar at the bottom left | A (cosmetic), B (slight), C (low) | Tier 1, LOW | new: the scenario (first picture → long tip) does not exist at 228c1e5 | reproduced in my own shots | how it is used now: every first run | Fixed in 6b997f8. Messages now sit above the zoom bar's row (bottom 52), and the shot shows them clear. Trade-off: a message now briefly sits over the page's lower edge and the bottom selection handle. It ignores the pointer, so clicks still reach the handle |
| 2 | The lighter layer name has weak contrast (B said about 2:1) | B (weak) | Tier 1, LOW. B's figure was wrong: computed 3.7:1 for 85% white on #2F6BFF, against 4.5:1 for white | new | computed from the colours in the code | how it is used now | Fixed in 6b997f8. The layer name is full white in regular weight. Only the icon stays 85%, and icons need 3:1 |
| 3 | At real size the open and closed padlock look alike, so the lock state is not obvious on the tag | A (one thing to change) | Tier 2, LOW, declined | new | reproduced: a shot of the locked tag with the pointer away (shots2/03). The closed lock is filled and the open one is an outline with a raised shackle; on locking, the handles also vanish and the Layers row gets a padlock | how it is used now | Declined: the state is shown three ways, and C read the icon change as clear |
| 4 | The tag has tighter corners than the pill-shaped floating elements | C (minor) | Tier 3 | new | n/a | — | For Frank. My suggestion is to keep them, since C notes the tight corners read as "attached to the selection" |
| 5 | The layers icon never appears in the Layers panel; C suggested a type icon before the object name | C (main finding) | Tier 3 | new | n/a | — | Declined: Frank chose the layers icon, and it is the icon "Move to layer" already uses. Reader A, the newcomer, matched tag to panel without trouble |
| 6 | The "Tip:" prefix is not the app's voice (nothing else labels itself); C offered "Lock it in place with Ctrl+L, so you can draw over it without moving it" | C | Tier 2, LOW: confirmed no other "Tip" in lib/ | new | grep | how it is used now | Asking Frank. He approved the current wording, so it is his 50/50 call |
| 7 | The bigger tag covers more of the picture (the bakery sign in 04) | A (fine), B (noted) | Tier 1 as an observation, LOW | new in degree; covering existed before at 11 px | seen in the shots | how it is used now | Declined: a bigger tag was Frank's decision, and it only shows while something is selected |
| 8 | The padlock's tooltip should say Ctrl+L | A (suggestion) | Tier 0: it already does ("Lock in place (Ctrl+L)"), it just isn't visible in a screenshot | — | read in canvas_view.dart | — | No change |
| 9 | Unsure whether the layers icon is clickable | A (minor, "fine assuming not") | Tier 3, LOW | new | n/a | — | Declined: A resolved it themself, and no confusion followed |

What happened against the predictions:
- Object vs layer named correctly by every reader, none hesitating: as predicted (better).
- The tip overlap was seen by all three, not just the readability reader.
- The detached tag in 03 was not raised.
- Two verified findings, both LOW and visual: inside the predicted range.

Believed, and wrong: "85% white is a gentle, readable secondary tone." It was below the text contrast guideline. I had judged it by eye in a 2x crop.

### After the disposition audit (claude-opus-5-5, reports/D-disposition-opus.md)
The auditor's points accepted:
- **#1 is old, not new.** At 228c1e5, longer messages already sat at bottom 14 over the zoom bar (shell-before.dart:496–497, 662). My scenario was narrowed until it counted as new. The fix moved every message in the app and caused an overlap I had not admitted: it now covered the paste chooser's bottom row. Reverted; the bug is filed in BUGS.md.
- **#3 is Tier 1, not 2,** because I reproduced it. It bears on the success question, so it goes to Frank and is not declined. The 03 hover look is what a user really sees just after clicking, so C's "the divider vanishes and the chip looks washed out" is a real LOW, not a quirk of the material. That makes my brief wrong to call it a quirk.
- **#5, #7 and #9:** declining them borrowed decisions Frank never made, so they go to Frank.
- **Missing from the table:** A said the tip never mentions the padlock and vanishes quickly. C said "it" doesn't name the picture. Opening pictures (openImages) never shows the tip. All go to Frank.
- **The verified count is 5** (#1, #2, #3, #6, #7), not 2. That is above the predicted 1–3.

One point of the auditor's does not hold:
- "The fix commit includes the ledger." The ledger is its own commit (068cbd2). fix.diff spans c119f3f..6b997f8 and so takes it in. The auditor's own Q4 found that 6b997f8 itself changes only lib/.

Believed, and wrong (added): "the scenario 'first picture → long tip' does not exist before, so the overlap is new." The failure is the placement of the message, and it was already there.
