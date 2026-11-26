# Design decisions

The values (colours, sizes, spacing, corners, timings) live in [`lib/ui/design.dart`](../lib/ui/design.dart). Nothing in the interface types a value of its own. This file holds the choices that are taste rather than rule, so nobody has to ask again.

## Words

- **Image**, never "picture": in labels, tooltips, messages and docs.
- **Remove marks** for the sweeping tool, not "eraser": it deletes whole marks, never part of an image.
- **Hide details** for the pixelate-or-cover box.
- **Lock in place** / **Unlock**.

## Feel

- **Snappy, no added motion.** Things appear and disappear at once. Flutter's own short fades on menus and tooltips stay.
- **Tools go back to Select after one use;** double-click a tool to keep it. Marking tools (pen, highlighter, Remove marks, numbered marker) stay active.
- **Esc backs out:** the current gesture, then the tool, then the selection. It never leaves full screen; F11 does.

## Layout

- **Toolbar groups** are separated by the same full divider used before undo and the grid buttons. Small gaps were tried first and were too subtle to see.
- **Controls are shown even when they don't apply yet,** greyed until they do. Example: Reset to default.
- **The active tool shows its key** as a small keycap under its button. The tools start at a fixed spot (past the Collection panel at its usual width) and never follow the panel, so the keycap hangs over open page area.
- **Controls in the panel:** every field, dropdown, button and button group is the same height. A labelled action is a full-width outlined button (Cut out…, Fit page to content); a set of options or small actions is a joined group of icon buttons (Align, Arrange). A single icon action next to fields is a one-button group, so it is boxed like its neighbours.
- **One thing looks selected.** In the Layers list only the selection is filled; the current layer is named in the accent colour, with a bar at its left whose tooltip says new things go there.
- **The Layers list has no bands or cards.** Layers are set apart by a thin line and a little room, and both kinds of row share one set of columns: an object's icon starts under its layer's name, and every eye sits in one column at the right, with the padlock and the layer's count just before it. Grey bands behind the layer rows were tried and looked heavy once the columns lined up.
- **Visible things' eyes are quiet** and darken under the pointer; a hidden thing's crossed-out eye is dark, so what is hidden stands out. Hidden layers' names stay faint on purpose.
- **Explanations go in tooltips** when they would otherwise be paragraphs in the panel (Grow the page as I add things).
- **The rows in a panel section end on one right edge,** and sizes carry their unit (px).
- **One blue:** switches and sliders use the accent colour, not a shade picked by Flutter's theme.
- **Numbers sit on the right of their field,** so a unit (°, px, wide) is right beside them.

## Type

- **Inter** for the whole interface, bundled so it looks the same on every desktop. Three weights: regular for text, semibold for names and buttons, bold for headings. No extra letter spacing anywhere.
- Text on the page keeps its own four typefaces (Sans, Serif, Mono, Hand).

## Icons

One outline style in the toolbar: Material's outline icons, and Thinkspace's own drawn to match them on an 18-unit grid with a 1.6 line (line, highlighter, Remove marks, Hide details, text, numbered marker, scissors, grid). No solid-filled icons; a numbered marker is a circle, as it is on the page.
