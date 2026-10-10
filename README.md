# Thinkspace

Thinkspace is a lightweight desktop workspace for quickly combining images, simple drawing, and layers to explain an idea without the complexity of a full graphics suite.

## Current direction

- Build a desktop app with Flutter and Dart, starting on Linux.
- Keep the interface sparse and quick to use.
- Support pasted/imported raster images plus editable straight lines, resizable arrows, and text/other simple marks.
- Keep objects individually editable. Layers organize objects: show/hide, reorder, move contents together, and move an object between layers.
- Keep a collected-images area for source images. It should be larger than a tiny tray and may be resizable. Pasting may offer a choice to add an image to the current layer or to the collection; exact behavior remains open.
- Allow resizing the canvas to make room for longer compositions. A five-image composition may need a tall/long page. Resizing should be easy; exact handles, units, and growth behavior remain open.
- Provide an optional visible grid and snapping to help position objects. Exact snapping behavior remains open.
- A saved project should preserve editable objects and layers; image export is a separate, flat output.

This is a working direction for the first prototype, not a final product specification. Open interaction details and the history behind these choices are in [`DRAFT.md`](DRAFT.md). The visual review mockup is [`mockups/index.html`](mockups/index.html); it is illustrative, not app code, and predates the larger/resizable collection, paste destination choice, movable objects between layers, optional snapping grid, and resizable canvas described above.

## Project files

- `README.md` — current product direction and project map.
- `DRAFT.md` — decisions, open questions, and brainstorming history. Later direction sections supersede older speculation where they conflict.
- `AGENTS.md` — collaboration and editing guidance.
- `mockups/index.html` — nonfunctional HTML vision-review mockup.
- `pubspec.yaml`, `lib/`, `test/` — existing Flutter scaffold; prototype implementation is pending.

## Collaboration

When implementing, read [`AGENTS.md`](AGENTS.md) and the latest direction in [`DRAFT.md`](DRAFT.md). Treat the current direction above as the user's chosen starting point. Do not add broad graphics-suite features or turn open interaction details into extra scope without discussing them. Agent inspectability is important: the app should eventually launch predictably, load known examples, exercise workflows, and expose screenshots and meaningful app state.
