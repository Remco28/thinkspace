# Thinkspace

A small, quick place to get an idea out of your head and onto a page — to show someone what you mean.

Paste a screenshot or a photo, drop in more pictures, draw an arrow at the part that matters, fade one option, hide another, and send the result. It is what you reach for when GIMP is too slow, Paint is too thin and you do not want to learn a drawing suite.

Thinkspace is **not** a photo editor, a vector studio or a drafting tool. The screen stays sparse: a short toolbar, a layer list, a collection of source images, and a few properties for whatever is selected.

> Status: a working Linux desktop app (Flutter). It is built and tested on Linux; Windows and macOS builds are not attempted yet.

## What it does

- **Pictures stay separate things.** Paste, drop or import images. Each is its own object you can move, resize, rotate, fade and rename. Nothing is painted into the page until you export.
- **Fast lines and arrows.** Straight lines and arrows that you resize by dragging their ends. `Shift` snaps them to clean angles. Also rectangles, ellipses, text in four typefaces (sans, serif, mono, handwriting) and a smoothed pen; hold `Shift` with the pen for a straight line.
- **Layers that do the simple things.** Show/hide, reorder, lock, and *move everything on a layer together* — click a layer to select its contents, then drag. Drag any object onto another layer without it changing.
- **A collection of source images.** Keep pictures you have gathered but not placed. Drag one onto the page to use it; the original stays in the collection to use again. Click an item to select it (`Enter` places it, `Delete` removes it), and drag one onto another to rearrange the shelf (or use `[` `]`). The collection is resizable and can be hidden.
- **Cut things out.** Draw around the part of a picture you want (freehand or box) and it becomes a new object, leaving the original intact. Or click a colour to remove it, or clear a flat background in one click (it also clears the gaps inside a drawing and softens the edge, so a line drawing on white sits cleanly on any colour). Cutting can leave a gap in the original, which you can leave empty, blend in from the surroundings (good for flat screenshots), or fill with a colour. Pieces can be merged into a single image, and a merged image can be unmerged back into its original pieces for as long as the picture itself has not been cut or recoloured (moving, scaling, turning and fading do not matter).
- **A page that grows with the work.** Drag the grips on the page edge (or type a size) to make room for a longer composition. Resizing never touches the objects on it. "Fit page to content" tightens it up again.
- **A grid when you want one.** Show it, snap to it, hold `Ctrl` to ignore it. The grid is never part of the export.
- **Select the thing you mean.** Overlapping pictures are a fact of life: click the same spot again to reach the one underneath (or `Alt`-click). The selected object wears its name and layer on the page.
- **Undo that matches how you think.** One drag, one resize or one slider pull is one undo step.
- **Share it.** Export a PNG (1×, 2×), or copy the page — or just the selection — to the clipboard as an image.
- **Your work survives.** Projects save as one editable `.thinkspace` file (objects, layers and images). Unsaved work is autosaved and offered back after a crash, and closing with unsaved changes asks first.

## Install

Download `thinkspace-linux-x64.tar.gz` from the releases page (or build it yourself, below), then:

```bash
tar xzf thinkspace-linux-x64.tar.gz
cd thinkspace-linux-x64 && ./install.sh     # installs into ~/.local, no root needed
thinkspace
```

Pasting images from the clipboard uses `xclip` (X11) or `wl-clipboard` (Wayland):

```bash
sudo apt install xclip wl-clipboard
```

## A first five minutes

1. Take a screenshot to the clipboard, then press `Ctrl+V` in Thinkspace. Choose **Add to “Layer 1”** — the page becomes the size of your screenshot.
2. Press `A`, drag across the screen to draw an arrow. Drag either end to resize it. `Shift` keeps it straight.
3. Press `T`, click, type a note. Press `Esc` to finish.
4. Paste another picture. It lands as its own object: drag it, pull a corner, grab the round handle to rotate, and slide **Opacity** in the panel.
5. Add a layer (`+` in the Layers panel), drag the second picture onto it from the object list, and click the eye to flip between the two.
6. `Ctrl+E` exports a PNG. `Ctrl+Shift+C` copies the page so you can paste it into chat or email.

