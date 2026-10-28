Working on Thinkspace within Agent Office (antigravity).

Here is the disposition audit of the review loop through Round 2, audited strictly against the profile rules in [`code-review.md`](file:///home/frank/Projects/Thinkspace/.claude/skills/review-loop/profiles/code-review.md), the stakes and rules in [`LEDGER.md`](file:///home/frank/Projects/Thinkspace/review-loop/LEDGER.md), the readers' reports, and the code at HEAD.

---

### 1. Which ratings or declines do not hold? (In particular: Round 2)

#### G5: Rating LOW does not hold — must be MEDIUM
* **Ledger disposition:** Fix auditor (LOW) $\to$ Ours: LOW ("edge case, visible, Ctrl or a drag away").
* **Why it does not hold:**
  1. **Direct violation of profile rule ([`code-review.md:51`](file:///home/frank/Projects/Thinkspace/.claude/skills/review-loop/profiles/code-review.md#L51)):** *" 'Visible' or 'recoverable' alone never makes a finding LOW."* The author’s recorded reason literally rests on "visible" and "Ctrl or a drag away" (recoverable).
  2. **Direct violation of precedence rule ([`code-review.md:42`](file:///home/frank/Projects/Thinkspace/.claude/skills/review-loop/profiles/code-review.md#L42)):** *"The same mechanism gets the same rating in every round. A past rating is a precedent; rating it lower needs a new reason."* In Round 1, **F4** (text box rounded corners ignored by connector ray exit) was ruled **MEDIUM** by the Round 1 auditor and accepted by the author ([`LEDGER.md:306-310`](file:///home/frank/Projects/Thinkspace/review-loop/LEDGER.md#L306-L310)). **G5** is the exact same mechanism in reverse: [`_withinOutline`](file:///home/frank/Projects/Thinkspace/lib/editor/controller.dart#L920-L932) inside [`attachTargetAt`](file:///home/frank/Projects/Thinkspace/lib/editor/controller.dart#L886-L928) ignored the rounded corner arc of text boxes. By precedent, it must be **MEDIUM**.
  3. **Consequence:** By rating G5 as LOW, the author fixed it in commit `988327c` without the mandatory peer review step required for all MEDIUM fixes ([`code-review.md:59`](file:///home/frank/Projects/Thinkspace/.claude/skills/review-loop/profiles/code-review.md#L59)), repeating the exact procedural breach admitted for F2 and F4 in Round 1 ([`LEDGER.md:311-314`](file:///home/frank/Projects/Thinkspace/review-loop/LEDGER.md#L311-L314)).

#### G2: Disposition "outside the rules / to Frank: a rule question" does not hold — it is a real MEDIUM finding
* **Ledger disposition:** Rules (outside the rules) $\to$ Ours: "MEDIUM: visible in exports. It follows B4/C2 as written $\dots$ to Frank: a rule question".
* **Why it does not hold:**
  1. The author claims it *"follows B4/C2 as written"*. This claim is contradicted by the confirmed text of **Rule B4** ([`LEDGER.md:36`](file:///home/frank/Projects/Thinkspace/review-loop/LEDGER.md#L36)):
     > *"B4. On a text box, the border goes around the backdrop box, **or around the text area if there is no backdrop**."*
  2. The code in [`outlineOf`](file:///home/frank/Projects/Thinkspace/lib/model/connect.dart#L43-L53) and [`_paintBorder`](file:///home/frank/Projects/Thinkspace/lib/editor/render.dart#L239-L254) completely ignores whether a backdrop exists. It always measures from `t.size` (which defaults to 320 px wide for click-created text boxes in [`CanvasInteractor._finishTextBox`](file:///home/frank/Projects/Thinkspace/lib/editor/interactor.dart#L1077)). When `background == 0`, the border and connector ends do not ride the text area; arrow tails float in empty air ~90–140 px away from the letters.
  3. This directly violates the project's **Stake #2** ([`LEDGER.md:23`](file:///home/frank/Projects/Thinkspace/review-loop/LEDGER.md#L23)): *"an exported picture whose arrow quietly points at the wrong spot"*. Calling it "outside the rules" and punting to Frank is an evasion of an implemented omission. It is a genuine code defect and must be tracked as **MEDIUM**.

#### Decline of solver’s alignment frame proposal (Peer Step G1) does not hold
* **Ledger disposition:** *"Declined from the solver: leaving such lines out of the alignment frame. That would change today's align results for lines that stick out, which nobody asked for."*
* **Why it does not hold:**
  In [`EditorController.alignSelection`](file:///home/frank/Projects/Thinkspace/lib/editor/controller.dart#L1214-L1262), the author included attached lines in `frame = unionRects(objs.map((o) => o.bounds))` but subsequently set `shifts[o] = Offset.zero` for lines attached to aligned objects. Checking this against the code reveals two failures:
  1. **Marks sticking out of a picture get double-translated:** The protruding mark expands `frame`, so the picture shifts to align with the mark's outer edge. The author zeroes the mark's shift (`shifts[o] = Offset.zero`). Then [`relinkConnectors`](file:///home/frank/Projects/Thinkspace/lib/model/connect.dart#L238-L290) shifts the mark *again* by the picture's movement. The mark overshoots the alignment boundary.
  2. **Free ends of one-ended connectors freeze in place:** In [`EditorController.alignSelection`](file:///home/frank/Projects/Thinkspace/lib/editor/controller.dart#L1246-L1253):
     ```dart
     if (o is LineObject &&
         o.attached &&
         (o.start == null || ids.contains(o.start!.to)) &&
         (o.end == null || ids.contains(o.end!.to))) {
       shifts[o] = Offset.zero;
     }
     ```
     For an attached line with one free end (e.g., `o.start` pinned to an aligned picture, `o.end == null`), `(o.end == null || ids.contains(o.end!.to))` evaluates to `true`! The author zeros `shifts[o]`, preventing `o.p2` from moving during alignment. This directly violates **Rule C16** (*"arrow keys and align move only its pinned and free ends"*) and breaks the explicit expectation in Codex's review ([`round-2/peer-g1/critic-codex.md:7`](file:///home/frank/Projects/Thinkspace/review-loop/round-2/peer-g1/critic-codex.md#L7): *"A one-ended pinned connector likewise keeps that end attached while its free end moves"*).

#### Stopping at Round 2 does not hold
* Under [`code-review.md:92-95`](file:///home/frank/Projects/Thinkspace/.claude/skills/review-loop/profiles/code-review.md#L92-L95), review loops may only stop after a round that has no HIGH and **needed no HIGH or MEDIUM fixes**. Round 2 required fixing G1 (MEDIUM), fixing G5 (MEDIUM), and leaves G2 and G3 unresolved. Round 2 cannot be the final round.

---

### 2. Are the stated reasons real, or convenient?

| Stated Reason / Claim | Disposition | Reality Check Against Code | Verdict |
|---|---|---|---|
| **G4 rejection:** *"killed by pixels: with a 10 px border, pixels 1–9 px out are border and 11 px out is page; the tip is at 10 px. The stroke is centred w/2 outside with width w, so it covers 0..w"* | Rejected | [`_paintBorder`](file:///home/frank/Projects/Thinkspace/lib/editor/render.dart#L239-L254) draws `box.inflate(w / 2)` with `strokeWidth = w`. Its inner edge is at distance 0 (the box boundary) and outer edge is at distance $w$. [`outlineOf`](file:///home/frank/Projects/Thinkspace/lib/model/connect.dart#L50-L52) returns $hw + w$. The arrow tip meets the exact outer border edge. Codex misread Flutter's stroke expansion. | **Real.** |
| **G5 rating as LOW:** *"edge case, visible, Ctrl or a drag away"* | Rated LOW | Bypasses explicit rule against using visibility/recoverability to downgrade, and ignores Round 1 precedent F4. | **Convenient.** |
| **G2 disposition:** *"follows B4/C2 as written"* | Punted to Frank | Directly contradicts Rule B4's fallback for backdrop-less text boxes. | **Convenient / False.** |
| **Declining solver's align frame proposal:** *"That would change today's align results for lines that stick out, which nobody asked for."* | Declined | Zeroing shifts while keeping the line in the frame causes double-translation of protruding marks and freezes free ends on callouts. | **Convenient / Flawed.** |
| **Peer 2 decline to cut [`anchorBend`](file:///home/frank/Projects/Thinkspace/lib/model/scene.dart#L698):** *"re-deriving each pass drifts, and drift makes phantom undo steps and dirty files"* | Retained | Verified in [`relinkConnectors`](file:///home/frank/Projects/Thinkspace/lib/model/connect.dart#L244) and [`refitBend`](file:///home/frank/Projects/Thinkspace/lib/model/connect.dart#L292). Re-projecting from endpoints without the stored anchor reference accumulates drift on repeated passes. Supported by both fresh critics in pass 3. | **Real.** |
| **Peer 1 decline of relink-before-export:** *"relink already runs on every notify and endEdit $\dots$ Export must not change the document"* | Declined | Verified in [`EditorController`](file:///home/frank/Projects/Thinkspace/lib/editor/controller.dart#L469): every mutating transaction relinks before committing. [`exportPng`](file:///home/frank/Projects/Thinkspace/lib/editor/controller.dart#L1998) is strictly a rendering pass. | **Real.** |

---

### 3. Were the author's own items treated more gently than checkable ones?

**Yes.**
1. **G2 (Text area without backdrop):** Fixing this properly requires dynamic layout measurement via [`TextPainter`](file:///home/frank/Projects/Thinkspace/lib/editor/render.dart#L301) to compute tight bounding geometry when `background == 0`. Because this was complex and required changes across [`connect.dart`](file:///home/frank/Projects/Thinkspace/lib/model/connect.dart) and [`render.dart`](file:///home/frank/Projects/Thinkspace/lib/editor/render.dart), the author framed it as a rule question for Frank rather than an implementation bug under Rule B4.
2. **G5 (`_withinOutline` rounded corners):** This was a direct oversight from the author’s own Round 1 fix for F4. When caught by the fix auditor in Round 2, the author rated it LOW using the forbidden "visible / easily recoverable" justification, avoiding the mandatory peer step for a MEDIUM fix.
3. **Peer Step G1 shortcut:** Rather than properly separating connected lines from the alignment bounding box in [`EditorController.alignSelection`](file:///home/frank/Projects/Thinkspace/lib/editor/controller.dart#L1214), the author used a quick `shifts[o] = Offset.zero` override, introducing new edge-case regressions for one-ended connectors and sticking-out marks.
4. This repeats the exact pattern from Round 1, where the author initially rated self-authored defects (P10, R5, F2, F4) as LOW using "cosmetic" and "a few pixels" justifications.

---

### 4. Does any reader report contain a finding the ledger does not record at all?

1. **No separate reader finding was omitted entirely from the ledger.** Every concrete failure reported across Peer 1–3 and Rounds 1–2 is represented in the ledger tables or narrative.
2. **However, findings in the Round 2 peer step were inappropriately minimized:**
   In [`round-2/peer-g1/critic-codex.md:5-6`](file:///home/frank/Projects/Thinkspace/review-loop/round-2/peer-g1/critic-codex.md#L5-L6), Critic Codex reported two concrete **MEDIUM** side effects of the proposed G1 fix:
   - *Mark aligned on its own (zero-shift): overlapping picture takes its pin.*
   - *Mark and unrelated picture: pin can silently switch.*
   The author relegated these to narrative text rather than tracking them as verified findings, and adopted a solver patch that in turn broke one-ended connectors and protruding marks.

---

### Summary of Required Adjustments

1. **Re-rate G5 to MEDIUM:** Note the procedural breach of fixing it without a peer step.
2. **Re-rate G2 to MEDIUM:** Track it as a defect violating Rule B4 rather than deflecting it as a rule question.
3. **Fix the alignment logic in [`EditorController.alignSelection`](file:///home/frank/Projects/Thinkspace/lib/editor/controller.dart#L1214):** Exclude riding connectors from `frame`, ensure lines with a free end (`o.start == null || o.end == null`) receive their alignment shift on that free end, and prevent double-shifting protruding marks.
4. **Do not stop the review loop:** A Round 3 with a fix auditor is required to audit the fixes in commit `988327c`.
