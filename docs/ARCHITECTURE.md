# Architecture

Thinkspace keeps three things apart on purpose:

- **The document** — the named things on the page and the changes someone meant.
- **The image** — how those things look right now, including zoom and pan.
- **The export** — a flat image, only when a flat image is wanted.

Zoom changes the view, never an object's position in the document. A drag updates objects live so the image follows the hand, and the history records it once, on release.

## Layers of code

```
lib/model     plain data         no Flutter widgets, no I/O
lib/editor    behaviour          controller, interactor, painting, image maths
lib/ui        windows & panels   read the controller, call its methods
                                 (every colour, size and timing: lib/ui/design.dart)
lib/io        the outside world  clipboard, dialogs, samples
lib/dev       inspection         HTTP door, enabled by an environment variable
```

### Model (`lib/model`)

- `Document` — canvas size, background, grid size, `layers`, `collection`, an id counter. Serialises to JSON.
- `Layer` — name, visible, locked, and its objects bottom-to-top.
- `SceneObject` and subclasses: `ImageObject`, `TextObject`, `ShapeObject` (rect/ellipse, also the highlighter's box), `BadgeObject` (numbered marker), `HideObject` (Hide details), `LineObject` (line/arrow), `StrokeObject` (pen and highlighter marks). Boxes (`BoxObject`) have centre, size, rotation; lines have two endpoints and an optional `bend`; strokes have points. Each knows how to hit-test itself, translate, copy and serialise.
- A curved line keeps its `bend` relative to its own chord (along it, across it, as fractions of its length), so moving or stretching the ends keeps the shape. It is drawn as a quadratic curve through the bend point; hit-testing and bounds use points sampled along it. A straight line writes no `bend`, so older files and older builds are unaffected.
- `CollectionItem` — a source image kept for reuse. A *different thing* from an `ImageObject` placed on the page; placing one creates a new object and leaves the source.
- `AssetStore` / `Asset` — decoded images live **outside** the document. Objects hold an asset id. That keeps history snapshots tiny and means an undone image can always come back. Each asset keeps a coarse alpha mask (≤ ~1024 px) so transparent parts of cutouts are not grabbable; full pixels are read on demand.

### History

`EditorController` snapshots the document as JSON before a change (`beginEdit`) and pushes it on the undo stack when the change is finished and actually differs (`endEdit`). `transact(label, fn)` wraps the common case. Gestures hold a token across pointer-down → pointer-up, so a drag is one step however many events it produced. Sliders do the same (`LiveSlider`). `Document.signature()` ignores the id counter, so an abandoned gesture that burned an id is not an edit.

### Interaction (`lib/editor/interactor.dart`)

`CanvasInteractor` turns pointer events into edits. Modes: pan, move, resize, rotate, line-end and bend, marquee, create (lines, shapes, Hide details boxes), pen, highlight, remove, lasso, box cutout, text box, canvas grip.

Remove marks marks what it sweeps over in `EditorController.removing` (drawn faded) and deletes it all on release in one step; Esc clears the set. `EditorController.removable` decides what it may take: never images, text or Hide details boxes.

The eyedropper renders the page once into raw pixels when it starts, so hovering reads colours without re-rendering; the colour picker reaches it through the `pickFromPage` hook the shell sets. Selection rules worth knowing:

- Pointer-down on a handle (single selection) wins, then canvas grips, then objects.
- Pointer-down on an already-selected object (even beneath another) keeps it grabbed so it can be dragged; a plain click without moving then picks the topmost.
- Clicking the selected top object again walks down the stack (`_cyclePoint` / `_cycleIndex`); `Alt` jumps straight to the one beneath.
- Snapping is applied to the dragged bounds' left/centre/right (and top/centre/bottom), or to the point for line ends and canvas grips. `Ctrl` bypasses it.

### Painting (`lib/editor`)

The page is painted from the document by `paintDocumentObjects` (`render.dart`) — the **same function** draws the editor view and the export, so what you see is what you export. Overlays (selection outlines, handles, name chip, grips, marquee, lasso) are painted in screen space by `CanvasPainter` so they stay crisp at any zoom. Text objects are painted by `TextPainter`; while editing, a real `TextField` is laid over the object in the same transformed space.

Objects with opacity are drawn into a `saveLayer`, so a rotated, semi-transparent image fades as one thing.

`paintObjects` draws a list bottom to top and hands each Hide details box everything drawn before it. Pixelating draws that, in the box's own rotated frame, into a small image with four samples per tile (`Image.toImageSync`), shrinks it to one pixel per tile with mipmapped sampling (an average), and draws that back over the box with `FilterQuality.none`. Only objects that overlap the box are redrawn. Copying and merging go through `paintObjects` too, so nothing leaves the app un-hidden.

### Tool looks

Each tool has a `ToolStyle` (colour, width, fill, size, font and a few tool-specific switches) in `EditorController.toolStyles`; `defaultToolStyles()` is what "Reset to default" returns to. Editing something on the page updates the style of the tool that makes it (`toolFor`, `rememberStyle`).

### Images

`image_ops.dart` holds the pixel work: polygon cutouts (clip + draw, optionally erasing the hole from the original), flood-fill colour removal with tolerance, and corner-seeded background removal. Results become new assets; the object just points at the new id, so every operation is undoable and the originals are never mutated.

### Files

A `.thinkspace` project is one JSON file: `{format, version, document, assets: {id: base64}}`. Only assets still referenced are written. Loading decodes into a scratch store first, so a bad file leaves the open project alone. Autosave writes the same format when there are unsaved changes, one file per window in `~/.local/share/thinkspace/recovery/` (or under `$THINKSPACE_DATA_DIR`). Several windows can be open at once, so each holds a lock beside its own copy while it runs (`lib/io/recovery.dart`); at start-up only copies nobody holds, left by a window that never closed properly, are offered back, newest first. The single `recovery.thinkspace` of older versions is offered too.

`prefs.json` in the same folder (`lib/io/prefs.dart`) holds what belongs to the person, not to a project: the Layers/settings divider, each tool's look and the recent projects. The shell saves it by watching the controller: when the tool looks or the recent list change, it writes them a moment later, so no call site has to remember to save. An unreadable or odd file just means defaults.

Clipboard images go through `xclip` or `wl-clipboard`, because Flutter's clipboard carries only text. A copy counts only once the clipboard is read back and holds exactly the new image; otherwise the next tool is tried and then the copy is reported as failed, because a silent failure leaves the previous image there to be pasted. A selection copied as an image takes along any Hide details boxes over it (`withCovers`). When Thinkspace copies, it puts a rendered PNG on the system clipboard *and* remembers a signature of it, so a later paste can tell "my own copy" from "something new" and paste full-fidelity objects.

### Inspector (`lib/dev/inspector.dart`)

With `THINKSPACE_DEBUG_PORT` set, the app serves `/state` (the controller's own account of the document and selection), `/screenshot` (the whole app, dialogs included), `/export` (the page) and `/do` (drive the controller and interactor). `tool/run_headless.sh` runs the real window on Xvfb; `tool/xinput.py` injects genuine X input so the real hit-testing, focus and text-input paths can be exercised.

## Testing

`flutter test` needs no display.

- `test/model_test.dart` — serialisation, hit-testing, geometry.
- `test/editor_test.dart` — the controller and interactor driven headlessly with real gesture sequences: drawing, moving, snapping, resizing and rotating (including rotated objects), cycling through overlaps, marquee, layers, z-order, cutouts of rotated/flipped images, background removal, merge, recovery, save/load, export pixels.
- `test/widget_test.dart` — the real widget tree with pointer and keyboard events: tools, shortcuts, layer panel, text editing on the page, paste chooser, recovery dialog, the name tag's padlock, and layout at several window sizes.
- `test/curves_test.dart` — curved lines and the eyedropper.
- `test/remove_marks_test.dart` — what a sweep removes, leaves and undoes.
- `test/hide_styles_recent_test.dart` — Hide details (including the pixels it produces), tool looks, locking, recent files and prefs.
- `test/dib_test.dart`, `test/platform_test.dart` — the Windows clipboard bitmap format and per-platform paths.
