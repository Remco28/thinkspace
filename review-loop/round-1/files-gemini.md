Working on Thinkspace within Agent Office (gemini-1496).

### Findings

**No findings.** (0 HIGH, 0 MEDIUM, 0 LOW)

No path was found that loses work, corrupts a file, makes a file fail to open, marks a just-opened file as changed, creates phantom undo steps, or makes an old file look different from before.

---

### Checks That Came Up Clean

#### 1. Saving, Opening, and "Just-Opened" File Dirty State
- **File signature and clean open**: Verified that [`markSaved()`](file:///tmp/claude-3645/r1/gemini/lib/editor/controller.dart#L178-L186) calls [`relinkConnectors(doc)`](file:///tmp/claude-3645/r1/gemini/lib/model/connect.dart#L154-L170) before capturing `_savedSig = doc.signature()`, and [`loadProjectJson()`](file:///tmp/claude-3645/r1/gemini/lib/editor/controller.dart#L2423-L2470) calls `markSaved()` before calling `notifyListeners()`. Opening any saved file results in `dirty == false`, `canUndo == false`, and an identical signature.
- **Dangling connector recovery on load**: Tested opening a file with damaged, missing, or dangling attachment targets (`start: {'to': 'non_existent_id'}`). [`relinkConnectors`](file:///tmp/claude-3645/r1/gemini/lib/model/connect.dart#L154-L170) cleans the references before `_savedSig` is taken. The file loads with free ends, remains `dirty == false`, and does not register a false modification on open.
- **Damaged frame or connector data**: Verified [`Framed.readFrame`](file:///tmp/claude-3645/r1/gemini/lib/model/scene.dart#L217-L224), [`Attachment.tryRead`](file:///tmp/claude-3645/r1/gemini/lib/model/scene.dart#L789-L799), and [`_tryOff`](file:///tmp/claude-3645/r1/gemini/lib/model/scene.dart#L14-L22). Corrupt types, negative widths, `NaN`, or infinite coordinates fall back gracefully to default frames or free lines without throwing `FormatException` or failing to open.

#### 2. Backward and Forward Compatibility (Commit 427c4ca vs 500f942)
- **Old files opened in new build (Rule B8, C14)**: Tested loading documents created under commit `500f942` into the new build. Images and text boxes load with `border = 0` and `shadow = false`. Lines load with `start = null`, `end = null`, `anchorBend = null`. Re-saving an unmodified old file emits JSON with no extraneous `border`, `borderWidth`, `shadow`, `start`, `end`, or `anchorBend` fields.
- **New files opened in older build**: Tested loading new files containing borders, shadows, and attached/curved connectors in commit `500f942`. The older build's `Document.fromJson` reads the base box and line parameters (`p1`, `p2`, `bend`), safely ignoring unfamiliar keys. Lines render on screen identically because `p1`, `p2`, and `bend` record the true scene coordinates.
- **Visual fidelity on old files**: Checked [`paintBounds`](file:///tmp/claude-3645/r1/gemini/lib/model/scene.dart#L46-L50) vs `bounds` across rendering, export, and selection logic. When `framed` is false (`border == 0 && !shadow`), `paintBounds` returns `bounds` identically, leaving layer clipping, opacity layers, and bounds math unchanged.

#### 3. Undo / Redo and Phantom Step Prevention
- **Clicks and zero-distance gestures**: Verified that plain clicks on the canvas, clicks on object bodies, clicking on handle diamonds, and drags below movement thresholds do not create undo steps. [`endEdit()`](file:///tmp/claude-3645/r1/gemini/lib/editor/controller.dart#L496-L511) checks `token._snap.signature == doc.signature()` and aborts cleanly.
- **Short lines and tiny hide boxes**: Verified that clicking the line or cutout/hide tool without dragging drops objects shorter than 4 px or boxes under 6 px in [`_finishCreate()`](file:///tmp/claude-3645/r1/gemini/lib/editor/interactor.dart#L1031-L1045), leaving the document signature identical and avoiding phantom undo steps.
- **No-op nudging and alignments**: Verified that nudging locked selections or connectors with edge-riding ends that cannot move produces identical post-relink coordinates; signature matching prevents creating undo steps. Aligning objects that are already aligned produces no undo step.
- **Escape cancellation**: Verified [`abortEdit()`](file:///tmp/claude-3645/r1/gemini/lib/editor/controller.dart#L514-L522) restores the snapshot JSON and reinstates `dirty = wasDirty`.

#### 4. Merging and Unmerging (Rules B6, C10)
- **Baking borders into merged image**: Tested [`mergeObjects()`](file:///tmp/claude-3645/r1/gemini/lib/editor/controller.dart#L2034-L2095) with bordered and shadowed pictures. Bounds are calculated from `paintBounds.inflate(1)`, and borders are baked directly into the rendered raster image.
- **Freeing external connectors (Rule C10)**: Verified that when pictures are merged, external connectors attached to them have their attachments cleared in [`relinkConnectors()`](file:///tmp/claude-3645/r1/gemini/lib/model/connect.dart#L181-L188) because the target ID is removed from the canvas. The freed line end stays exactly where it was on the border.
- **Unmerging with scaling and flipping (Rule B6, C16)**: Tested [`unmerge()`](file:///tmp/claude-3645/r1/gemini/lib/editor/controller.dart#L2124-L2210) after moving, resizing, and flipping a merged image. Original borders and shadows are restored, `borderWidth` scales by `k = sqrt(sx * sy)`, and internal connector attachments between unmerged parts are remapped to new IDs via [`remapAttachments()`](file:///tmp/claude-3645/r1/gemini/lib/editor/controller.dart#L2199). Flipped curved marks and connectors invert their bend/anchorBend to preserve geometry.

#### 5. Copy, Paste, and Duplicate (Rule C9)
- **Duplicating connector alone vs with target**: Tested [`duplicateSelection()`](file:///tmp/claude-3645/r1/gemini/lib/editor/controller.dart#L1286-L1305) and [`pasteObjects()`](file:///tmp/claude-3645/r1/gemini/lib/editor/controller.dart#L1975-L1993). Duplicating a connector alone remaps missing target IDs to null, turning the duplicate into a free line. Duplicating a connector together with its target remaps `Attachment.to` to the duplicated target ID.
- **Between-window copy and paste**: Checked Linux multi-window flow via [`SystemClipboard`](file:///tmp/claude-3645/r1/gemini/lib/io/clipboard.dart#L18-L40). Copying a selection writes the rendered PNG (including borders, shadows, and attached marks) to the system clipboard and stores internal objects in `_clip`. When pasting in a separate Thinkspace process, `_sig(bytes) != _lastCopySig` holds true, correctly importing the rendered image without referencing foreign isolate memory or mismatched asset IDs.
- **Cutout border default (Rule B9)**: Verified that [`cutout()`](file:///tmp/claude-3645/r1/gemini/lib/editor/controller.dart#L2231-L2296) leaves the source image's border and shadow intact while the newly extracted cutout object defaults to no border (`border = 0`, `shadow = false`).

#### 6. Autosave, Recovery, and Multiple Windows
- **Per-window lock isolation**: Verified [`RecoverySlot.claim()`](file:///tmp/claude-3645/r1/gemini/lib/io/recovery.dart#L19-L34) and [`RecoverySlot.orphans()`](file:///tmp/claude-3645/r1/gemini/lib/io/recovery.dart#L49-L75). Multiple windows each hold distinct lock files; autosaving in one window never overwrites or cleans another open window's recovery copy.
- **Atomic saves**: Verified [`_writeAtomic()`](file:///tmp/claude-3645/r1/gemini/lib/editor/controller.dart#L2474-L2485) flushes to a `.tmp` file before renaming, preventing file corruption or truncation in the event of an abrupt interruption.
