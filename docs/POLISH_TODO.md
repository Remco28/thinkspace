# Polish to-do

Work list for the `polish` branch. No new features: the goal is that Thinkspace looks and behaves like one carefully made thing. This file goes once the list is done.

## Do

- [ ] **One set of design values.** Put colours, text sizes, spacing (4 px grid), corner roundings, icon sizes and durations in one file, and use only those everywhere.
  - Today there are 10 text sizes, 8 icon sizes, 10 roundings and more than 40 colours.
  - The named greys exist (`kit.dart`), but their hex codes are typed in directly 21 more times.
  - Merge the near-twins: borders `D8DBE3`/`D9DCE3`, reds `C62828`/`D32F2F`, greys `C3C8D4`/`C3C8D3`.
  - Colour definitions are split over `widgets.dart`, `kit.dart` and `canvas_painter.dart`.
- [ ] **One look per kind of control in the side panel.**
  - Name is a boxed field, but Layer is a bare dropdown.
  - The ° after Rotate floats away from the number.
  - Under the image section there are wide outlined buttons, while Align and Arrange use compact icon groups.
- [ ] **"Image", never "picture",** in everything the app says (labels, tooltips, messages) and in the README.
- [ ] **No repeated headings.** The panel header says ARROW, then the first section is titled Arrow; the same happens for every kind of object.
- [ ] **One highlight in the Layers list.** The selected object's row and its layer's row are both tinted. The layer should be quieter.
- [ ] **Keycap no longer sits on the Collection header.** The hanging "V" (the active tool's key) lands on COLLECTION. Idea: start the tools where the page area starts, past the Collection panel. Open question: what happens when the Collection panel is hidden or resized?
- [ ] **Bundle the interface font** (Inter, about 300 KB) so the app looks the same on every Linux desktop and on Windows.

## Later or maybe

- [ ] **Toolbar icons in one style.** Today there's a mix of outline and filled icons (bold T, filled scissors, solid mosaic, boxed 1). Held back for now. Revisit after the font and sizes settle, since those change how the icons balance.
- [ ] **Divider cutting a Layers row in half.** Seen in a screenshot (half a `storefront_photo` row under the Layers/settings divider), but not seen on Frank's screen. Check at a few window sizes and divider positions before fixing anything.
- [ ] **Motion.** Messages, the merge pill and the name tag appear and vanish instantly. Frank likes the snappy feel, so leave it unless something feels jarring in use. If anything, use very short fades (≤ 100 ms) and only on the bottom message.

## How each item is checked

- Before-and-after screenshots from the running app.
- `dart format lib test && flutter analyze && flutter test` stays clean.
- Smaller windows still lay out (the existing layout tests).
