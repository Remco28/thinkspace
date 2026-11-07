# Audit of the round-1 triage: selection tag and Ctrl+L tip

**Short answer:** the triage is softer than the ledger says. One origin label is wrong. The fix for finding 1 moves every message in the app and causes an overlap the ledger doesn't mention. Two declines lean on choices Frank never made. And the "two verified findings, both LOW" summary comes from the author's own uneven labelling: by the ledger's own rule there are five verified findings.

## Q3: "new" and "old" labels

**Finding 1 (the message runs into the zoom bar) is old, not new. Confidence: high.** In `shell-before.dart:969-971`, at 228c1e5, messages were already centred at `bottom: 14` over a zoom bar at left 8, bottom 8. Several messages from before the change are as long as the tip or longer, and they sit at the same spot:
- "Nothing to merge: select two or more things that are visible and unlocked" (`shell-before.dart:497`, about the same length)
- "Nothing to merge: Hide details boxes stay on the page, so select two or more other things" (`:496`, longer)
- "Drop images (PNG, JPG, WebP, GIF, BMP) or a .thinkspace project" (`:662`)

Reader C already said the overlap depends on how wide the page is, not on the message ("in 05 … sits clear … because the page is narrower"). The ledger's reason, "the scenario (first picture → long tip) does not exist at 228c1e5", narrows the scenario until it counts as new. What's true is that the bug is old and the tip makes it happen on every first run.

That label decided what happened next. By the rules, an old bug is filed, not fixed. Instead it was fixed by moving all ~45 messages in the app, which is outside this change and is a choice about what users see. No BUGS.md exists anywhere in `repo/`.

**Finding 7 (the bigger tag covers more of the picture): the label holds.** The tag's placement code is unchanged (`canvas_painter-before.dart:478-485`). Only its size grew: text 11 → 12.5, maximum width 260 → 300, padlock area 22 → 28. So covering existed before, and "new in degree" is fair. But the old part should then have been filed, and it wasn't.

## Q1: Do the declines hold?

**Finding 3 (open and closed padlock look alike) does not hold.**
- **Wrong tier.** The ledger says the author reproduced it (shots2/03), and by the stated rules a reproduced finding is Tier 1. Calling it Tier 2 is inconsistent and helps keep it out of the verified count.
- **Too low.** It bears directly on the third part of the success question ("come away knowing that the padlock … locks"). It was A's one recommended change. MEDIUM is defensible, and at MEDIUM it couldn't have been declined.
- **"C read the icon change as clear" is a convenient reason.** C judged screenshot 03, where the padlock has the hover fill behind it. C itself called the locked padlock "the loudest thing in the chip" there. The author's own pointer-away shot (z03 against z02) removes exactly that: what's left is a 16 px filled lock against an outline lock.
- **"Shown three ways" is partly real.** The handles do vanish. The Layers-row padlock only helps if the panel is open and the user looks there.

This should go to Frank, not be declined.

**Finding 5 (the layers icon never appears in the Layers panel) does not hold as written.** Frank chose a layers icon *instead of the word "in"*. He did not rule on C's actual suggestion, a type icon before the object's name to match the panel, or on whether the panel and the tag should share an icon. Also, the ledger rates it Tier 3, which by its own rules means "collected for the owner". Yet the Done column says "Declined", not "For Frank". The supporting point that reader A matched the tag to the panel is real (A §1).

**Finding 7 (tag covers the picture) does not hold.** "A bigger tag was Frank's decision" borrows his authority for a consequence he wasn't shown: in 04 the tag covers the top of the "CORNER BAKERY" lettering (`04-zoom-tag.png`). Size against coverage is exactly a 50/50 call for him.

**Finding 9 (is the layers icon clickable?) roughly holds, but the reason is overstated.** A didn't resolve it; A said "I'm fine *assuming* it isn't". The stakes are low. It is also Tier 3, so by the rules it goes to Frank rather than being declined.

## Q2: Ratings too gentle on the author's own choices

