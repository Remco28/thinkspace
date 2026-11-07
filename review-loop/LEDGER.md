# Review-loop ledger: readability of the interface's text and icons
*Kept by the review-loop skill. Safe to delete this folder once the work is done.*

Success question: Glancing at any part of the window, can someone find and read the label, value, or icon they need in about a second, without straining or searching?
Rules confirmed with: Frank, 2026-11-07.
- One round: three readers on different models, plus the auditor.
- I come back with findings and a proposed set of type sizes and colours, shown before and after. Nothing is built until Frank agrees.
- Guideline used as a source of truth (step 0): text contrast of at least 4.5:1, and 3:1 for icons and large text.

Reviewing: a whole thing, the interface as it is at 7e02bbd (main).

How it is really used (stakes):
- Frank runs the dist build on two screens: a 14" 16:10 ThinkPad (probably 1920×1200, about 160 ppi, scaling unknown) and a 24" 1080p monitor (about 92 ppi).
- His words: "a lot of the text is difficult to read… something preventing my eyes from locking into each thing I need to focus on."
- A failure costs strain and slower work every session. It does not lose data.
- Stop after one round and propose.

## Step 0 (computed from lib/ui/design.dart)
Contrast of each text colour against each background:

| Text colour | white | panel F7F8FA | workspace E4E6EB | selected row E8EEFF |
|---|---|---|---|---|
| kInk 222733 | 14.9 | 14.1 | 12.0 | 12.9 |
| kInkSoft 5B6272 | 6.1 | 5.8 | 4.9 | 5.3 |
| kInkFaint 8A90A0 (captions, counts, shortcuts, units; 16 uses) | 3.2 | **3.0** | **2.6** | **2.8** |
| kInkDisabled B4B8C2 | 2.0 | 1.9 | 1.6 | 1.7 |
| kIconInk 444B5A | 8.8 | 8.2 | 7.0 | 7.5 |
| kAccent 2F6BFF | 4.5 | 4.2 | 3.6 | 3.9 |

- Type sizes: caption 11 px (18 uses), body 12.5 px (40 uses), title 14.5 px. Font: Inter at 400, 600 and 700.
- Icons: 13, 16 and 18 px.
- The workspace and panels are three close greys: F7F8FA, E4E6EB and white.

## Round 1, 2026-11-07, 7e02bbd
Predictions (written before the round):
- kInkFaint text (counts, shortcuts, units such as "wide", "px" and "%", the Layers counts) will be named hard to read by at least two readers.
- 12.5 px body text will be called small, especially once the laptop is mentioned.
- Someone will say the hierarchy is flat: section labels (11 px caps) are weaker than the rows they head, and many things share one size and grey, so nothing anchors the eye.
- Icons at 13 px (the Layers eye, small buttons) will be called faint or small.
- Expect 4 to 7 verified findings, mostly MEDIUM.

Cast:
- A, glance-task user: claude-opus-5-5.
- B, legibility specialist: codex gpt-6-luna, with the images attached.
- C, visual hierarchy and focus: claude-sonnet-5-5.
- The disposition auditor runs after sorting: claude-opus-5-5.

