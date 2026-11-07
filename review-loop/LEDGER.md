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
