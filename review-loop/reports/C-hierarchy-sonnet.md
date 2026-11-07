**Short answer:** the complaint is real, but I don't think plain low contrast is the main cause. The main cause is a flat hierarchy. Almost everything is one size (about 12–13px), one weight and one dark grey. Panel, canvas and chrome tones are also very close together. I judged from the full-size screenshots only. I did not measure pixel colours and I did not open the zoom crops.

## 1. Diagnosis, in order of importance

1. **Flat hierarchy (the biggest factor).**
   - In 02, the layer names, the row labels ("Name", "Layer", "Opacity", "Size", "Rotate", "Border") and the input values ("awning_02", "640", "85 %") are all about the same size, weight and grey.
   - The eye has nothing to rank them by, so it can't lock onto a value.
   - The section sub-heads ("Size and rotation", "Edit", "Align", "Style") are only slightly bolder and smaller than the row labels. They don't work as anchors.
   - The same holds in 05: "Page size", "Page colour" and "Grid" are tiny, medium-weight and grey.
2. **Type is small and the secondary text is too faint.** Several tiers of text sit at roughly 11px or smaller and in a lighter grey.
   - Helper text in 05: "The page gets bigger, on any side…" and "You can also drag…".
   - Collection captions: "green awning" and "plant".
   - The "1200 × 800" readout.
   - Unit suffixes: "wide", "high", "px", "%".
   - Layer child counts (the "2", "1" at the right edge).
   - The shortcut hint badges, such as "V" under the tool.
   - On the 24-inch screen these are tolerable but tiring. On the 14-inch ThinkPad at 100% scaling they would be about 40% smaller physically and likely unreadable.
   - Contrast does matter for this faint tier and for the disabled-looking items, but not for the main text.
