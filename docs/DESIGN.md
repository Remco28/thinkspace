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
- **The active tool shows its key** as a small keycap under its button.
- **Controls in the panel:** every field, dropdown, button and button group is the same height. A labelled action is a full-width outlined button (Cut out…, Fit page to content); a set of options or small actions is a joined group of icon buttons (Align, Arrange). A single icon action next to fields is a one-button group, so it is boxed like its neighbours.
- **One thing looks selected.** In the Layers list only the selection is filled; the current layer has an accent bar at its left.
- **Numbers sit on the right of their field,** so a unit (°, px, wide) is right beside them.

## Icons

Material outline icons, plus a few drawn to match (line, highlighter, Remove marks, Hide details). Making every icon one weight and style is held until the interface font and sizes have settled.
