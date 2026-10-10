# Architecture

Thinkspace keeps three things apart on purpose:

- **The document** — the named things on the page and the changes someone meant.
- **The picture** — how those things look right now, including zoom and pan.
- **The export** — a flat image, only when a flat image is wanted.

Zoom changes the view, never an object's position in the document. A drag updates objects live so the picture follows the hand, and the history records it once, on release.

## Layers of code

```
lib/model     plain data         no Flutter widgets, no I/O
lib/editor    behaviour          controller, interactor, painting, image maths
lib/ui        windows & panels   read the controller, call its methods
lib/io        the outside world  clipboard, dialogs, samples
lib/dev       inspection         HTTP door, enabled by an environment variable
```

### Model (`lib/model`)

- `Document` — canvas size, background, grid size, `layers`, `collection`, an id counter. Serialises to JSON.
- `Layer` — name, visible, locked, and its objects bottom-to-top.
- `SceneObject` and subclasses: `ImageObject`, `TextObject`, `ShapeObject` (rect/ellipse), `LineObject` (line/arrow), `StrokeObject` (pen). Boxes (`BoxObject`) have centre, size, rotation; lines have two endpoints; strokes have points. Each knows how to hit-test itself, translate, copy and serialise.
- `CollectionItem` — a source image kept for reuse. A *different thing* from an `ImageObject` placed on the page; placing one creates a new object and leaves the source.
- `AssetStore` / `Asset` — decoded images live **outside** the document. Objects hold an asset id. That keeps history snapshots tiny and means an undone image can always come back. Each asset keeps a coarse alpha mask (≤ ~1024 px) so transparent parts of cutouts are not grabbable; full pixels are read on demand.

### History

`EditorController` snapshots the document as JSON before a change (`beginEdit`) and pushes it on the undo stack when the change is finished and actually differs (`endEdit`). `transact(label, fn)` wraps the common case. Gestures hold a token across pointer-down → pointer-up, so a drag is one step however many events it produced. Sliders do the same (`LiveSlider`). `Document.signature()` ignores the id counter, so an abandoned gesture that burned an id is not an edit.

### Interaction (`lib/editor/interactor.dart`)

`CanvasInteractor` turns pointer events into edits. Modes: pan, move, resize, rotate, line-end, marquee, create, pen, lasso, box cutout, text box, canvas grip. Selection rules worth knowing:

- Pointer-down on a handle (single selection) wins, then canvas grips, then objects.
- Pointer-down on an already-selected object (even beneath another) keeps it grabbed so it can be dragged; a plain click without moving then picks the topmost.
- Clicking the selected top object again walks down the stack (`_cyclePoint` / `_cycleIndex`); `Alt` jumps straight to the one beneath.
- Snapping is applied to the dragged bounds' left/centre/right (and top/centre/bottom), or to the point for line ends and canvas grips. `Ctrl` bypasses it.

### Painting (`lib/editor`)

The page is painted from the document by `paintDocumentObjects` (`render.dart`) — the **same function** draws the editor view and the export, so what you see is what you export. Overlays (selection outlines, handles, name chip, grips, marquee, lasso) are painted in screen space by `CanvasPainter` so they stay crisp at any zoom. Text objects are painted by `TextPainter`; while editing, a real `TextField` is laid over the object in the same transformed space.

Objects with opacity are drawn into a `saveLayer`, so a rotated, semi-transparent picture fades as one thing.

### Images

`image_ops.dart` holds the pixel work: polygon cutouts (clip + draw, optionally erasing the hole from the original), flood-fill colour removal with tolerance, and corner-seeded background removal. Results become new assets; the object just points at the new id, so every operation is undoable and the originals are never mutated.

### Files

A `.thinkspace` project is one JSON file: `{format, version, document, assets: {id: base64}}`. Only assets still referenced are written. Loading decodes into a scratch store first, so a bad file leaves the open project alone. Autosave writes the same format to `~/.local/share/thinkspace/recovery.thinkspace` (or `$THINKSPACE_DATA_DIR`) when there are unsaved changes.

Clipboard images go through `xclip` or `wl-clipboard`, because Flutter's clipboard carries only text. When Thinkspace copies, it puts a rendered PNG on the system clipboard *and* remembers a signature of it, so a later paste can tell "my own copy" from "something new" and paste full-fidelity objects.

### Inspector (`lib/dev/inspector.dart`)

With `THINKSPACE_DEBUG_PORT` set, the app serves `/state` (the controller's own account of the document and selection), `/screenshot` (the whole app, dialogs included), `/export` (the page) and `/do` (drive the controller and interactor). `tool/run_headless.sh` runs the real window on Xvfb; `tool/xinput.py` injects genuine X input so the real hit-testing, focus and text-input paths can be exercised.

## Testing

`flutter test` needs no display.

- `test/model_test.dart` — serialisation, hit-testing, geometry.
- `test/editor_test.dart` — the controller and interactor driven headlessly with real gesture sequences: drawing, moving, snapping, resizing and rotating (including rotated objects), cycling through overlaps, marquee, layers, z-order, cutouts of rotated/flipped images, background removal, merge, recovery, save/load, export pixels.
- `test/widget_test.dart` — the real widget tree with pointer and keyboard events: tools, shortcuts, layer panel, text editing on the page, paste chooser, recovery dialog, and layout at several window sizes.