- **The verified count is wrong.** By the ledger's own rule ("the author reproduced or checked it"), findings 1, 2, 3, 6 and 7 are all verified. That is five, not two, and outside the predicted "1 to 3". The line "inside the predicted range" depends on finding 3 being called Tier 2 and finding 7 being called "an observation".
- **Finding 2 (contrast).** I recomputed it: 85% white on #2F6BFF is 3.69:1, and full white is 4.50:1. So the author's figures are right and B's "2:1" was wrong. But this was the author's own colour choice, it failed the guideline, and it bears on reading the tag at real size. Calling it LOW is gentle. It was fixed, so in practice only the scorecard benefits.
- **The pattern.** The checkable item (finding 1, the message overlap) was fixed, and on a global scale. Items about the author's design (the padlock state, the tag covering content, icon consistency) were all declined, two of them by citing Frank.

## Q4: Did fix.diff do what the ledger says?

**Finding 2 fix: does what it says.** The layer name is now full white in regular weight, and only the icon stays at 85% (3.7:1, above the 3:1 needed for icons). z02 and z03 confirm it.

**Finding 1 fix: works for the zoom bar, but has trade-offs the ledger doesn't admit.**
1. **New overlap with the paste chooser.** The chooser sits at `bottom: 56` (`shell.dart:963-965`). Messages now span roughly 52–84 px from the bottom, and they're drawn after the chooser in the Stack, so on top of it. Before, they spanned about 14–47 and never touched it.
   - What gets hidden: the chooser's bottom row, the "Always do this" checkbox (`shell.dart:1279-1293`).
   - When: any message that fires while the chooser is open, such as undo ("Undid …"), "Nothing to paste", or "Saved …".
   - IgnorePointer means clicks still go through; it's covered for about 3 s.
   - Severity: LOW, and unadmitted.
2. **The scope is understated.** The ledger says "a message now briefly sits over the page's lower edge". It is every message, and the tip itself now covers the bottom of the page for 6 s. That page is the picture the tip just invited the user to draw on, since the first picture is fit to the view. z01 also shows the message sitting right on top of the page-resize grip ("•••").
3. **The fix commit includes the ledger.** `fix.diff` adds `review-loop/LEDGER.md` to the project commit, though its header says the folder is safe to delete. I couldn't confirm it's in `repo/`, because there is no review-loop folder there.

## Q5: In the reports but missing from the table

- **A §3: the tip never mentions the padlock**, "so I wouldn't connect the two". This is the core of the success question ("the padlock *or* Ctrl+L"). It isn't in the table; finding 8 only covers the tooltip.
- **A §3: "Would I remember it? Maybe once. It vanishes after a few seconds."** Not in the table.
- **C §4: "it" in the tip doesn't name the picture.** Not in the table.
- **C §1 and §3: the locked chip looks washed out and the divider disappears in 03.** The readers were told the hover fill was "a known quirk", and C discounted it for that reason. But `_TagLock` (`canvas_view.dart:544-550`) is an InkWell with `hoverColor`. The tag also deliberately stays put so the padlock remains under the pointer (`canvas_painter-before.dart:479-481`). So the hover state in 03 is exactly what every user sees right after clicking the padlock. Treating it as a display artefact (Tier 0) is wrong. C's divider and washed-out points are real LOW findings, and the briefing steered them out.
- **Not raised by any reader (the readers only saw screenshots), but checkable in the code:** the tip only fires from `placeAsset`, which covers paste, drop and placing from the collection. Opening pictures (`openImages`, `controller.dart:2838-2900`, the workflow behind screenshot 02) builds the document directly, so it never shows the tip. Whether "placed on the page" was meant to include opening a picture is Frank's call.

## Q6: Put to Frank, not decided alone

1. Whether all messages move up to bottom 52, with its overlap of the page and the paste chooser, or the old overlap is filed instead (finding 1).
2. Whether the locked padlock needs a stronger look on the tag (finding 3).
3. Bigger tag against more of the picture covered (finding 7).
4. A type icon on the object name, and whether the tag and Layers panel should share an icon (finding 5, a Tier 3 item).
5. Whether the tip should mention the padlock and stay up longer (A, missing).
6. Whether opening a picture should trigger the tip.

Finding 6 ("Tip:") is already correctly with him.

## What I couldn't check

I didn't run the app or the tests. The overlap with the paste chooser is worked out from the layout constants, not seen in a screenshot. I didn't measure how wide the zoom bar gets when the pan hint shows.