The menu (☰) has **Open the storefront sample**, a small scene with two overlapping awnings, a note and an arrow, if you would like something to poke at.

## Keyboard

| Key | Does |
|---|---|
| `V` `L` `A` `R` `E` `T` `P` `C` | Select · line · arrow · rectangle · ellipse · text · pen · cut out |
| double-click a tool | keep it active until `Esc` |
| `Shift` while drawing / dragging | straight angles · perfect squares · lock to one axis |
| `Ctrl` while moving | ignore snapping |
| `Space` + drag, middle or right drag | pan (a hint appears beside the zoom controls when the page is bigger than the window) |
| `?` or `F1` | the shortcut sheet |
| scroll wheel | zoom at the pointer (`Shift` + wheel pans) |
| `Ctrl+0` / `Ctrl+1` / `F` | fit the page / actual size / fit |
| `Ctrl+V` / `Ctrl+Shift+V` | paste (asks where) / paste into the collection |
| `Ctrl+C` `X` `D` | copy · cut · duplicate |
| `Ctrl+Z` / `Ctrl+Shift+Z` | undo / redo |
| `[` `]` | send backward / bring forward (`Ctrl` for all the way) |
| arrows | nudge (`Shift` = 10 px, or one grid step when snapping) |
| click a row in Layers, then `↑` `↓` | walk the list (`Shift` extends it; `Shift`+click selects a run) |
| `G` / `Shift+G` | show grid / snap to grid |
| `Ctrl+S` `O` `E` `I` | save · open · export PNG · add image |
| `M` / `U` | merge the selection into one image / take a merged image apart (a small button under the selection does the same) |
| `Ctrl+Shift+C` | copy the page as an image |
| right-click | context menu for what is under the pointer |

## Build from source

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install/linux) and the Linux desktop toolchain:

```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev
flutter pub get
flutter run -d linux
```

```bash
flutter analyze && flutter test        # the whole suite runs without a display
tool/package_linux.sh                  # dist/thinkspace-linux-x64.tar.gz
```

## Project map

| Path | What is there |
|---|---|
| `lib/model/` | The document: objects, layers, collection, assets, geometry. Plain data, no UI. |
| `lib/editor/` | The controller (state, history, operations), the pointer interactor, painting and rendering, image operations. |
| `lib/ui/` | The window: shell, toolbar, layers, collection, properties, menus. |
| `lib/io/` | Clipboard, file dialogs, the built-in sample. |
| `lib/dev/inspector.dart` | A localhost-only door for developers and agents (see below). |
| `test/` | Model, interaction, layer, cutout, project and widget tests. |
| `docs/ARCHITECTURE.md` | How it fits together and why. |
| `DRAFT.md` | The thinking behind it: questions, mockup reviews, decisions. |
| `AGENTS.md` | Notes for AI collaborators working in this repo. |
| `human_feedback/` | Test guides and returned feedback from people trying a build. |

## Watching it work (developers and agents)

Set `THINKSPACE_DEBUG_PORT` and the app listens on `127.0.0.1` only:

```bash
tool/run_headless.sh &                     # real window on a virtual display (Xvfb)
tool/ts do '{"cmd":"sample"}'              # load the storefront sample
tool/ts do '{"cmd":"drag","from":[100,500],"to":[300,380]}'
tool/ts state                              # layers, objects, selection, history as JSON
tool/ts shot window.png                    # what the window looks like
tool/xinput.py drag 420 320 700 420        # real mouse input into the real window
```

`GET /state`, `GET /screenshot`, `GET /export` and `POST /do` are documented at the top of `lib/dev/inspector.dart`.

## License

MIT — see [LICENSE](LICENSE). The bundled typefaces (Lora, JetBrains Mono, Caveat) are under the SIL Open Font License; their licences are in `assets/fonts/`.