A's tasks 1 to 6 were written only in its thinking. The final reply holds tasks 7 to 11; I recovered 1 to 6 from the thinking in the log:
- Task 1: opacity 85%, size 640×190. "Size and rotation" is faint.
- Task 2: "Navy awnings", and Notes holds 2. The count is tiny and far right, and layer and object names look alike.
- Task 4: the width reads at a glance. Which swatch is chosen is hard to pick out.
- Task 5: the shortcuts are faint; Ctrl+Shift+S is hard to tell from Ctrl+Shift+N.
- Task 6: Lock in place is last of 15 rows, and Ctrl+Shift+] and [ are hard to tell apart.

| # | Finding | Readers | Ours | From | How checked | Reaches | Done |
|---|---|---|---|---|---|---|---|
| 1 | A whole tier of secondary text is faint: counts, units (wide/high/px/%), menu shortcuts, the panel and menu headings, "Reset to default", collection captions | A, B (estimated 2.6–3.5:1), C | Tier 1, MEDIUM | untraced (the design tokens) | step 0: kInkFaint is 3.0:1 on the panel and 2.6:1 on the workspace | how it is used now: every screen | Propose kInkFaint 8A90A0 → 666D7E (4.9:1 on the panel) and menu headings kInkFaint → kInkSoft |
| 2 | Text is small: body ≈12.5 px and captions 11 px, worse on the 14" ThinkPad | A, B, C | Tier 1, MEDIUM | untraced | design.dart: kTextBody 12.5, kTextCaption 11 | how it is used now: both screens, the laptop most | Propose body 12.5 → 13.5, caption 11 → 12, title 14.5 → 15.5 |
| 3 | Flat hierarchy: section headings are the weakest text; sub-heads ("Size and rotation", "Page size") are about as heavy as row labels; values look like labels. Nothing anchors the eye — "the can't-lock-in feeling" | A, C (B: "one small size… harder to settle on a priority") | Tier 1, MEDIUM (the main cause, per A and C) | untraced | kit.dart: Section titles are 11 px, 700, kInkSoft; PropRow labels are 12.5 px kInkSoft | how it is used now | Propose: sub-heads at body size, semibold, kInk. Panel headers (LAYERS, IMAGE) in kInk. Row labels stay kInkSoft and values stay kInk |
| 4 | Layer rows and object rows look alike; the eye icons sit on different sides | C, A (task 2) | Tier 1, LOW | untraced | seen in shot 02 | how it is used now | For Frank: layer rows semibold kInk with a faint band. Not in the first proposal, to keep it to type and colour tokens |
| 5 | The selected swatch is hard to pick out | A (task 4) | Tier 1 by my check, LOW | untraced | zoom/06: a thin blue ring on red | how it is used now | Propose a thicker ring with a white gap |
| 6 | Background tones too close (panel F7F8FA, workspace E4E6EB); fields are hairline outlines on near-white | C | Tier 3 | — | step 0: the two greys are 1.17:1 apart | — | For Frank |
| 7 | The shortcuts window is dense; bare "Click"/"Scroll"/"drag" are styled unlike the key caps | B (dense), C | Tier 3. A found this window the easiest to read | — | — | — | For Frank; no change proposed |
| 8 | The laptop's display scaling: at 100%, 13 px is about 2 mm tall | A | Tier 3 (a setting, not the app) | — | — | the ThinkPad | Tell Frank: check the scaling there; 125% would help everything |

What happened against the predictions:
- faint secondary text named by 2 or more readers: yes, all 3.
- body called small: yes, all 3.
- flat hierarchy: yes, A and C call it the main cause.
- icons called faint or small: no. B found no serious icon problem, and none of the others raised one.
- 4 to 7 verified findings, mostly MEDIUM: 4 verified (3 MEDIUM, 1 LOW), plus 1 to check.

Believed, and wrong: "the font sizes were chosen for this app and are fine; it's colour." Size and hierarchy came up as much as colour did.
| 9 | The Layer dropdown in the properties panel draws in the system font, not Inter: a dropdown's style replaces the theme's, and this one did not name the font | found by me while building the proposal | Tier 1, LOW | untraced | seen in the before/after crops; read in properties_panel.dart | how it is used now | Fixed in the proposal branch |

### After the disposition audit (claude-opus-5-5, reports/D-disposition-opus.md)
Accepted:
- **Ratings.** #1 and #3 → HIGH: this review is about readability, and that is exactly the complaint. #4 → MEDIUM: it is where glance task 2 slowed. #4 goes into the proposal, not to "for Frank" alone.
- **The two greys collapsing.** Darkening kInkFaint would have merged it with kInkSoft and dimmed the hidden-name cue. Redone: kInkFaint is unchanged and kept for marks that are not read (grips, the key-cap shadow, hidden names). Every secondary *text* now uses kInkSoft, and the step below labels comes from size and weight.
- **Wrong token claims.** PanelHeader and Hint are kInkSoft, not kInkFaint; only the size and heading changes reach them. Corrected.
- **KeyCap hard-codes 8.5/11.5 px.** Raised to 9.5/12.5, and their heights to 13/20.
- **C §2, pen and page settings read as one list.** A PAGE heading and a divider now separate them when a tool is picked.
- **#5 on the blue swatch.** The after shot shows the dark ring on blue.
- **Fixed heights.** The after shot of a focused Name field shows no clipping. The layer rename field was not captured: F2 did not open it from the harness. Not checked.
- **"]" and "["** are distinct in the after shot of the right-click menu.
- **Corrections to the predictions.** Icons: B and C raised minor icon points, so "none raised one" overstated it. The tally is 5 tier-1 findings (3 MEDIUM, 2 LOW); "plus 1 to check" was wrong.
- **#7** goes to Frank as a split: B and C say the shortcuts window is dense, A found it the easiest screen.
- **#8, scaling:** asked as a question, not given as an FYI.
- **#6, field borders.** kControlBorder is 1.4:1 on the panel, under the 3:1 non-text guideline. That part is tier 2 by computation and goes to Frank as an option. The workspace tone stays taste.

Declined, with reason:
- **"Sub-heads now look like layer names."** They sit in different panels (the properties panel vs the Layers list), and the new band also sets layer names apart. Kept, and shown in the before/after.
- **C §1.4, weak grouping.** The code has an 8 px row gap against 12+1+12 between sections; C overstated it. Not acted on.
- **C §1.5, the swatches are loudest.** Colour swatches are meant to be seen; no change.
- **C §3, the active-layer bar.** It is already 3 px, as C asked.
- **"Reset to default" pale.** It is a disabled button (the width is already the default), and disabled controls are exempt from the contrast guideline.

From the review, separately: the page is fixed so it stays centred when the window grows after opening. Frank reported this mid-review; it is on its own commit, outside the proposal.
