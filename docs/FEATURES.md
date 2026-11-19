# Features

Everything Thinkspace does, grouped by what you are trying to do. For the reasons behind the short list, see "Why it exists" in the [README](../README.md). Shortcuts are in [KEYBOARD.md](KEYBOARD.md).

## Images

- **Images stay separate things.** Paste, drop or import images, or open up to ten with **Open...** (`Ctrl+O`). They become a new document with one layer per image, named after its file, so you can flip between them with the eye buttons. Each image is its own object that you can move, resize, rotate, fade and rename. Nothing is painted into the page until you export.
- **Screenshots without leaving.** Press `S`, or the screenshot button at the right of the toolbar. Thinkspace steps out of the way, the desktop's own picker lets you choose part of the screen, and the picture comes in as a paste does, asking where it goes. Linux only for now.
  - **From anywhere.** **Screenshot shortcut…** in the menu sets keys that take a screenshot even with Thinkspace in the background. On GNOME it becomes one of your custom keyboard shortcuts. The picture goes to the Thinkspace window you used last, or opens a new one. Elsewhere, bind `thinkspace --capture` in the desktop's keyboard settings.
- **Cut things out.** Draw around the part of an image you want, freehand or as a box, and it becomes a new object. The original stays intact. You can also click a colour to remove it, or clear a flat background in one click, then fine-tune it with a Less/More slider. It can clear the gaps inside a drawing and softens the edge, so a line drawing on white sits cleanly on any colour.
  - Cutting can leave a gap in the original. You choose whether to leave it empty or fill it with a colour.
  - Choosing the cut-out tool opens a small card in the middle of the page. It asks what to select (draw around it, a box or a colour), whether to copy or cut, and what to leave behind.
  - Pieces can be merged into a single image. A merged image can be unmerged into its original pieces until the image itself is cut or recoloured. Moving, scaling, turning and fading do not count.
- **Hide details.** The mosaic button beside Cut out makes a box that pixelates whatever is under it, or covers it with a solid colour. The box stays editable. Exports and copies carry only the hidden version.
- **A collection of source images.** Keep images you have gathered but not placed. Drag one onto the page to use it. The original stays in the collection to use again.
  - Every item has a name. Click an item to select it. `Enter` places it, `Delete` removes it and `F2` renames it on the spot.
  - Drag one item onto another to rearrange the shelf, or use `[` and `]`.
  - You can resize the collection or hide it.

## Marking up

- **Lines and arrows.** Drag the ends to resize them. `Shift` snaps to clean angles. Drag the small diamond in the middle to bend a line into a curve. It snaps back to straight, or to an even arc, when you get close.
- **Arrows that stay attached.** Drop an end on a text box, shape, marker or image and it stays attached when things move. Dropped anywhere on the edge, it aims at the middle. Dropped on one of the dots that appear at the corners and side middles, it stays on that dot. On an image it can also pin to any spot. Hold `Ctrl` for a free end.
- **Shapes, markers and a pen.** Rectangles, ellipses, numbered markers and a smoothed pen. Hold `Shift` with the pen for a straight line.
- **Text that fits.** Click with the text tool and type. The box grows with your words and starts a new line only where you press `Enter`. Drag instead, or drag a text box's side, to set a width the text wraps in. Four typefaces are available: sans, serif, mono and handwriting. Emoji are drawn in colour from the computer's colour emoji font (Noto Color Emoji on Linux).
- **A highlighter.** Press `H` and drag over text in a screenshot like a marker. A quick, nearly level pass becomes a perfectly level bar, and `Shift` gives a straight line. Switch to Box and drag a rectangle to mark a whole area. There are five colours. Writing underneath stays dark, as under a real marker. A switch turns the highlighter into a plain see-through colour for dark images.
- **Remove marks.** Press `X` and drag across pen and highlighter marks, lines, arrows, shapes and markers. They fade as you pass and go when you let go, as one undo step. Images, text, locked things and hidden layers are never touched.
- **Tools remember how you set them.** Each tool keeps its own colour, width and size, even after a restart. Changing something on the page changes its tool too. Each tool's settings end in a **Reset to default** link that turns on once something has changed.
- **Colours.** Mix any colour with the colour picker, open from the rainbow swatch, or take one from the page with the eyedropper.

## Layers and selection

- **Layers for organising.** Show or hide, reorder, lock, and move everything on a layer together: click a layer to select its contents, then drag. Drag any object onto another layer and it keeps its place on the page. A new layer goes just above the current one and opens its name for typing.
- **Lock things in place.** The padlock at the end of the selection's name tag, or `Ctrl+L`, locks it. A locked thing ignores clicks, so you can work on what is above it. Unlock it from its row in the Layers list.
- **Select the thing you mean.** Overlapping images are common. Click the same spot again, or `Alt`-click, to reach the one underneath. The selected object shows its name and layer on the page.
- **A side panel with two parts.** The layer list and the settings for the selection share the right-hand column. Drag the divider to give either more room, and double-click it to reset.

## The page

- **A page that grows with the work.** Put something past any edge and the page grows to fit it, with a little room to spare. You can turn this off on the Page settings or in the menu. An image you cropped by shrinking the page stays cropped. Drag the grips on the page edge, or type a size, to make room for a longer composition. Resizing never touches the objects on it. **Fit page to content** tightens the page again.
- **A grid when you want one.** Show it, snap to it, and hold `Ctrl` to ignore it. The grid is never part of the export.
- **Zoom and pan.** Scroll to zoom at the pointer. `Space` and drag, or a middle or right drag, pans. These change the view only and never rewrite the document.

## Undo, save and share

- **Undo that matches how you think.** One drag, one resize or one slider pull is one undo step.
- **Share it.** Export a PNG at 1x or 2x. Copy the whole page, or only the selection, to the clipboard as an image.
- **Your work survives.** A project is one editable `.thinkspace` file with its objects, layers and images. **Open recent** in the menu lists the last eight. Unsaved work is autosaved, each window on its own, and offered back after a crash. Closing with unsaved changes asks first.
- **More than one window.** `Ctrl+Shift+N` opens a new window, so you can work on two things at once.
