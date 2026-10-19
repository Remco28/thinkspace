# Polish to-do

Work list for the `polish` branch. No new features: the goal is that Thinkspace looks and behaves like one carefully made thing. This file goes once the list is done.

## Do

- [x] **One set of design values.** Done: everything comes from `lib/ui/design.dart`, with taste decisions in `docs/DESIGN.md`. In the interface, 10 text sizes became 3, 8 icon sizes became 3, 10 roundings became 2 plus a pill shape, and about 40 colours became 22 named roles; spacing is on a 4 px grid.
- [x] **One look per kind of control in the side panel.** Done: Layer is drawn as a field, the units sit against their numbers, the lone size button is boxed, and every control is 28 tall. Wide labelled buttons for actions and icon groups for options stay as the two button styles (recorded in `docs/DESIGN.md`).
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