3. **Background tones are too close.**
   - The right panel, left panel, top bar and canvas surround are all pale cool greys and whites.
   - The canvas surround (~#e4e6ec) is only slightly darker than the panels.
   - Inputs are white with a hairline border on a near-white panel. Fields, buttons and plain text all look like faint outlines.
   - Nothing separates "things I act on" from "things that label them".
4. **Weak grouping.** Sections are divided by 1px hairlines and a small amount of space.
   - In 03, "Size and rotation" and "Style" are separated from the rows above only by a rule.
   - Row spacing inside a group is about the same as the gap between groups.
   - The Layers/properties split is a hairline plus a tiny grip, and the "IMAGE" header is the same weight as "LAYERS".
5. **Competing elements.**
   - In 02 the canvas selection chip, the saturated blue handles and the blue highlighted row all compete.
   - The colour swatch rows (03, 05, 06) are the loudest thing in the right column. They pull the eye away from the labels around them.

## 2. Right column anchors (02–06)

- **Panel headers ("IMAGE", "TEXT", "PAGE", "NEW PEN STROKE") are the only real anchors.** They are small caps in mid-grey at about 11px. They are the same style as "LAYERS" and "COLLECTION", so they identify the panel but don't draw the eye.
- **Order of importance is inverted or flat.**
  - Sub-heads ("Size and rotation", "Style") are weaker than they should be.
  - Row labels ("Opacity", "Font") are about as strong as the sub-heads.
  - Values in the inputs ("85 %", "640") look the same as labels. The value is what the user needs, so it should win.
  - The helper paragraphs in 05 are just a step below the labels, so the page reads as a wall of grey.
- **Exception:** "Grow the page as I add things" in 05 is slightly larger and darker. That works, and it reads as the toggle's title.
- **06 is the weakest screen.** "Colour" and "Width" are the real task. They sit directly under a small caps heading and above a faint "Reset to default". The page settings that follow, "Page size" and "Page colour", have equal visual weight. Pen settings and page settings read as one continuous list.

## 3. Layers vs objects

- **Partly distinguishable.**
  - Layers are slightly heavier (medium weight), have a chevron and an eye icon on the left, and have a count on the right.
  - Objects are indented slightly and carry a type icon (arrow, T, image). They are a little lighter and have their eye icon on the far right.
- **But it takes effort.**
  - Weight is the only real cue, and the weight difference is small.
  - Layer rows and object rows are the same height and the same size, with no background difference.
  - The indent is only about 20px.
  - Layer eyes are on the left and object eyes are on the right, which is inconsistent.
  - The selected-row highlight in 02/03 is the strongest element in the column, so it dominates instead of the structure.
- **Selected layer indicator.** A thin blue bar at the far left marks the active layer. It is subtle and easy to miss.

## 4. Menus and shortcuts

- **Main menu (07).**
  - *Helps:*
    - Dividers.
    - Right-aligned shortcut text, which is consistently positioned and lighter.
    - Icons at the left.
    - The small caps section label "WHEN I PASTE AN IMAGE".
    - Check marks for state.
  - *Hinders:*
    - The shortcut text is faint, small and low-contrast.
    - The "Open recent" disabled state is very faint, though that is expected.
    - Rows are tight with little padding between items.
    - The small caps label is faint grey and nearly disappears.
    - The menu is a white panel over a white-ish app, so its edges are weak apart from a shadow.
- **Right-click menu (08).**
  - *Helps:*
    - The red "Delete" is clear.
    - The grouping is logical (clipboard, order, move to layer, tools).
  - *Hinders:*
    - The "MOVE TO LAYER" heading is faint.
    - The hover highlight on "Duplicate" is very faint.
    - Shortcut labels are tiny.
    - The menu sits on a busy canvas.
- **Shortcuts window (09).**
  - *Helps:*
    - The key-cap styling is excellent for scanning.
    - The two-column layout (keys left, description right) is a strong structure.
    - Section headings are in small caps.
  - *Hinders:*
    - Description text is mid-grey and medium size.
    - The "TOOLS — PRESS THE LETTER" and other section heads are small and faint, so the window has no strong anchors.
    - The tool lines are dense, with a key cap and name inline and no alignment.
    - Bare words such as "Click", "Scroll" and "drag" in the key column are bold with no key cap. They are the same weight as the key caps, so the cap styling is inconsistent.
    - Rows have uneven spacing, and some descriptions wrap onto two lines.

## 5. Three changes (type and colour only, no layout change)

1. **Create a three-step type scale in the right column and menus.**
   - Panel and section titles: 11px caps → 12px caps, semibold, darker (about #2a2f3a) instead of mid-grey. Sub-heads ("Size and rotation", "Style", "Page size"): 11px medium grey → 12.5px semibold, same dark.
   - Row labels ("Opacity", "Size", "Font"): keep at 12–13px but drop to a lighter grey (about #5b6270) and regular weight.
   - Values in inputs: 13px, darkest (#1a1d24), regular or medium.
   - This ranks sub-heads over labels and values over labels, which is the order of importance.
2. **Raise the floor for small text.**
   - Everything currently 10–11px (helper text, captions, shortcut text, unit suffixes, counts, "1200 × 800") should go to at least 12px. Use about #5b6270 instead of the lighter grey.
   - Keep truly disabled items lighter, but not for secondary information that must stay readable.
   - This matters most for the ThinkPad at 100% scaling.
3. **Separate surfaces by tone, and make layers distinct from objects.**
   - Make the right and left panels a slightly different tone from the canvas surround. For example, panels near-white and canvas surround noticeably darker (about #d5d8e0). Give input fields a clear border (about #b8bdc9) or a tinted fill.
   - In Layers, make layer rows semibold and dark with a light tinted band (about #eef0f5) across the row, and make object rows regular weight in medium grey. Move all eye icons to one side.
   - Strengthen the active-layer bar from a thin line to 3px.

## 6. What to keep

- **The layout.** It is calm and well-organised, and the owner is right that "everything is pretty close to being there."
- **Key caps in 09 and the right-aligned shortcut column in 07/08.** These are good scanning devices.
- **The toolbar.** Icon grouping with dividers is clear, and the active tool (blue tint plus the letter tag) is easy to find.
- **The blue selection accent.** Selected layer row, canvas chip and handles tie together, though the highlight is a bit loud.
- **The red Delete in 08, the toggle in 05 and the pressed/active states for the font and format buttons in 03.** All are clear.
- **The canvas selection chip** ("awning_02 · Navy awnings"). It is a good, legible label.
- **Icon + label rows in the main menu and in the "Cut out…" and "Remove background" buttons.**

**Not checked:** I did not open `04` or `10`. I did not open the zoom crops or measure colours or font sizes in pixels. Sizes and greys above are estimates from the full screenshots.
