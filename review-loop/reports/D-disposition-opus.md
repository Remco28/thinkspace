I couldn't run commands here, so I worked out the WCAG luminance figures by hand. They should be accurate to about ±0.02. Every token claim below is checked against `source/`, and every layout claim against the zoomed screenshots.

## Overall

The step-0 table is right, but the proposal has three problems. The new faint grey becomes almost the same as `kInkSoft`. The new sub-head style is identical to the layer names. Several of the "pale" items aren't `kInkFaint`, so the colour change misses them. The ratings look anchored to the prediction ("mostly MEDIUM"), and two of the tier calls go against the ledger's own rules.

## Q2: Do the numbers and token claims hold?

**Step-0 contrast figures: all correct.** I recomputed every cell: `kInkFaint` is 3.19, 3.01, 2.56 and 2.75; `kInkSoft` is 6.1, 5.75, 4.90 and 5.27; panel against workspace is 1.175:1. One small point: `kAccent` on white is 4.499, which is just *under* 4.5, not "4.5".

**Proposed `666D7E`: 4.9:1 on the panel is correct, but that's the only background the ledger quotes.**
- On white it is 5.2:1.
- On the workspace `E4E6EB` it is **4.1:1**, which still fails the ledger's own 4.5 line. The table has a workspace column, so the author expects faint text there.
- On a selected row it is **4.0–4.5:1**. That's 4.47 on `E8EEFF`, and about 4.0 on the actual selected object row, which is `kAccent` at 16% over the panel ≈ `D7E1FB`.

**Token claims:**
- Correct: Section titles are 11 px, w700, `kInkSoft` (`source/kit.dart:42-45`). PropRow labels are 12.5 px `kInkSoft` (`source/kit.dart:74`). Menu headings are `kInkFaint` (`source/menus.dart:96`). Menu shortcuts are 11 px `kInkFaint` (`source/menus.dart:70-72`).
- **Wrong:** Finding 1 puts "the panel headings" in the faint tier. `PanelHeader` (LAYERS, IMAGE, PAGE) is **`kInkSoft`** (`source/widgets.dart:28`). Changing `kInkFaint` does nothing for them; only finding 3's proposal reaches them.
- **Wrong:** The helper text (`Hint`, and the `SwitchRow` hint) is **`kInkSoft` at 11 px** (`source/kit.dart:271-275, 303-306`), not `kInkFaint`. This is B's #1 finding and is also on C's list. The colour change misses it; only caption 11→12 reaches it. B measured the hint text at about 3.5:1 even though the token is 5.8:1. That gap is anti-aliasing thinning 11 px strokes, and it means token ratios overstate how readable small text really is.
- **Probably wrong:** "Reset to default" in shot 06 is drawn in the same pale grey as the disabled "Open recent" in shot 07. It is most likely a *disabled* button (`kInkDisabled`, 1.9:1) because the width is already at its default. If so, the proposal never reaches it. Its source wasn't provided, so I couldn't confirm this.
- **Not reached by the size change:** `KeyCap` hard-codes 8.5 px and 11.5 px (`source/widgets.dart:655`). The toolbar letter badges C flagged ("V" under the tool) stay at 8.5 px. design.dart's own comment says "Nothing in the app types a value of its own", which isn't true here. Icon sizes 14 and 15 are also hard-coded (`source/layers_panel.dart:448, 461`), and step 0's "13, 16, 18" misses them.

## Q3: New problems the proposal would cause

**1. The two secondary greys collapse into one.**
- Today `kInkSoft` against `kInkFaint` is 1.9:1. With `666D7E` it is **1.18:1**, about 11 RGB levels apart, so you can't tell them apart.
- The ledger never says it intends to merge the two tiers, and it also moves menu headings to `kInkSoft`. In practice it creates one secondary grey without saying so.
- Merging may be fine (C asked for `#5b6270` everywhere), but then the step between labels and captions has to come from size and weight. The proposal should say that and decide it on purpose.

**2. `kInkFaint` isn't only text, so darkening it changes other things the ledger doesn't mention:**
- **The key-cap shadow** is `kInkFaint` (`source/widgets.dart:646`). The key caps are the element A and C both praised, and they would get heavier.
- **Layer drag handles** (`source/layers_panel.dart:259`) and the **lock icons** would darken. That puts four dark marks before every layer name, which adds noise to the column whose problem is "can't lock in".
- **Hidden layers and objects** are shown by putting the name in `kInkFaint` (`source/layers_panel.dart:304, 438`). Against `kInk`, that cue drops from 4.7:1 to 2.9:1. Hidden names would then look like ordinary `kInkSoft` labels instead of "off".

Fix: keep a separate token for icons, the shadow and the hidden state.

**3. Headings would look exactly like layer names.**
- The proposed sub-head style is body size, semibold, `kInk`. That is exactly the layer-name style today: `kTextBody`, `kWeightStrong`, `kInk` (`source/layers_panel.dart:301-305`). It is also the style of a selected object's name.
- Finding 4 is "things that look alike", and this adds one more lookalike.
- Panel headers would be 12 px caps in `kInk`, while the sub-heads under them would be 13.5 px semibold `kInk`. The top level could end up equal to or weaker than the level below it, so the hierarchy is flat again, just in a different place.

**4. Fixed heights.**
- Fields are a tight `kControlHeight` 28 with dense padding of 8+8. At 12.5 px that's already about 31 px of content, and at 13.5 px it's about 32 px. The layer rename field is only 26 px tall (`source/layers_panel.dart:567`).
- The current shots render fine, so Flutter is absorbing the overflow today. One more pixel could clip descenders ("awning_02", "Navy awnings").
- The before/after should include a focused field and a rename field.

**5. Fixed widths: low risk, but worth showing.**
- **Label column** (64 px; `LabeledRow` is 62): from the 2× crops, "Opacity" ≈ 49 px and "Spacing" ≈ 52 px at 13.5 px, so they fit. I couldn't check labels in panels that weren't shot (shapes, badges). A label of 9 or more characters would *wrap*, not clip, and make that row taller.
- **Value box** (56 px): "100%" ≈ 33.5 of the 40 px available at 13.5 px. It fits, but "100 %" with a space, or a 4-digit value, would not.
- **Menus** (210/220 px): the longest label-plus-shortcut pair in 07 and 08 ("Copy page as image" with Ctrl+Shift+C) still fits at 13.5 + 12.

## Q1: Ratings, and findings that are missing or folded away

**Ratings that are too gentle:**
- **Finding 3** is called "the main cause" in its own row but rated MEDIUM. The stakes line ("does not lose data") seems to have capped everything at MEDIUM. In a review *about readability*, the issue the owner complained about, seen on every screen, should be **HIGH**.
- **Finding 1** fails the ledger's own guideline on every screen for three readers out of three. I'd also make it **HIGH**.
- **Finding 4** is rated LOW, but it's the one place a glance task actually failed (A task 2). It should be **MEDIUM**.

**Count and tier inconsistencies:**
- **Finding 4** is rated "Tier 1, LOW" but is handled like tier 3 ("For Frank", not in the proposal). A verified tier-1 finding has been parked as taste.
- **Finding 7** was raised by B and C. "Two or more independent readers agree" is tier 1, and A disagreeing doesn't make it taste. It's a genuine 50/50 and should go to Frank *as a split* (two readers say dense, one says it's the best screen in the app), not as "no change proposed".
- **Finding 6** is partly checkable. The field border `kControlBorder` `D0D4DD` is **1.49:1 on white and 1.40:1 on the panel**, well under the 3:1 non-text guideline the ledger already uses. That part is tier 2, not taste.

**Missing from the table or folded away:**
- **C §1.4, weak grouping:** row gap compared with section gap. The code (8 vs 12+1+12) suggests C overstated this, but it should be listed and rejected, not dropped.
- **C §2, shot 06:** "pen settings and page settings read as one continuous list". In shot 06, "Page size" sits under NEW PEN STROKE behind only a hairline. This is directly about focus, and the proposed bold `kInk` sub-heads would make "Page size" compete *more* with the pen controls.
- **C §1.5, competing elements:** the swatch rows are "the loudest thing in the column", and the selection highlight dominates.
- **C §3, the active-layer bar is "easy to miss":** the code already makes it 3 px, which is what C asked for. Check it and say so.
- **C §1.1 and §2, "values look like labels":** the Done column says "labels stay kInkSoft, values stay kInk", which is no change, with no reason given. In shot 02 values *are* darker than labels, so C is partly wrong. The ledger should say that rather than quietly keep the status quo.
- **C §4, minor:** faint menu hover, and weak menu edges on white.
- **A tasks 5 and 6, telling characters apart:** S/N and ]/[ are folded into "shortcuts faint". +1 px and a darker grey help, but nothing confirms that `]` and `[` become distinct at 12 px. The after shot should show them.
- **A task 6:** "Lock in place is last of 15 rows" is about searching, which the success question covers. It isn't recorded anywhere.
- **Finding 5 is understated:** the ring is `kAccent` (luminance ≈ 0.18) and red has about the same luminance, so on red the ring stands out by hue only. On the **blue** swatch a blue ring would be almost invisible. The proposed white-gap ring does fix this, but the before/after should show the selected blue swatch.

## Q4: The tier-3 items

- **8 (scaling): act now, it isn't taste.** The ledger itself says the laptop's scaling is "unknown", and the answer decides finding 2. At 125–150% the 12.5→13.5 change matters much less. Ask Frank this *before* showing him the sizes, as a question rather than an FYI.
- **4: act on it, and put it to him honestly.** The proposed "layer rows semibold kInk" is already the current style (`source/layers_panel.dart:303-304`). Only the band is new. The colour-only options within scope are: object names in `kInkSoft`, plus a tinted band on layer rows. Moving the eye icon is a layout change and goes to him separately. This has to be settled together with the finding-3 sub-head style, or the two will clash.
- **7: put it to him as a split** between readers, as above.
- **6: split it.** Field borders at 1.4:1 can be checked and fixed with a token. Workspace tone is taste, so show it before/after.

## Q5: The "what happened against the predictions" section

- **Faint text, small body text, flat hierarchy: these three hold.**
- **Icons "no; none of the others raised one": overstated.** B §5 says the smaller eye, grid/snap and collection controls "may take an extra moment to identify", and C raises the eye-icon placement. "Minor, not serious" is fair; "none raised one" is not. The prediction also rested on a wrong fact: the Layers eye is 18 px, and the object eye is 15 px, not 13.
- **Count: wrong.** The table has **5** tier-1 findings: 3 MEDIUM (1–3) and 2 LOW (4, plus 5 "by my check"). There is no tier-2 item, so "plus 1 to check" refers to nothing. The ratings landing exactly on the predicted "mostly MEDIUM" is the softness sign this audit exists to catch.
- **"Believed, and wrong" holds.**

## What I could not check

- Where "Reset to default", the collection captions and the 01 hint get their colour (that source wasn't provided).
- Whether any `kInkFaint` text actually sits on the workspace.
- Row labels in panels that weren't screenshotted.
- The ledger's "16 uses" of `kInkFaint`: the five files I have contain about 10.
- I couldn't render anything, so the overflow risks are measured from the 2× crops, not tested.
