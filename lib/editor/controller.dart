import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:flutter/services.dart';

import '../io/clipboard.dart';
import '../io/paths.dart';
import '../model/assets.dart';
import '../model/connect.dart';
import '../model/geometry.dart';
import '../model/scene.dart';
import 'image_ops.dart';
import 'render.dart';

enum Tool {
  select,
  line,
  arrow,
  rect,
  ellipse,
  text,
  pen,
  highlight,
  remove,
  badge,
  cutout,
  hide,
}

enum CutoutMode { lasso, box, wand }

enum PasteMode { ask, layer, collection }

enum HandleKind { resize, rotate, lineStart, lineEnd, lineBend }

class HandleSpot {
  const HandleSpot(this.kind, this.pos, {this.hx = 0, this.hy = 0});
  final HandleKind kind;
  final Offset pos;
  final int hx, hy;
}

enum CanvasGrip { right, bottom, corner }

class PendingPaste {
  PendingPaste(this.assetId, this.name);
  final String assetId;
  final String name;
}

class _Snap {
  _Snap(this.json, this.signature, this.selection, this.layerId, this.label);
  final String json;
  final String signature;
  final List<String> selection;
  final String layerId;
  final String label;
}

/// Opaque token for an in-progress gesture or edit.
class EditToken {
  EditToken._(this._snap);
  final _Snap _snap;
}

const List<int> kPalette = [
  0xFFE53935, // red
  0xFFFB8C00, // orange
  0xFFFDD835, // yellow
  0xFF43A047, // green
  0xFF1E88E5, // blue
  0xFF8E24AA, // purple
  0xFFFFFFFF, // white
  0xFF9E9E9E, // grey
  0xFF222222, // near black
];

/// The five highlighter colours.
const List<int> kHighlightPalette = [
  0xFFFFF200, // yellow
  0xFF8BE04E, // green
  0xFFFF7EC8, // pink
  0xFF5CC8FF, // blue
  0xFFFFB347, // orange
];

/// How the next thing a tool makes looks. Each tool keeps its own, so a thick
/// red arrow does not make the next pen stroke thick and red. Not every tool
/// uses every field: [size] is the text size, the marker size or the size of
/// Hide details' tiles; [box], [keepText] are the highlighter's; [solid] is
/// Hide details' choice of a plain cover.
class ToolStyle {
  ToolStyle({
    required this.color,
    this.width = 5,
    this.fill = 0,
    this.size = 0,
    this.font = TextFont.sans,
    this.box = false,
    this.keepText = true,
    this.solid = false,
  });

  int color;
  double width;
  int fill;
  double size;
  TextFont font;
  bool box;
  bool keepText;
  bool solid;

  ToolStyle copy() => ToolStyle(
    color: color,
    width: width,
    fill: fill,
    size: size,
    font: font,
    box: box,
    keepText: keepText,
    solid: solid,
  );

  Map<String, dynamic> toJson() => {
    'color': color,
    'width': width,
    'fill': fill,
    'size': size,
    'font': font.name,
    'box': box,
    'keepText': keepText,
    'solid': solid,
  };

  /// Take what is readable from [j]; anything missing or odd stays as it is.
  void read(Object? j) {
    if (j is! Map) return;
    T? get<T>(String k) => j[k] is T ? j[k] as T : null;
    color = get<int>('color') ?? color;
    width = get<num>('width')?.toDouble() ?? width;
    fill = get<int>('fill') ?? fill;
    size = get<num>('size')?.toDouble() ?? size;
    font = j['font'] is String ? TextFont.byName(j['font']) : font;
    box = get<bool>('box') ?? box;
    keepText = get<bool>('keepText') ?? keepText;
    solid = get<bool>('solid') ?? solid;
  }

  bool sameAs(ToolStyle o) => jsonEncode(toJson()) == jsonEncode(o.toJson());
}

/// What each tool starts with, and goes back to on "Reset to default".
Map<Tool, ToolStyle> defaultToolStyles() => {
  for (final t in [Tool.line, Tool.arrow, Tool.rect, Tool.ellipse, Tool.pen])
    t: ToolStyle(color: kPalette[0]),
  Tool.badge: ToolStyle(color: kPalette[0], size: 44),
  Tool.text: ToolStyle(color: 0xFF222222, size: 28),
  Tool.highlight: ToolStyle(color: kHighlightPalette.first, width: 26),
  Tool.hide: ToolStyle(color: 0xFF222222, size: 14),
};

class EditorController extends ChangeNotifier {
  EditorController() {
    doc = Document.blank();
    currentLayerId = doc.layers.first.id;
    _savedSig = doc.signature();
  }

  /// The document as it was when last saved (or opened); null when the
  /// current work has never been saved anywhere.
  String? _savedSig;

  /// Note that what is on the page now is what is on disk.
  void markSaved() {
    // A file whose connectors were out of step (a dangling one, say) is put
    // right before its signature is taken, so it does not open as changed.
    relinkConnectors(doc);
    _savedSig = doc.signature();
    dirty = false;
  }

  late Document doc;
  final AssetStore assets = AssetStore();

  // --- selection & tools -------------------------------------------------
  List<String> _selection = [];
  List<String> get selection => _selection;

  /// Whatever sets the selection, the collection shelf lets go when something
  /// on the page is picked: the keys never act on two things at once.
  set selection(List<String> ids) {
    _selection = ids;
    if (ids.isNotEmpty) _collectionSel = null;
  }

  late String currentLayerId;
  Tool tool = Tool.select;
  bool toolLocked = false;
  CutoutMode cutoutMode = CutoutMode.lasso;

  /// The page-edge handle under the pointer, and the one being dragged, so
  /// they can be drawn lit.
  CanvasGrip? hoverGrip, draggingGrip;

  /// The last thing pressed on the page was a finger: handles are drawn bigger
  /// and things are easier to hit.
  bool touchInput = false;

  /// The options card for the cut-out tool is showing.
  bool cutoutOptionsOpen = false;
  bool cutoutLeavesHole = false;

  /// What to put where a cut-out piece came from (when it leaves a hole).
  HoleFill cutoutFill = HoleFill.empty;
  int cutoutFillColor = 0xFFFFFFFF;
  double wandTolerance = 0.14;
  bool wandContiguous = true;

  /// Background removal also clears roomy background-coloured pockets that
  /// the outside cannot reach (the gaps inside a drawing's outline).
  bool bgInside = true;
  String? editingTextId;

  // --- view ---------------------------------------------------------------
  double zoom = 1;
  Offset pan = Offset.zero;
  Size viewport = Size.zero;
  bool showGrid = false;
  bool snapOn = false;
  bool autoGrow = false;
  bool _fitPending = true;

  // --- defaults for new things --------------------------------------------
  /// Each tool's look for the next thing it makes. Changing something on the
  /// page changes its tool's too, so the next one comes out the same.
  final Map<Tool, ToolStyle> toolStyles = defaultToolStyles();

  ToolStyle styleOf(Tool t) => toolStyles[t] ??= ToolStyle(color: kPalette[0]);

  /// The tool that makes things like [o], whose look the next one copies.
  static Tool? toolFor(SceneObject o) => switch (o) {
    LineObject l => l.headEnd ? Tool.arrow : Tool.line,
    StrokeObject s =>
      s.highlight == HighlightStyle.none ? Tool.pen : Tool.highlight,
    ShapeObject s =>
      s.highlight != HighlightStyle.none
          ? Tool.highlight
          : s.ellipse
          ? Tool.ellipse
          : Tool.rect,
    BadgeObject _ => Tool.badge,
    TextObject _ => Tool.text,
    HideObject _ => Tool.hide,
    _ => null,
  };

  /// Change the look [o]'s tool will use next.
  void rememberStyle(SceneObject o, void Function(ToolStyle s) f) {
    final t = toolFor(o);
    if (t != null) f(styleOf(t));
  }

  bool styleIsDefault(Tool t) {
    final d = defaultToolStyles()[t];
    return d == null || styleOf(t).sameAs(d);
  }

  void resetToolStyle(Tool t) {
    final d = defaultToolStyles()[t];
    if (d == null) return;
    toolStyles[t] = d;
    notifyListeners();
  }

  Map<String, dynamic> toolStylesJson() => {
    for (final e in toolStyles.entries) e.key.name: e.value.toJson(),
  };

  void readToolStyles(Object? j) {
    if (j is! Map) return;
    for (final t in Tool.values) {
      if (j[t.name] != null) styleOf(t).read(j[t.name]);
    }
  }

  int get textColor => styleOf(Tool.text).color;
  set textColor(int v) => styleOf(Tool.text).color = v;
  double get textSize => styleOf(Tool.text).size;
  set textSize(double v) => styleOf(Tool.text).size = v;
  TextFont get textFont => styleOf(Tool.text).font;
  set textFont(TextFont v) => styleOf(Tool.text).font = v;
  double get markerSize => styleOf(Tool.badge).size;
  set markerSize(double v) => styleOf(Tool.badge).size = v;

  // The highlighter: colour, marker width, marker or box, and whether writing
  // under it stays dark (multiply) or the colour is simply see-through.
  int get hlColor => styleOf(Tool.highlight).color;
  set hlColor(int v) => styleOf(Tool.highlight).color = v;
  double get hlWidth => styleOf(Tool.highlight).width;
  set hlWidth(double v) => styleOf(Tool.highlight).width = v;
  bool get hlBox => styleOf(Tool.highlight).box;
  set hlBox(bool v) => styleOf(Tool.highlight).box = v;
  bool get hlKeepText => styleOf(Tool.highlight).keepText;
  set hlKeepText(bool v) => styleOf(Tool.highlight).keepText = v;

  PasteMode pasteMode = PasteMode.ask;
  PendingPaste? pendingPaste;

  /// Projects opened or saved lately, newest first.
  List<String> recentFiles = [];
  static const int maxRecentFiles = 8;

  void noteRecent(String path) {
    final p = File(path).absolute.path;
    recentFiles = [
      p,
      ...recentFiles.where((r) => r != p),
    ].take(maxRecentFiles).toList();
  }

  void forgetRecent(String path) {
    recentFiles = recentFiles.where((r) => r != path).toList();
    notifyListeners();
  }

  // --- transient overlays drawn by the canvas -------------------------------
  Rect? marquee;
  List<Offset>? lasso;
  Rect? cutBox;
  Offset? snapGuideX, snapGuideY;

  // --- file ----------------------------------------------------------------
  String? filePath;
  bool dirty = false;

  // --- messages ------------------------------------------------------------
  String? toastMessage;
  Timer? _toastTimer;

  /// Where unsaved work is kept so a crash doesn't lose it. Null disables it.
  File? recoveryFile;
  Timer? _autosaveTimer;
  bool _needsAutosave = false;

  final List<_Snap> _undo = [];
  final List<_Snap> _redo = [];
  EditToken? _textEditToken;
  List<SceneObject> _clip = [];
  int _pasteCount = 0;
  int _lastCopySig = 0;

  String? get undoLabel => _undo.isEmpty ? null : _undo.last.label;
  String? get redoLabel => _redo.isEmpty ? null : _redo.last.label;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  int get undoDepth => _undo.length;
  int get redoDepth => _redo.length;

  Layer get currentLayer => doc.layerById(currentLayerId) ?? doc.layers.last;

  List<SceneObject> get selectedObjects => [
    for (final id in selection)
      if (doc.objectById(id) != null) doc.objectById(id)!,
  ];

  SceneObject? get single =>
      selection.length == 1 ? doc.objectById(selection.first) : null;

  Rect get selectionBounds => unionRects(selectedObjects.map((o) => o.bounds));

  @override
  void dispose() {
    finishColourPick(null);
    _toastTimer?.cancel();
    _autosaveTimer?.cancel();
    super.dispose();
  }

  // ===== memory ============================================================

  /// Forget pictures nothing can bring back: not on the page, not in the
  /// collection, not in any undo or redo step, not on the internal clipboard.
  /// Recently made ones are kept, since an edit may be about to use them.
  void pruneAssets({Duration minAge = const Duration(minutes: 2)}) {
    final keep = <String>{...doc.usedAssets};
    final pp = pendingPaste;
    if (pp != null) keep.add(pp.assetId);
    for (final o in _clip) {
      if (o is ImageObject) {
        keep.add(o.assetId);
        if (o.canUnmerge) keep.addAll(o.merged!.assets);
      }
    }
    final ref = RegExp(r'"asset":"([^"]+)"');
    for (final snap in [..._undo, ..._redo]) {
      for (final m in ref.allMatches(snap.json)) {
        keep.add(m.group(1)!);
      }
    }
    assets.retain(keep, minAge);
  }

  // ===== recovery ==========================================================

  void startAutosave(
    File file, {
    Duration every = const Duration(seconds: 20),
  }) {
    recoveryFile = file;
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer.periodic(every, (_) {
      pruneAssets();
      autosaveNow();
    });
  }

  Future<void> autosaveNow() async {
    final f = recoveryFile;
    if (f == null || !_needsAutosave || !dirty) return;
    _needsAutosave = false;
    try {
      await f.parent.create(recursive: true);
      await _writeAtomic(f, projectJson());
    } catch (_) {}
  }

  void clearRecovery() {
    _needsAutosave = false;
    try {
      recoveryFile?.deleteSync();
    } catch (_) {}
  }

  /// If a previous session left unsaved work behind, load it. Returns when it
  /// was written, or null if there was nothing to restore.
  DateTime? pendingRecovery() {
    final f = recoveryFile;
    try {
      if (f == null || !f.existsSync()) return null;
      return f.lastModifiedSync();
    } catch (_) {
      return null;
    }
  }

  /// Load unsaved work back: this window's own copy, or [from], one left by
  /// a window that did not close properly.
  Future<void> restoreRecovery({File? from}) async {
    final f = from ?? recoveryFile;
    if (f == null) return;
    await loadProjectJson(await f.readAsString());
    _savedSig = null; // it has never been saved under a real name
    dirty = true;
    _needsAutosave = true;
    notifyListeners();
  }

  void notify() => notifyListeners();

  /// Every change is drawn through here, so attached line ends are put in
  /// step first: whatever moved, what is attached to it follows.
  @override
  void notifyListeners() {
    relinkConnectors(doc);
    super.notifyListeners();
  }

  void showToast(String msg) {
    toastMessage = msg;
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 3), () {
      toastMessage = null;
      notifyListeners();
    });
    notifyListeners();
  }

  // ===== history ===========================================================

  _Snap _capture(String label) => _Snap(
    doc.encode(),
    doc.signature(),
    List.of(selection),
    currentLayerId,
    label,
  );

  EditToken beginEdit(String label) {
    _editsBegun++;
    return EditToken._(_capture(label));
  }

  /// How many edits have begun, ever: a merge that takes a while checks it
  /// did not overlap one (even one that has changed nothing yet).
  int _editsBegun = 0;

  /// Record [token]'s state for undo if the document changed since.
  void endEdit(EditToken token) {
    // The moved ends of connectors belong to the same undo step.
    relinkConnectors(doc);
    // Resizing the page by hand is a deliberate choice; never undo it.
    if (autoGrow && token._snap.label != 'resize canvas') _growToFit();
    if (token._snap.signature == doc.signature()) {
      notifyListeners();
      return;
    }
    _undo.add(token._snap);
    if (_undo.length > 300) _undo.removeAt(0);
    _redo.clear();
    dirty = true;
    _needsAutosave = true;
    notifyListeners();
  }

  /// Throw away everything since [token] (e.g. Escape during a drag).
  void abortEdit(EditToken token) {
    final wasDirty = dirty;
    _restore(token._snap);
    dirty = wasDirty;
    marquee = null;
    lasso = null;
    cutBox = null;
    notifyListeners();
  }

  T transact<T>(String label, T Function() fn) {
    final t = beginEdit(label);
    final T r;
    try {
      r = fn();
    } catch (_) {
      abortEdit(t); // never leave a half-made edit with no undo step
      rethrow;
    }
    endEdit(t);
    return r;
  }

  void _restore(_Snap s) {
    doc = Document.decode(s.json);
    selection = s.selection.where((id) => doc.objectById(id) != null).toList();
    currentLayerId = doc.layerById(s.layerId) != null
        ? s.layerId
        : doc.layers.last.id;
    editingTextId = null;
    dirty = _savedSig == null || doc.signature() != _savedSig;
  }

  void undo({bool quiet = false}) {
    finishTextEdit();
    if (_undo.isEmpty) return;
    final s = _undo.removeLast();
    _redo.add(_capture(s.label));
    _restore(s);
    if (!quiet) showToast('Undid ${s.label}');
  }

  void redo() {
    finishTextEdit();
    if (_redo.isEmpty) return;
    final s = _redo.removeLast();
    _undo.add(_capture(s.label));
    _restore(s);
    showToast('Redid ${s.label}');
  }

  // ===== selection =========================================================

  void select(List<String> ids) {
    if (editingTextId != null &&
        !(ids.length == 1 && ids.first == editingTextId)) {
      finishTextEdit();
    }
    selection = ids;
    _listSel = null;
    _pickedLayer = null;
    if (ids.length == 1) {
      final l = doc.layerOf(ids.first);
      if (l != null) currentLayerId = l.id;
    }
    notifyListeners();
  }

  // ---- selecting from the Layers list -------------------------------------

  /// Layers whose rows are folded away in the Layers panel.
  final Set<String> collapsedLayers = {};

  /// True after a row in the Layers list was clicked, until the selection
  /// changes some other way: the arrow keys then walk the list, as in any
  /// file list, instead of nudging the selection on the page.
  bool get listFocus => _listSel != null && listEquals(selection, _listSel);

  /// What the list itself last selected. The arrows walk the list only while
  /// the selection is still exactly that, so merging, undoing, pasting or
  /// clicking on the page all hand them back to nudging without anyone
  /// having to remember to switch the mode off.
  List<String>? _listSel;

  /// A click on the page: the arrows nudge again, even if it picked the very
  /// same things the list had.
  void endListWalk() => _listSel = null;
  String? _listAnchor, _listCursor;

  /// Object ids in the order the Layers panel shows them (top layer first,
  /// topmost object first), skipping folded layers.
  List<String> get listOrder => [
    for (final l in doc.layers.reversed)
      if (!collapsedLayers.contains(l.id))
        for (final o in l.objects.reversed) o.id,
  ];

  /// A click on a row: plain selects it, Ctrl toggles it, Shift selects
  /// everything between the last clicked row and this one.
  void clickListRow(String id, {bool shift = false, bool ctrl = false}) {
    final order = listOrder;
    // The run starts from the last row clicked in the list, or, if the
    // selection has moved on since, from what is selected now.
    final anchor = listFocus
        ? _listAnchor
        : (selection.isEmpty ? null : selection.last);
    if (shift && anchor != null && order.contains(anchor)) {
      select(_between(order, anchor, id));
      _listCursor = id;
    } else if (ctrl) {
      toggleSelect(id);
      _listAnchor = _listCursor = id;
    } else {
      select([id]);
      _listAnchor = _listCursor = id;
    }
    _listSel = List.of(selection);
  }

  static List<String> _between(List<String> order, String a, String b) {
    var i = order.indexOf(a), j = order.indexOf(b);
    if (i < 0 || j < 0) return [b];
    if (i > j) (i, j) = (j, i);
    return order.sublist(i, j + 1);
  }

  /// Arrow up/down in the Layers list; [extend] (Shift) grows the selection
  /// from where the walk began.
  void listStep(int dir, {bool extend = false}) {
    final order = listOrder;
    if (order.isEmpty) return;
    var cursor = _listCursor;
    if (cursor == null || !order.contains(cursor)) {
      cursor = selection.isEmpty ? null : selection.last;
    }
    var i = cursor == null
        ? (dir > 0 ? -1 : order.length)
        : order.indexOf(cursor);
    if (i < 0 && cursor != null) i = dir > 0 ? -1 : order.length;
    final n = (i + dir).clamp(0, order.length - 1);
    final id = order[n];
    final anchor = extend ? (_listAnchor ?? cursor ?? id) : id;
    select(extend ? _between(order, anchor, id) : [id]);
    _listAnchor = anchor;
    _listCursor = id;
    _listSel = List.of(selection);
    notifyListeners();
  }

  void clearSelection() => select([]);

  void toggleSelect(String id) {
    final s = List.of(selection);
    s.contains(id) ? s.remove(id) : s.add(id);
    select(s);
  }

  void selectAll() => select([
    for (final l in doc.layers)
      if (l.visible && !l.locked)
        for (final o in l.objects)
          if (o.visible && !o.locked) o.id,
  ]);

  void selectLayerContents(String layerId) {
    final l = doc.layerById(layerId);
    if (l == null) return;
    currentLayerId = layerId;
    selection = [
      for (final o in l.objects)
        if (o.visible && !o.locked) o.id,
    ];
    _pickedLayer = layerId;
    _pickedLayerSel = List.of(selection);
    notifyListeners();
  }

  /// The layer whose row was the last thing clicked, while the selection is
  /// still what that click picked: F2 then renames the layer, not an object.
  String? get pickedLayer =>
      _pickedLayer != null && listEquals(selection, _pickedLayerSel)
      ? _pickedLayer
      : null;
  String? _pickedLayer;
  List<String> _pickedLayerSel = const [];

  // ---- renaming in place ----------------------------------------------------

  /// The layer or object whose name is open for typing in the Layers list.
  String? renamingId;

  /// Counts renames begun, so the Layers list scrolls to each one once.
  int renameCount = 0;

  /// Open [id]'s name (a layer or an object) for typing in the Layers list,
  /// unfolding its layer so the row can be seen.
  void beginRename(String id) {
    final layer = doc.layerById(id) ?? doc.layerOf(id);
    if (layer == null) return;
    if (layer.id != id) collapsedLayers.remove(layer.id);
    renamingId = id;
    renameCount++;
    notifyListeners();
  }

  void endRename() {
    if (renamingId == null) return;
    renamingId = null;
    notifyListeners();
  }

  // ===== remove marks ======================================================

  /// What a Remove marks drag has brushed over so far: drawn faded, and taken
  /// away when the drag ends.
  final Set<String> removing = {};

  /// How far from its centre the Remove marks pointer reaches, on screen.
  double get removeRadius => touchInput ? 18 : 10;

  /// Remove marks takes away what was drawn on top: pen and highlighter
  /// marks, lines and arrows, shapes and markers. Pictures and text stay;
  /// those are removed with Delete, on purpose.
  /// Hide details boxes stay too: a sweep over pen marks must never uncover
  /// a password.
  static bool removable(SceneObject o) =>
      o is! ImageObject && o is! TextObject && o is! HideObject;

  /// Mark everything removable within reach of the stretch from [a] to [b]
  /// (page coordinates). True if anything new was marked.
  bool brushRemove(Offset a, Offset b) {
    final r = removeRadius / zoom;
    final steps = math.max(1, ((b - a).distance / (r / 2)).ceil());
    var added = false;
    for (final layer in doc.layers) {
      if (!layer.visible || layer.locked) continue;
      for (final o in layer.objects) {
        if (!o.visible || o.locked || !removable(o)) continue;
        if (removing.contains(o.id)) continue;
        if (!o.bounds.inflate(r).overlaps(Rect.fromPoints(a, b).inflate(r))) {
          continue;
        }
        for (int i = 0; i <= steps; i++) {
          if (o.hitTest(Offset.lerp(a, b, i / steps)!, r, assets)) {
            removing.add(o.id);
            added = true;
            break;
          }
        }
      }
    }
    return added;
  }

  /// Take away what the drag marked. False if nothing was.
  bool finishRemove() {
    if (removing.isEmpty) return false;
    final gone = Set.of(removing);
    removing.clear();
    for (final layer in doc.layers) {
      layer.objects.removeWhere((o) => gone.contains(o.id));
    }
    selection = selection.where((id) => !gone.contains(id)).toList();
    return true;
  }

  // ===== eyedropper ========================================================

  Completer<int?>? _colourPick;
  ByteData? _pickPixels;
  int _pickW = 0, _pickH = 0;

  /// Waiting for a click on the page to take a colour from.
  bool get pickingColour => _colourPick != null;

  /// Where the pointer is on screen, while the eyedropper or Remove marks
  /// draws its own pointer; and the colour under it while picking.
  Offset? pointerScreen;
  int? pickHoverColour;

  /// The eyedropper: the next click on the page answers with the colour
  /// there, as the page looks (every visible layer together). Escape, or a
  /// click off the page, answers null. The page is drawn once up front so
  /// the colour under the pointer can be shown as it moves.
  Future<int?> pickColourFromPage() {
    finishColourPick(null);
    final done = Completer<int?>();
    _colourPick = done;
    showToast('Click on the page to take its colour (Esc to cancel)');
    () async {
      final img = await renderDocument(doc, assets);
      final px = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (_colourPick == done) {
        _pickPixels = px;
        _pickW = img.width;
        _pickH = img.height;
      }
      img.dispose();
      notifyListeners();
    }();
    notifyListeners();
    return done.future;
  }

  /// The colour the page shows at [scene], or null off the page or before it
  /// has been drawn. Where nothing is painted the page counts as white, as
  /// on screen.
  int? colourAt(Offset scene) {
    final px = _pickPixels;
    final x = scene.dx.floor(), y = scene.dy.floor();
    if (px == null || x < 0 || y < 0 || x >= _pickW || y >= _pickH) {
      return null;
    }
    final i = (y * _pickW + x) * 4;
    // Raw RGBA is premultiplied: over white, each channel gains (255 - a).
    final a = px.getUint8(i + 3);
    int ch(int k) => (px.getUint8(i + k) + 255 - a).clamp(0, 255);
    return 0xFF000000 | ch(0) << 16 | ch(1) << 8 | ch(2);
  }

  void finishColourPick(int? argb) {
    final done = _colourPick;
    if (done == null) return;
    _colourPick = null;
    _pickPixels = null;
    pointerScreen = null;
    pickHoverColour = null;
    done.complete(argb);
    notifyListeners();
  }

  void setTool(Tool t, {bool lock = false}) {
    finishTextEdit();
    finishColourPick(null);
    removing.clear();
    // Nothing is picked while removing marks: a selection box around a mark
    // that is fading away only confuses.
    if (t == Tool.remove) selection = [];
    // Choosing the cut-out tool opens its options first, so the choices
    // (what shape, cut or copy, what to leave behind) are made before drawing.
    if (t == Tool.cutout && tool != Tool.cutout) cutoutOptionsOpen = true;
    if (t != Tool.cutout) cutoutOptionsOpen = false;
    tool = t;
    toolLocked = lock && t != Tool.select;
    lasso = null;
    cutBox = null;
    notifyListeners();
  }

  void toolDone() {
    if (!toolLocked) tool = Tool.select;
  }

  // ===== hit testing =======================================================

  /// Everything under [p], topmost first.
  List<SceneObject> objectsAt(Offset p) {
    final tol = (touchInput ? 12 : 4) / zoom;
    final out = <SceneObject>[];
    for (final layer in doc.layers.reversed) {
      if (!layer.visible || layer.locked) continue;
      for (final o in layer.objects.reversed) {
        if (!o.visible || o.locked) continue;
        if (o.hitTest(p, tol, assets) || (o is Framed && o.onBorder(p, tol))) {
          out.add(o);
        }
      }
    }
    return out;
  }

  /// The object a line's end dropped at [p] attaches to: the topmost one it
  /// can attach to, locked ones included (hidden ones not). Pictures count
  /// where they are not see-through, and on their border; an unfilled
  /// rectangle or ellipse only near its outline, so an end dropped inside a
  /// frame reaches what is in it. [exclude] is the line itself. With
  /// [picturesOnly], only pictures count, and everything else is passed
  /// through.
  BoxObject? attachTargetAt(
    Offset p, {
    String? exclude,
    bool picturesOnly = false,
  }) {
    final reach = (touchInput ? 20 : 9) / zoom;
    for (final layer in doc.layers.reversed) {
      if (!layer.visible) continue;
      for (final o in layer.objects.reversed) {
        if (!o.visible || o.id == exclude || !canAttachTo(o)) continue;
        o as BoxObject;
        if (picturesOnly && o is! ImageObject) continue;
        final hit = switch (o) {
          ImageObject() => o.hitTest(p, 0, assets) || o.onBorder(p, reach),
          ShapeObject() => o.hitTest(p, reach, assets),
          _ => _withinOutline(o, p, reach),
        };
        if (hit) return o;
      }
    }
    return null;
  }

  static bool _withinOutline(BoxObject o, Offset p, double reach) {
    final out = outlineOf(o);
    final l = o.toLocal(p);
    final hw = out.hw + reach, hh = out.hh + reach;
    if (out.round) {
      final x = l.dx / hw, y = l.dy / hh;
      return x * x + y * y <= 1;
    }
    final ax = l.dx.abs(), ay = l.dy.abs();
    if (ax > hw || ay > hh) return false;
    // Past a round corner's arc is outside it.
    final r = out.corner + reach;
    final cx = hw - r, cy = hh - r;
    if (out.corner > 0 && ax > cx && ay > cy) {
      return Offset(ax - cx, ay - cy).distance <= r;
    }
    return true;
  }

  /// The object a line end is about to attach to, outlined while dragging.
  String? attachHover;

  /// Before moving [moving] (lines among it) without the pictures their pins
  /// are on: take those pins off, so the ends can move. [repin] puts them
  /// back where the ends end up. A pin whose picture moves too keeps it.
  /// [group] is everything moving together, if more than [moving] itself (an
  /// align moves some of the selection by nothing): a pin on any of it is
  /// kept.
  Map<String, (Attachment?, Attachment?)> holdPins(
    Iterable<SceneObject> moving, {
    Iterable<SceneObject>? group,
  }) {
    final ids = {for (final o in group ?? moving) o.id};
    bool held(Attachment? a) => a != null && a.pinned && !ids.contains(a.to);
    final out = <String, (Attachment?, Attachment?)>{};
    for (final o in moving) {
      if (o is! LineObject || o.locked) continue;
      final s = held(o.start) ? o.start : null;
      final e = held(o.end) ? o.end : null;
      if (s == null && e == null) continue;
      out[o.id] = (s, e);
      if (s != null) o.start = null;
      if (e != null) o.end = null;
    }
    return out;
  }

  /// Pin the ends [holdPins] took off again where they are now: on the
  /// picture under them (passing through text, shapes and markers, so a mark
  /// on a picture stays one), or free if there is none. A pin on a hidden
  /// picture stays on that picture.
  void repin(Map<String, (Attachment?, Attachment?)> held) {
    for (final e in held.entries) {
      final l = doc.objectById(e.key);
      if (l is! LineObject) continue;
      Attachment? again(Attachment? was, Offset at) {
        if (was == null) return null;
        final old = doc.objectById(was.to);
        final layer = doc.layerOf(was.to);
        if (old is BoxObject && (!old.visible || layer?.visible == false)) {
          return Attachment(old.id, pinAt(old, at));
        }
        final t = attachTargetAt(at, exclude: l.id, picturesOnly: true);
        return t == null ? null : attachmentFor(t, at);
      }

      final (s, en) = e.value;
      if (s != null) l.start = again(s, l.p1);
      if (en != null) l.end = again(en, l.p2);
    }
  }

  List<HandleSpot> handlesFor(SceneObject o) {
    if (o is LineObject) {
      return [
        HandleSpot(HandleKind.lineStart, o.p1),
        HandleSpot(HandleKind.lineEnd, o.p2),
        // Too short on screen and the middle would crowd the ends.
        if (o.curved || o.length * zoom >= 40)
          HandleSpot(HandleKind.lineBend, o.mid),
      ];
    }
    if (o is BoxObject) {
      final hw = o.size.width / 2, hh = o.size.height / 2;
      final out = <HandleSpot>[];
      final isText = o is TextObject;
      for (final hy in [-1, 0, 1]) {
        for (final hx in [-1, 0, 1]) {
          if (hx == 0 && hy == 0) continue;
          if (isText && hy != 0 && hx == 0) {
            continue; // text height follows its content
          }
          if (o is BadgeObject && (hx == 0 || hy == 0)) {
            continue; // a marker stays round
          }
          out.add(
            HandleSpot(
              HandleKind.resize,
              o.toScene(Offset(hx * hw, hy * hh)),
              hx: hx,
              hy: hy,
            ),
          );
        }
      }
      out.add(
        HandleSpot(HandleKind.rotate, o.toScene(Offset(0, -hh - 30 / zoom))),
      );
      return out;
    }
    return const [];
  }

  Map<CanvasGrip, Offset> get gripPositions => {
    CanvasGrip.right: Offset(doc.canvasSize.width, doc.canvasSize.height / 2),
    CanvasGrip.bottom: Offset(doc.canvasSize.width / 2, doc.canvasSize.height),
    CanvasGrip.corner: Offset(doc.canvasSize.width, doc.canvasSize.height),
  };

  // ===== view ==============================================================

  Offset toScene(Offset screen) => (screen - pan) / zoom;
  Offset toScreen(Offset scene) => scene * zoom + pan;

  Offset get viewCenterScene =>
      toScene(Offset(viewport.width / 2, viewport.height / 2));

  void setViewport(Size s) {
    if (s == viewport) return;
    viewport = s;
    if (_fitPending && s.width > 50 && s.height > 50) {
      _fitPending = false;
      fitToView(notify: false);
      // We're inside a build; tell the zoom label once the frame is done.
      WidgetsBinding.instance.addPostFrameCallback((_) => notifyListeners());
    }
  }

  void fitToView({bool notify = true}) {
    if (viewport.isEmpty) {
      _fitPending = true;
      return;
    }
    const margin = 56.0;
    final cw = doc.canvasSize.width, ch = doc.canvasSize.height;
    zoom = math
        .min(
          (viewport.width - margin * 2) / cw,
          (viewport.height - margin * 2) / ch,
        )
        .clamp(0.02, 8.0);
    pan = Offset(
      (viewport.width - cw * zoom) / 2,
      (viewport.height - ch * zoom) / 2,
    );
    if (notify) notifyListeners();
  }

  void zoomTo(double z, {Offset? anchorScreen}) {
    final a = anchorScreen ?? Offset(viewport.width / 2, viewport.height / 2);
    final sceneAnchor = toScene(a);
    zoom = z.clamp(0.02, 16.0);
    pan = a - sceneAnchor * zoom;
    notifyListeners();
  }

  void panBy(Offset d) {
    pan += d;
    notifyListeners();
  }

  void toggleGrid() {
    showGrid = !showGrid;
    notifyListeners();
  }

  void toggleSnap() {
    snapOn = !snapOn;
    showToast(snapOn ? 'Snapping on' : 'Snapping off');
  }

  // ===== naming / adding objects ===========================================

  String uniqueName(String base) {
    final names = {for (final o in doc.allObjects) o.name};
    var n = 1;
    while (names.contains('$base $n')) {
      n++;
    }
    return '$base $n';
  }

  void _addToLayer(SceneObject o, [Layer? layer]) {
    final l = layer ?? currentLayer;
    l.objects.add(o);
  }

  /// Add [o] to the current layer and select it, as one undo step.
  T addObject<T extends SceneObject>(T o, {String label = 'add'}) {
    transact(label, () {
      _addToLayer(o);
      selection = [o.id];
    });
    return o;
  }

  // ===== layers ============================================================

  /// The layer just made (added or duplicated), and a count that goes up
  /// each time, so the layers panel can bring it into view, point it out and
  /// offer its name for typing: a new layer lands just above the current one,
  /// which is not always where the eye is.
  String? freshLayerId;
  int freshLayerCount = 0;

  void _madeLayer(Layer l) {
    currentLayerId = l.id;
    freshLayerId = l.id;
    freshLayerCount++;
  }

  void addLayer() => transact('add layer', () {
    final idx = doc.layers.indexWhere((l) => l.id == currentLayerId);
    final n = doc.layers.length + 1;
    final layer = Layer(id: doc.newId('l'), name: 'Layer $n');
    doc.layers.insert(idx < 0 ? doc.layers.length : idx + 1, layer);
    _madeLayer(layer);
  });

  void deleteLayer(String id) {
    if (doc.layers.length <= 1) {
      showToast('A document needs at least one layer');
      return;
    }
    transact('delete layer', () {
      final gone = doc.layerById(id);
      if (gone == null) return;
      final removedIds = gone.objects.map((o) => o.id).toSet();
      doc.layers.remove(gone);
      selection = selection.where((s) => !removedIds.contains(s)).toList();
      if (currentLayerId == id) currentLayerId = doc.layers.last.id;
    });
  }

  void renameLayer(String id, String name) => transact('rename layer', () {
    final l = doc.layerById(id);
    if (l != null && name.trim().isNotEmpty) l.name = name.trim();
  });

  void setLayerVisible(String id, bool v) =>
      transact(v ? 'show layer' : 'hide layer', () {
        doc.layerById(id)?.visible = v;
        if (!v) {
          final ids = doc.layerById(id)?.objects.map((o) => o.id).toSet() ?? {};
          selection = selection.where((s) => !ids.contains(s)).toList();
        }
      });

  void setLayerLocked(String id, bool v) =>
      transact(v ? 'lock layer' : 'unlock layer', () {
        doc.layerById(id)?.locked = v;
        if (v) {
          final ids = doc.layerById(id)?.objects.map((o) => o.id).toSet() ?? {};
          selection = selection.where((s) => !ids.contains(s)).toList();
        }
      });

  /// [from] and [to] index the layers bottom-to-top.
  void moveLayer(int from, int to) {
    if (from == to ||
        from < 0 ||
        to < 0 ||
        from >= doc.layers.length ||
        to >= doc.layers.length) {
      return;
    }
    transact('reorder layer', () {
      final l = doc.layers.removeAt(from);
      doc.layers.insert(to, l);
    });
  }

  /// A copy of the layer with copies of everything on it, just above it —
  /// handy for trying a variation without losing the first idea.
  void duplicateLayer(String id) {
    final src = doc.layerById(id);
    if (src == null) return;
    transact('duplicate layer', () {
      final map = <String, String>{};
      final copy = Layer(
        id: doc.newId('l'),
        name: '${src.name} copy',
        visible: src.visible,
        locked: src.locked,
        objects: [
          for (final o in src.objects)
            o.copyWith(id: map[o.id] = doc.newId('o')),
        ],
      );
      remapAttachments(copy.objects, map);
      doc.layers.insert(doc.layers.indexOf(src) + 1, copy);
      _madeLayer(copy);
      selection = [for (final o in copy.objects) o.id];
    });
  }

  /// Line objects up. With several selected they align to each other; with
  /// one, to the page. [how] is left, centre, right, top, middle or bottom.
  /// Whether Align lines the selection up with the page (one thing, with any
  /// lines it carries) rather than with each other.
  bool get alignsToPage {
    final selected = {for (final o in selectedObjects) o.id};
    final own = selectedObjects.where(
      (o) => !o.locked && !_carriedBy(o, selected),
    );
    return own.length <= 1;
  }

  static bool _carriedBy(SceneObject o, Set<String> selected) =>
      o is LineObject &&
      o.attached &&
      (o.start == null || selected.contains(o.start!.to)) &&
      (o.end == null || selected.contains(o.end!.to));

  void alignSelection(String how) {
    final objs = selectedObjects.where((o) => !o.locked).toList();
    if (objs.isEmpty) return;
    // A line attached only to things selected with it (a mark on its
    // picture, a connector between two selected boxes) is carried by them:
    // it is not aligned in its own right and does not widen the frame. A
    // locked picture still carries its marks; it just does not move.
    final selected = {for (final o in selectedObjects) o.id};
    bool carried(SceneObject o) => _carriedBy(o, selected);
    final own = objs.where((o) => !carried(o)).toList();
    if (own.isEmpty) return;
    final frame = own.length > 1
        ? unionRects(own.map((o) => o.bounds))
        : Offset.zero & doc.canvasSize;
    transact('align', () {
      final shifts = <String, Offset>{};
      for (final o in own) {
        final b = o.bounds;
        shifts[o.id] = switch (how) {
          'left' => Offset(frame.left - b.left, 0),
          'right' => Offset(frame.right - b.right, 0),
          'centre' => Offset(frame.center.dx - b.center.dx, 0),
          'top' => Offset(0, frame.top - b.top),
          'bottom' => Offset(0, frame.bottom - b.bottom),
          'middle' => Offset(0, frame.center.dy - b.center.dy),
          _ => Offset.zero,
        };
      }
      // A carried line moves with the first thing it is attached to, so a
      // free end keeps its place beside it; its attached ends follow their
      // targets anyway.
      for (final o in objs) {
        if (o is LineObject && carried(o)) {
          final by = (o.start ?? o.end)!.to;
          shifts[o.id] = shifts[by] ?? Offset.zero;
        }
      }
      // Pins come off only lines that really shift, and only where their
      // picture is not selected with them.
      final held = holdPins([
        for (final o in objs)
          if ((shifts[o.id] ?? Offset.zero) != Offset.zero) o,
      ], group: selectedObjects);
      for (final o in objs) {
        o.translate(shifts[o.id] ?? Offset.zero);
      }
      repin(held);
    });
  }

  void setCurrentLayer(String id) {
    currentLayerId = id;
    notifyListeners();
  }

  /// Move whole objects to another layer without altering them.
  void moveObjectsToLayer(List<String> ids, String layerId) {
    final target = doc.layerById(layerId);
    if (target == null) return;
    transact('move to ${target.name}', () {
      final moving = <SceneObject>[];
      for (final l in doc.layers) {
        for (final o in List.of(l.objects)) {
          if (ids.contains(o.id)) {
            moving.add(o);
            l.objects.remove(o);
          }
        }
      }
      target.objects.addAll(moving);
      currentLayerId = layerId;
    });
  }

  void setObjectVisible(String id, bool v) => transact(v ? 'show' : 'hide', () {
    doc.objectById(id)?.visible = v;
    if (!v) selection = selection.where((s) => s != id).toList();
  });

  // ===== editing selection =================================================

  void deleteSelection() {
    if (selection.isEmpty) return;
    transact('delete', () {
      final ids = selection.toSet();
      for (final l in doc.layers) {
        l.objects.removeWhere((o) => ids.contains(o.id));
      }
      selection = [];
      editingTextId = null;
    });
  }

  void duplicateSelection() {
    final objs = selectedObjects;
    if (objs.isEmpty) return;
    transact('duplicate', () {
      final ids = <String>[];
      final map = <String, String>{};
      final copies = <SceneObject>[];
      for (final o in objs) {
        final layer = doc.layerOf(o.id) ?? currentLayer;
        final copy = o.copyWith(id: doc.newId('o'))
          ..translate(const Offset(24, 24));
        layer.objects.add(copy);
        ids.add(copy.id);
        map[o.id] = copy.id;
        copies.add(copy);
      }
      remapAttachments(copies, map);
      selection = ids;
    });
  }

  void nudge(Offset d) {
    final objs = selectedObjects.where((o) => !o.locked).toList();
    if (objs.isEmpty) return;
    transact('nudge', () {
      final held = holdPins(objs);
      for (final o in objs) {
        o.translate(d);
      }
      repin(held);
    });
  }

  /// Apply [f] to every selected object as one undo step.
  void editSelected(String label, void Function(SceneObject o) f) {
    final objs = selectedObjects;
    if (objs.isEmpty) return;
    transact(label, () {
      for (final o in objs) {
        f(o);
        if (o is TextObject) o.size = Size(o.size.width, measureTextHeight(o));
      }
    });
  }

  /// For sliders: change live between [beginEdit] and [endEdit].
  void liveEditSelected(void Function(SceneObject o) f) {
    for (final o in selectedObjects) {
      f(o);
      if (o is TextObject) o.size = Size(o.size.width, measureTextHeight(o));
    }
    notifyListeners();
  }

  /// Change the border or shadow of every selected picture and text box, as
  /// one undo step.
  void editFrames(String label, void Function(Framed f) f) =>
      editSelected(label, (o) {
        if (o is Framed) f(o);
      });

  /// Give every picture the border and shadow of [like], as one undo step.
  /// Locked pictures, and pictures on locked or hidden layers, are left as
  /// they are.
  void matchPictureBorders(ImageObject like) {
    transact('match picture borders', () {
      for (final l in doc.layers) {
        if (!l.visible || l.locked) continue;
        for (final o in l.objects) {
          if (o is ImageObject && !o.locked) o.copyFrame(like);
        }
      }
    });
  }

  /// Flip the selected pictures left to right. A curved mark pinned at both
  /// ends to a flipped picture is mirrored with it.
  void flipSelected() {
    final pics = {
      for (final o in selectedObjects)
        if (o is ImageObject) o.id: o,
    };
    if (pics.isEmpty) return;
    transact('flip', () {
      for (final p in pics.values) {
        p.flipX = !p.flipX;
      }
      for (final o in doc.allObjects) {
        if (o is LineObject &&
            !o.connects &&
            o.start != null &&
            o.end != null &&
            o.start!.to == o.end!.to &&
            pics.containsKey(o.start!.to)) {
          // The bend is measured across the line, which a flip turns over.
          o.bend = Offset(o.bend.dx, -o.bend.dy);
        }
      }
    });
  }

  /// Whether the selection counts as locked: any of it is.
  bool get selectionLocked => selectedObjects.any((o) => o.locked);

  /// Lock the selection in place, or unlock it if any of it is locked (so a
  /// mixed selection unlocks first, then locks). Locked things ignore clicks,
  /// so whatever is above or beside them is easy to work on; they stay
  /// selected until something else is.
  void toggleLockSelection() {
    final objs = selectedObjects;
    if (objs.isEmpty) return;
    final lock = !selectionLocked;
    editSelected(lock ? 'lock' : 'unlock', (o) => o.locked = lock);
  }

  void renameObject(String id, String name) => transact('rename', () {
    if (name.trim().isNotEmpty) doc.objectById(id)?.name = name.trim();
  });

  void reorderSelection(String how) {
    final objs = selectedObjects;
    if (objs.isEmpty) return;
    transact('reorder', () {
      for (final o
          in how == 'front' || how == 'forward' ? objs.reversed : objs) {
        final l = doc.layerOf(o.id);
        if (l == null) continue;
        final i = l.objects.indexOf(o);
        switch (how) {
          case 'front':
            l.objects
              ..removeAt(i)
              ..add(o);
          case 'back':
            l.objects
              ..removeAt(i)
              ..insert(0, o);
          case 'forward':
            if (i < l.objects.length - 1) {
              l.objects
                ..removeAt(i)
                ..insert(i + 1, o);
            }
          case 'backward':
            if (i > 0) {
              l.objects
                ..removeAt(i)
                ..insert(i - 1, o);
            }
        }
      }
    });
  }

  // ===== badges ===============================================================

  /// The size new markers are placed at: whatever size a marker was last given,
  /// so a row of markers comes out the same without resizing each one.

  /// Give every marker the size of [like] (one undo step), and remember it.
  void matchMarkerSizes(BadgeObject like) {
    final size = like.size;
    markerSize = math.max(size.width, size.height);
    transact('match marker sizes', () {
      for (final o in doc.allObjects) {
        if (o is BadgeObject && !o.locked) o.size = size;
      }
    });
  }

  /// How many markers differ in size from [like].
  int markersUnlike(BadgeObject like) => doc.allObjects
      .where((o) => o is BadgeObject && !o.locked && o.size != like.size)
      .length;

  /// The next free step number, so markers placed in a row count 1, 2, 3.
  int nextBadgeNumber() {
    var n = 0;
    for (final o in doc.allObjects) {
      if (o is BadgeObject && o.number > n) n = o.number;
    }
    return n + 1;
  }

  // ===== text ================================================================

  TextObject createText(Offset at, {double width = 320, String text = 'Text'}) {
    final t = TextObject(
      id: doc.newId('o'),
      name: uniqueName('text'),
      text: text,
      center: at,
      size: Size(width, 10),
      fontSize: textSize,
      color: textColor,
      font: textFont,
    );
    t.size = Size(width, measureTextHeight(t));
    t.center = Offset(at.dx + width / 2, at.dy + t.size.height / 2);
    return t;
  }

  void beginTextEdit(String id, {EditToken? token}) {
    finishTextEdit();
    final o = doc.objectById(id);
    if (o is! TextObject) return;
    editingTextId = id;
    selection = [id];
    _textEditToken = token ?? beginEdit('edit text');
    notifyListeners();
  }

  void updateEditingText(String text) {
    final o = editingTextId == null ? null : doc.objectById(editingTextId!);
    if (o is! TextObject) return;
    o.text = text;
    o.size = Size(o.size.width, measureTextHeight(o));
    notifyListeners();
  }

  void finishTextEdit() {
    final id = editingTextId;
    if (id == null) return;
    editingTextId = null;
    final o = doc.objectById(id);
    if (o is TextObject && o.text.trim().isEmpty) {
      doc.layerOf(id)?.objects.remove(o);
      selection = selection.where((s) => s != id).toList();
    }
    final t = _textEditToken;
    _textEditToken = null;
    if (t != null) endEdit(t);
    notifyListeners();
  }

  // ===== canvas ==============================================================

  void setCanvasSize(Size s, {String label = 'resize canvas'}) {
    final c = Size(
      s.width.clamp(64, 12000).toDouble(),
      s.height.clamp(64, 12000).toDouble(),
    );
    transact(label, () => doc.canvasSize = c);
  }

  void fitCanvasToContent({double padding = 0}) {
    final b = contentBounds(doc);
    if (b.isEmpty) return;
    transact('fit canvas to content', () {
      // Shift everything so the content sits at the page's top-left plus
      // padding; the page then covers the content exactly.
      final shift = Offset(padding - b.left, padding - b.top);
      for (final o in doc.allObjects) {
        o.translate(shift);
      }
      doc.canvasSize = Size(b.width + padding * 2, b.height + padding * 2);
    });
    fitToView();
  }

  void setBackground(int argb) =>
      transact('page colour', () => doc.background = argb);

  void setGridSize(double g) {
    final size = g.clamp(4, 400).toDouble();
    transact('grid size', () => doc.gridSize = size);
  }

  /// True when part of the page is outside the window, so panning is useful.
  bool get canPan =>
      doc.canvasSize.width * zoom > viewport.width + 1 ||
      doc.canvasSize.height * zoom > viewport.height + 1;

  void _growToFit() {
    final b = contentBounds(doc);
    if (b.isEmpty) return;
    final w = math.max(doc.canvasSize.width, b.right.ceilToDouble());
    final h = math.max(doc.canvasSize.height, b.bottom.ceilToDouble());
    if (w != doc.canvasSize.width || h != doc.canvasSize.height) {
      doc.canvasSize = Size(w, h);
    }
  }

  // ===== images ==============================================================

  bool get _pristine =>
      doc.allObjects.isEmpty &&
      doc.canvasSize == const Size(1600, 1000) &&
      doc.collection.isEmpty;

  Future<Asset> importBytes(Uint8List bytes) => assets.addEncoded(bytes);

  /// Put an image on the page as a new object in the current layer.
  ImageObject placeAsset(
    Asset a, {
    String? name,
    Offset? at,
    bool select = true,
  }) {
    var natural = Size(a.width.toDouble(), a.height.toDouble());
    Offset center = at ?? viewCenterScene;
    final t = beginEdit('add image');
    if (_pristine &&
        natural.width >= 300 &&
        natural.height >= 300 &&
        at == null) {
      doc.canvasSize = Size(
        math.min(natural.width, 12000),
        math.min(natural.height, 12000),
      );
      center = Offset(doc.canvasSize.width / 2, doc.canvasSize.height / 2);
      _fitPending = true;
    } else if (!viewport.isEmpty) {
      final visW = viewport.width / zoom, visH = viewport.height / zoom;
      final k = math.min(
        1.0,
        math.min(0.7 * visW / natural.width, 0.7 * visH / natural.height),
      );
      natural = Size(natural.width * k, natural.height * k);
    }
    final o = ImageObject(
      id: doc.newId('o'),
      name: name ?? uniqueName('image'),
      assetId: a.id,
      center: center,
      size: natural,
    );
    _addToLayer(o);
    if (select) selection = [o.id];
    endEdit(t);
    if (_fitPending) fitToView(notify: false);
    notifyListeners();
    return o;
  }

  /// A name no other collection item has. A taken name gets the next free
  /// number ("image 2" → "image 3"); [except] is the item being renamed.
  String uniqueCollectionName(String base, {String? except}) {
    final taken = {
      for (final i in doc.collection)
        if (i.id != except) i.name,
    };
    if (!taken.contains(base)) return base;
    final stem = base.replaceFirst(RegExp(r'\s+\d+$'), '');
    var n = 2;
    while (taken.contains('$stem $n')) {
      n++;
    }
    return '$stem $n';
  }

  CollectionItem addToCollection(Asset a, {String? name}) {
    final item = CollectionItem(
      id: doc.newId('c'),
      name: uniqueCollectionName(name ?? 'image 1'),
      assetId: a.id,
    );
    transact('add to collection', () => doc.collection.add(item));
    return item;
  }

  void removeFromCollection(String id) {
    final i = doc.collection.indexWhere((c) => c.id == id);
    if (i < 0) return;
    transact(
      'remove from collection',
      () => doc.collection.removeWhere((c) => c.id == id),
    );
    // Keep the highlight on a neighbour, so Delete can carry on down the shelf.
    if (_collectionSel == id) {
      _collectionSel = doc.collection.isEmpty
          ? null
          : doc.collection[i.clamp(0, doc.collection.length - 1)].id;
      notifyListeners();
    }
  }

  // ---- the selected collection item ----------------------------------------

  String? _collectionSel;

  /// The collection item that is selected, if there is one (and it still
  /// exists: undo can take it away).
  String? get selectedCollectionId =>
      doc.collection.any((c) => c.id == _collectionSel) ? _collectionSel : null;

  /// Select a collection item. It replaces any selection on the page: what
  /// the keys act on is never ambiguous.
  void selectCollectionItem(String? id) {
    if (id != null) {
      selection = [];
      if (editingTextId != null) finishTextEdit();
    }
    _collectionSel = id;
    notifyListeners();
  }

  /// Put the item where [targetId] is: it lands before the target when it
  /// moves back along the shelf, and after it when it moves forward.
  void moveCollectionItem(String id, String targetId) {
    final from = doc.collection.indexWhere((c) => c.id == id);
    final to = doc.collection.indexWhere((c) => c.id == targetId);
    if (from < 0 || to < 0 || from == to) return;
    transact('rearrange collection', () {
      doc.collection.insert(to, doc.collection.removeAt(from));
    });
  }

  /// One place earlier (-1) or later (+1).
  void shiftCollectionItem(int by) {
    final id = selectedCollectionId;
    if (id == null) return;
    final from = doc.collection.indexWhere((c) => c.id == id);
    final to = from + by;
    if (to < 0 || to >= doc.collection.length) return;
    moveCollectionItem(id, doc.collection[to].id);
  }

  void renameCollectionItem(String id, String name) {
    final fresh = uniqueCollectionName(name.trim(), except: id);
    if (name.trim().isEmpty) return;
    transact('rename item', () {
      for (final c in doc.collection) {
        if (c.id == id) c.name = fresh;
      }
    });
  }

  /// The collection item whose name is being typed in place (F2).
  String? renamingCollectionId;

  /// Start renaming the selected collection item (or [id]) right on its tile.
  void beginCollectionRename([String? id]) {
    final target = id ?? selectedCollectionId;
    if (target == null) return;
    if (editingTextId != null) finishTextEdit();
    _collectionSel = target;
    selection = [];
    renamingCollectionId = target;
    notifyListeners();
  }

  /// Finish the in-place rename; a null or blank name leaves things as they were.
  void finishCollectionRename(String? name) {
    final id = renamingCollectionId;
    if (id == null) return;
    renamingCollectionId = null;
    if (name != null && name.trim().isNotEmpty) renameCollectionItem(id, name);
    notifyListeners();
  }

  /// A new object from a collected source; the source stays in the collection.
  ImageObject? placeCollectionItem(String itemId, {Offset? at}) {
    final item = doc.collection.where((c) => c.id == itemId).firstOrNull;
    final a = item == null ? null : assets[item.assetId];
    if (item == null || a == null) return null;
    return placeAsset(a, name: uniqueName(item.name), at: at);
  }

  /// Keep a copy of a placed image as a collected source.
  void sendSelectionToCollection() {
    final imgs = selectedObjects.whereType<ImageObject>().toList();
    if (imgs.isEmpty) return;
    transact('add to collection', () {
      for (final o in imgs) {
        doc.collection.add(
          CollectionItem(
            id: doc.newId('c'),
            name: uniqueCollectionName(o.name),
            assetId: o.assetId,
          ),
        );
      }
    });
    showToast('Added to collection');
  }

  // ===== clipboard ===========================================================

  int _sig(Uint8List b) {
    var h = b.length;
    for (int i = 0; i < b.length; i += math.max(1, b.length ~/ 97)) {
      h = (h * 31 + b[i]) & 0x3fffffff;
    }
    return h;
  }

  /// Ctrl+V: an image on the system clipboard wins; otherwise text; otherwise
  /// whatever was last copied inside Thinkspace.
  Future<void> paste() async {
    final bytes = await SystemClipboard.readImage();
    if (bytes != null && _sig(bytes) != _lastCopySig) {
      try {
        final a = await assets.addEncoded(bytes);
        _receiveImage(a, 'pasted image');
        return;
      } catch (_) {
        showToast('That clipboard image could not be read');
        return;
      }
    }
    // Pictures copied as files (Ctrl+C in Explorer or a file manager).
    if (bytes == null) {
      final files = await SystemClipboard.readPictureFiles();
      if (files.isNotEmpty) {
        await _pasteFiles(files);
        return;
      }
    }
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (text != null &&
        text.trim().isNotEmpty &&
        (_clip.isEmpty || bytes == null)) {
      finishTextEdit();
      final t = createText(viewCenterScene - const Offset(160, 20), text: text);
      addObject(t, label: 'paste text');
      return;
    }
    if (_clip.isNotEmpty) {
      pasteObjects();
      return;
    }
    showToast('Nothing to paste');
  }

  /// Picture files from the clipboard: one asks where it should go, like any
  /// pasted picture; several go straight in, to wherever pasting is set to.
  Future<void> _pasteFiles(List<String> files) async {
    if (files.length == 1) {
      try {
        final a = await assets.addEncoded(
          await File(files.first).readAsBytes(),
        );
        _receiveImage(a, baseNameOf(files.first));
      } catch (_) {
        showToast('Could not open ${fileNameOf(files.first)}');
      }
      return;
    }
    await importFiles(files, toCollection: pasteMode == PasteMode.collection);
  }

  /// Paste an image straight into the collection, skipping the question.
  Future<void> pasteToCollection() async {
    final bytes = await SystemClipboard.readImage();
    if (bytes == null) {
      final files = await SystemClipboard.readPictureFiles();
      if (files.isNotEmpty) {
        await importFiles(files, toCollection: true);
        return;
      }
      showToast('There is no image on the clipboard');
      return;
    }
    final a = await assets.addEncoded(bytes);
    addToCollection(a);
  }

  /// Offer to place a new image on the page or in the collection.
  void _receiveImage(Asset a, String name) {
    switch (pasteMode) {
      case PasteMode.layer:
        placeAsset(a);
      case PasteMode.collection:
        addToCollection(a);
        showToast('Added to collection');
      case PasteMode.ask:
        pendingPaste = PendingPaste(a.id, name);
        notifyListeners();
    }
  }

  void resolvePaste({required bool toCollection, bool remember = false}) {
    final p = pendingPaste;
    if (p == null) return;
    pendingPaste = null;
    final a = assets[p.assetId];
    if (remember) {
      pasteMode = toCollection ? PasteMode.collection : PasteMode.layer;
    }
    if (a != null) {
      if (toCollection) {
        addToCollection(a);
      } else {
        placeAsset(a);
      }
    }
    notifyListeners();
  }

  void cancelPendingPaste() {
    pendingPaste = null;
    notifyListeners();
  }

  /// Import image files (dropped or chosen) straight to the right place.
  Future<void> importFiles(
    List<String> paths, {
    Offset? at,
    bool toCollection = false,
  }) async {
    for (final path in paths) {
      try {
        final bytes = await File(path).readAsBytes();
        final a = await assets.addEncoded(bytes);
        final base = baseNameOf(path);
        if (toCollection) {
          addToCollection(a, name: base);
        } else {
          placeAsset(a, name: uniqueName(base), at: at);
        }
      } catch (_) {
        showToast('Could not open ${fileNameOf(path)}');
      }
    }
  }

  void copySelection() {
    final objs = withCovers(selectedObjects);
    if (objs.isEmpty) return;
    _clip = [for (final o in objs) o.copyWith()];
    _pasteCount = 0;
    final covers = objs.length - selection.length;
    showToast(
      covers > 0 ? 'Copied, with the hidden details over it' : 'Copied',
    );
    unawaited(_copyRenderedSelection(objs));
  }

  /// [objs] in page order, plus every Hide details box that lies over them.
  /// A picture copied on its own must still have its private parts hidden:
  /// copying a screenshot and pasting it into an email is exactly when it
  /// matters.
  List<SceneObject> withCovers(List<SceneObject> objs) {
    if (objs.isEmpty) return const [];
    final chosen = {for (final o in objs) o.id};
    final area = unionRects(objs.map((o) => o.paintBounds));
    final out = <SceneObject>[];
    for (final layer in doc.layers) {
      for (final o in layer.objects) {
        if (chosen.contains(o.id)) {
          out.add(o);
        } else if (o is HideObject &&
            out.isNotEmpty &&
            layer.visible &&
            o.visible &&
            o.bounds.overlaps(area)) {
          out.add(o);
        }
      }
    }
    return out;
  }

  /// The selection drawn as one picture, as it is copied to the clipboard.
  Future<ui.Image> renderObjects(List<SceneObject> objs) {
    final b = unionRects(objs.map((o) => o.paintBounds)).inflate(2);
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec);
    c.translate(-b.left, -b.top);
    paintObjects(c, objs, assets);
    return rec.endRecording().toImage(b.width.ceil(), b.height.ceil());
  }

  Future<void> _copyRenderedSelection(List<SceneObject> objs) async {
    try {
      final img = await renderObjects(objs);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      final png = data!.buffer.asUint8List();
      _lastCopySig = _sig(png);
      if (!await SystemClipboard.writeImage(png)) {
        showToast(_copyFailed);
      }
    } catch (_) {
      showToast("Couldn't copy the selection as an image");
    }
  }

  /// Said when the clipboard did not take a picture: whatever was copied
  /// before is still there, and pasting would give that instead.
  static const _copyFailed =
      'Copy failed: pasting elsewhere gives what was copied before. Export with Ctrl+E instead, or install wl-clipboard (Wayland) or xclip (X11)';

  void cutSelection() {
    copySelection();
    deleteSelection();
  }

  void pasteObjects() {
    if (_clip.isEmpty) return;
    _pasteCount++;
    final off = Offset(24.0 * _pasteCount, 24.0 * _pasteCount);
    transact('paste', () {
      final ids = <String>[];
      final map = <String, String>{};
      final copies = <SceneObject>[];
      for (final o in _clip) {
        final copy = o.copyWith(id: doc.newId('o'))..translate(off);
        currentLayer.objects.add(copy);
        ids.add(copy.id);
        map[o.id] = copy.id;
        copies.add(copy);
      }
      remapAttachments(copies, map);
      selection = ids;
    });
  }

  /// The largest side an exported image may have (GPU texture limit).
  static const double maxExportSide = 16000;

  Future<Uint8List> exportPng({double scale = 1}) async {
    final longest = math.max(doc.canvasSize.width, doc.canvasSize.height);
    if (longest * scale > maxExportSide) {
      scale = maxExportSide / longest;
    }
    final img = await renderDocument(doc, assets, scale: scale);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return data!.buffer.asUint8List();
  }

  Future<void> copyPageToClipboard() async {
    try {
      final png = await exportPng();
      _lastCopySig = _sig(png);
      final ok = await SystemClipboard.writeImage(png);
      showToast(ok ? 'Copied the page as an image' : _copyFailed);
    } catch (_) {
      showToast("Couldn't copy the page as an image");
    }
  }

  /// Merge the selected objects into one picture. The originals are replaced
  /// (undo brings them back).
  Future<ImageObject?> flattenSelection() async {
    if (_flattening) {
      showToast('Still merging…');
      return null; // a second press while one is under way
    }
    _flattening = true;
    try {
      return await _flattenSelection();
    } finally {
      _flattening = false;
    }
  }

  bool _flattening = false;

  Future<ImageObject?> _flattenSelection() async {
    // Locked and hidden things are left where they are: a merge only takes
    // what you can see and are free to change.
    // A merge never takes a Hide details box off the page: it may be hiding
    // other things too.
    final ordered = mergeParts;
    final chosen = {for (final o in ordered) o.id};
    if (ordered.isEmpty) return null;
    final b = unionRects(ordered.map((o) => o.paintBounds)).inflate(1);
    // Marks made with the highlighter multiply onto the page. Merged into a
    // picture they would turn into solid colour and hide what they were
    // marking, so a merge of nothing but such marks multiplies as one; the
    // Hide boxes over them stay on the page and keep hiding what is below.
    final multiply = ordered.every(
      (o) =>
          (o is StrokeObject && o.highlight == HighlightStyle.multiply) ||
          (o is ShapeObject && o.highlight == HighlightStyle.multiply),
    );
    final (shown, refusal) = _mergePlan(ordered, highlights: multiply);
    if (refusal != null) {
      showToast(refusal);
      return null;
    }
    // Rendering takes a moment. If the page changes meanwhile, what was
    // rendered no longer matches it, so nothing is applied.
    final before = doc.signature();
    final edits = _editsBegun;
    // Opening a file (or undo) swaps the whole document, even one that
    // reads the same.
    final same = doc;
    final drawn = multiply ? ordered : shown;
    final covered = drawn.length > ordered.length;
    var scale = 1.0;
    for (final o in ordered) {
      if (o is ImageObject) {
        final a = assets[o.assetId];
        if (a != null) {
          scale = math.max(scale, a.width / math.max(1, o.size.width));
        }
      }
    }
    scale = math.min(scale, 4);
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    canvas.scale(scale);
    canvas.translate(-b.left, -b.top);
    paintObjects(canvas, [
      for (final o in drawn)
        if (o.visible) o,
    ], assets);
    final img = await rec.endRecording().toImage(
      (b.width * scale).ceil(),
      (b.height * scale).ceil(),
    );
    final asset = await assets.addImage(img);
    if (!identical(doc, same) ||
        doc.signature() != before ||
        _editsBegun != edits ||
        editingTextId != null) {
      assets.forget(asset.id);
      showToast('The page changed while merging. Merge again.');
      return null;
    }
    final topLayer = doc.layerOf(ordered.last.id) ?? currentLayer;
    final merged = ImageObject(
      id: doc.newId('o'),
      name: uniqueName('merged'),
      assetId: asset.id,
      center: b.center,
      size: b.size,
      merged: MergeRecord(
        assetId: asset.id,
        center: b.center,
        size: b.size,
        // The covers come back with the parts on unmerge, so a part never
        // comes back above the box that hid it.
        parts: [for (final o in drawn) o.toJson()],
      ),
      multiply: multiply,
    );
    transact('merge into one image', () {
      // The merged picture takes the place of the highest part, so whatever
      // was above the parts (an arrow, a label) stays above.
      final at = topLayer.objects.indexWhere((x) => x.id == ordered.last.id);
      if (at >= 0) {
        topLayer.objects[at] = merged;
      } else {
        topLayer.objects.add(merged);
      }
      for (final l in doc.layers) {
        l.objects.removeWhere((o) => chosen.contains(o.id));
      }
      selection = [merged.id];
      currentLayerId = topLayer.id;
    });
    if (covered) showToast('Merged, with the hidden details over it');
    return merged;
  }

  /// What a merge paints, and whether it must refuse. The merged picture
  /// holds what the page shows: [parts] in page order, with every shown Hide
  /// details box over them from the lowest part up, painted in. A merge
  /// refuses (with the reason) when something it would have to bury lies
  /// between the parts: a visible thing nobody selected, or a Hide details box
  /// that is switched off and would no longer cover the merged picture once
  /// switched on.
  ///
  /// A merge of highlights does not paint Hide boxes in (it stays
  /// see-through), so with [highlights] a box between the parts counts as
  /// something it would have to bury.
  (List<SceneObject>, String?) _mergePlan(
    List<SceneObject> parts, {
    bool highlights = false,
  }) {
    final ids = {for (final o in parts) o.id};
    final areas = [for (final o in parts) o.paintBounds];
    final last = parts.last.id;
    final out = <SceneObject>[];
    var above = false;
    for (final layer in doc.layers) {
      for (final o in layer.objects) {
        if (ids.contains(o.id)) {
          out.add(o);
          if (o.id == last) above = true;
          continue;
        }
        if (out.isEmpty) continue;
        final area = o is HideObject ? o.bounds : o.paintBounds;
        if (!areas.any((a) => a.overlaps(area))) continue;
        final seen = layer.visible && o.visible;
        if (o is HideObject) {
          if (above) {
            if (seen) out.add(o);
          } else if (!layer.visible) {
            return (
              out,
              'The Hide details box “${o.name}” is on a hidden layer and lies between these. Show the layer or delete the box first.',
            );
          } else if (!o.visible) {
            return (
              out,
              'The switched-off Hide details box “${o.name}” lies between these. Switch it on or delete it first.',
            );
          } else if (highlights) {
            return (
              out,
              'The Hide details box “${o.name}” lies between these highlights. Merge them in two steps.',
            );
          } else {
            out.add(o);
          }
        } else if (seen && !above) {
          final locked = o.locked || layer.locked;
          return (
            out,
            locked
                ? '“${o.name}” is locked and lies between these. Unlock it, or merge them in two steps.'
                : '“${o.name}” lies between these. Select it too, or merge them in two steps.',
          );
        }
      }
    }
    return (out, null);
  }

  /// What a merge turns into one picture: the mergeable things, except Hide
  /// details boxes, which stay on the page.
  List<SceneObject> get mergeParts => [
    for (final o in mergeable)
      if (o is! HideObject) o,
  ];

  /// The selected things a merge would take, bottom to top: visible, not
  /// locked, and not on a hidden or locked layer.
  List<SceneObject> get mergeable {
    final chosen = selection.toSet();
    return [
      for (final l in doc.layers)
        if (l.visible && !l.locked)
          for (final o in l.objects)
            if (chosen.contains(o.id) && o.visible && !o.locked) o,
    ];
  }

  /// Merging needs two or more things, or one thing that is not already a
  /// picture.
  bool get canMerge {
    final sel = mergeParts;
    return sel.length > 1 || (sel.length == 1 && sel.first is! ImageObject);
  }

  /// The selected picture, if it is a merge that can be taken apart again.
  bool get canUnmerge {
    final o = single;
    return o is ImageObject && o.canUnmerge;
  }

  /// Put a merged picture back into the pieces it was made from, wherever the
  /// merged picture has been moved, resized, turned or faded since.
  List<SceneObject> unmerge() {
    final o = single;
    if (o is! ImageObject || !o.canUnmerge) return const [];
    final rec = o.merged!;
    final sx = o.size.width / rec.size.width;
    final sy = o.size.height / rec.size.height;
    final k = math.sqrt(sx * sy);
    // Where a point on the page at merge time is now.
    Offset map(Offset p) {
      var q = p - rec.center;
      q = Offset(q.dx * sx, q.dy * sy);
      if (o.flipX) q = Offset(-q.dx, q.dy);
      return o.center + rotateOffset(q, o.rotation);
    }

    final layer = doc.layerOf(o.id) ?? currentLayer;
    try {
      return _unmergeInto(o, rec, layer, map, sx, sy, k);
    } catch (_) {
      // A damaged record: the edit was rolled back, so nothing changed.
      showToast("Couldn't unmerge this image");
      return const [];
    }
  }

  List<SceneObject> _unmergeInto(
    ImageObject o,
    MergeRecord rec,
    Layer layer,
    Offset Function(Offset) map,
    double sx,
    double sy,
    double k,
  ) {
    return transact('unmerge', () {
      final made = <SceneObject>[];
      final ids = <String, String>{};
      for (final j in rec.parts) {
        final json = Map<String, dynamic>.from(j)..['id'] = doc.newId('o');
        if (j['id'] is String) ids[j['id'] as String] = json['id'] as String;
        final p = SceneObject.fromJson(json);
        p.opacity *= o.opacity;
        switch (p) {
          case BoxObject():
            final turned = p.rotation.abs() > 1e-9;
            p.center = map(p.center);
            p.rotation = (o.flipX ? -p.rotation : p.rotation) + o.rotation;
            if (o.flipX && p is ImageObject) p.flipX = !p.flipX;
            p.size = turned || p is BadgeObject
                ? Size(p.size.width * k, p.size.height * k)
                : Size(p.size.width * sx, p.size.height * sy);
            if (p is TextObject) {
              p.fontSize *= k;
              p.size = Size(p.size.width, measureTextHeight(p));
            } else if (p is ShapeObject) {
              p.strokeWidth *= k;
            }
            if (p is Framed) p.borderWidth *= k;
          case LineObject():
            final mid = map(p.mid);
            p.p1 = map(p.p1);
            p.p2 = map(p.p2);
            p.mid = mid;
            p.width *= k;
            // A bend is measured across the line, which a flip turns over.
            if (o.flipX && p.anchorBend != null) {
              p.anchorBend = Offset(p.anchorBend!.dx, -p.anchorBend!.dy);
            }
          case StrokeObject():
            p.points = [for (final q in p.points) map(q)];
            p.width *= k;
        }
        made.add(p);
      }
      // Links between the parts come back; links to anything else are gone.
      remapAttachments(made, ids);
      final idx = layer.objects.indexWhere((x) => x.id == o.id);
      if (idx < 0) {
        layer.objects.addAll(made);
      } else {
        layer.objects.replaceRange(idx, idx + 1, made);
      }
      selection = [for (final p in made) p.id];
      currentLayerId = layer.id;
      return made;
    });
  }

  // ===== cutouts and background removal ======================================

  Offset _toPx(ImageObject o, Asset a, Offset scene) {
    final l = o.toLocal(scene);
    var u = l.dx / o.size.width + 0.5;
    if (o.flipX) u = 1 - u;
    return Offset(u * a.width, (l.dy / o.size.height + 0.5) * a.height);
  }

  /// The topmost visible image under [scene], regardless of lock state.
  ImageObject? imageAt(Offset scene) {
    for (final o in objectsAt(scene)) {
      if (o is ImageObject) return o;
    }
    return null;
  }

  /// Make a new object from the part of [src] inside [scenePolygon]. The
  /// original is untouched unless a hole is requested.
  Future<ImageObject?> cutout(
    ImageObject src,
    List<Offset> scenePolygon, {
    bool? leaveHole,
  }) async {
    final a = assets[src.assetId];
    if (a == null) return null;
    final poly = [for (final p in scenePolygon) _toPx(src, a, p)];
    final hole = leaveHole ?? cutoutLeavesHole;
    final res = await cutoutPolygon(
      a,
      poly,
      leaveHole: hole,
      fill: cutoutFill,
      fillColor: cutoutFillColor,
    );
    if (res == null) {
      showToast('Nothing to cut out there');
      return null;
    }
    final piece = await assets.addImage(res.image);
    Asset? rest;
    if (res.remainder != null) rest = await assets.addImage(res.remainder!);
    final sx = src.size.width / a.width, sy = src.size.height / a.height;
    var u = res.rectPx.center.dx / a.width;
    if (src.flipX) u = 1 - u;
    final local = Offset(
      (u - 0.5) * src.size.width,
      (res.rectPx.center.dy / a.height - 0.5) * src.size.height,
    );
    final obj = ImageObject(
      id: '',
      name: '${src.name} cut',
      assetId: piece.id,
      center: src.toScene(local),
      size: Size(res.rectPx.width * sx, res.rectPx.height * sy),
      rotation: src.rotation,
      flipX: src.flipX,
      opacity: src.opacity,
      multiply: src.multiply,
    );
    transact('cut out', () {
      final layer = doc.layerOf(src.id) ?? currentLayer;
      final placed = ImageObject(
        id: doc.newId('o'),
        name: uniqueName('${src.name} cut'),
        assetId: obj.assetId,
        center: obj.center,
        size: obj.size,
        rotation: obj.rotation,
        flipX: obj.flipX,
        opacity: obj.opacity,
        multiply: obj.multiply,
      );
      final idx = layer.objects.indexWhere((o) => o.id == src.id);
      layer.objects.insert(idx < 0 ? layer.objects.length : idx + 1, placed);
      if (rest != null) {
        // The source may have been deleted or undone while we were busy.
        final live = doc.objectById(src.id);
        if (live is ImageObject) live.assetId = rest.id;
      }
      selection = [placed.id];
      currentLayerId = layer.id;
    });
    return doc.objectById(selection.first) as ImageObject?;
  }

  Future<bool> removeBackgroundFrom(
    ImageObject o, {
    double? tolerance,
    int? session,
  }) async {
    final a = assets[o.assetId];
    if (a == null) return false;
    final r = await removeBackground(
      a,
      tolerance ?? wandTolerance,
      inside: bgInside,
    );
    if (r == null) {
      showToast('No background found to remove');
      return false;
    }
    final na = await assets.addImage(r.image);
    transact(
      'remove background',
      () => (doc.objectById(o.id) as ImageObject?)?.assetId = na.id,
    );
    // Open the fine-tuning bar, as long as nothing else happens meanwhile.
    // (Not if it was dismissed while the removal was being computed.)
    if (session == null || session == _bgGen) {
      _bgObject = o.id;
      _bgDepth = undoDepth;
      _bgAsset = na.id;
      _bgSig = doc.signature();
    }
    notifyListeners();
    return true;
  }

  // ---- fine-tuning a background removal -------------------------------------
  // Right after "Remove background" a small bar offers Less / More and the
  // enclosed-areas switch. Changing either takes the removal back and redoes
  // it from the original picture, so the whole thing stays one undo step.

  String? _bgObject, _bgAsset, _bgSig;
  int _bgDepth = -1, _bgGen = 0;
  bool _bgBusy = false, _bgPending = false;

  /// The picture whose background was just removed, while the bar applies:
  /// nothing else has been done since, and it is still selected.
  ImageObject? get bgSessionObject {
    final id = _bgObject;
    if (id == null || undoDepth != _bgDepth) return null;
    final o = doc.objectById(id);
    if (o is! ImageObject || o.assetId != _bgAsset) return null;
    return single?.id == id ? o : null;
  }

  void endBgSession() {
    _bgGen++; // a removal still being computed must not bring the bar back
    if (_bgObject == null) return;
    _bgObject = _bgAsset = null;
    notifyListeners();
  }

  /// Redo the removal with the current settings.
  Future<void> adjustBackground() async {
    if (_bgBusy) {
      _bgPending = true; // one more pass once this one is done
      return;
    }
    _bgBusy = true;
    try {
      do {
        _bgPending = false;
        final o = bgSessionObject;
        if (o == null) break;
        // Something changed the page without a step of its own (a slider
        // still being dragged): taking the removal back would lose it.
        if (doc.signature() != _bgSig) {
          endBgSession();
          break;
        }
        final gen = _bgGen;
        undo(quiet: true);
        final back = doc.objectById(o.id);
        if (back is ImageObject) {
          final ok = await removeBackgroundFrom(back, session: gen);
          if (!ok) endBgSession();
        } else {
          endBgSession();
        }
      } while (_bgPending);
    } finally {
      _bgBusy = false;
    }
  }

  Future<bool> removeColorAt(ImageObject o, Offset scene) async {
    final a = assets[o.assetId];
    if (a == null) return false;
    final px = _toPx(o, a, scene);
    final r = await removeColorFrom(
      a,
      [(px.dx.floor(), px.dy.floor())],
      wandTolerance,
      contiguous: wandContiguous,
    );
    if (r == null) {
      showToast('Nothing to remove there');
      return false;
    }
    final na = await assets.addImage(r.image);
    transact(
      'remove colour',
      () => (doc.objectById(o.id) as ImageObject?)?.assetId = na.id,
    );
    return true;
  }

  // ===== projects ============================================================

  String projectJson() => jsonEncode({
    'format': 'thinkspace',
    'version': 1,
    'document': doc.toJson(),
    'assets': assets.encode(doc.usedAssets),
  });

  /// Load a project. Returns how many pictures could not be read (the rest of
  /// the project still opens; a missing picture just draws as nothing).
  Future<int> loadProjectJson(String s, {String? path}) async {
    final j = jsonDecode(s) as Map<String, dynamic>;
    if (j['format'] != 'thinkspace') {
      throw const FormatException('Not a Thinkspace project');
    }
    final version = j['version'];
    if (version is num && version > 1) {
      throw const FormatException(
        'This project was made by a newer Thinkspace',
      );
    }
    final newDoc = Document.fromJson(Map<String, dynamic>.from(j['document']));
    // Decode into a scratch store first, so a bad file leaves the current
    // project untouched and a good one swaps in all at once.
    final fresh = AssetStore();
    final encoded = Map<String, dynamic>.from(j['assets'] ?? {});
    var unreadable = 0;
    for (final e in encoded.entries) {
      try {
        await fresh.addEncoded(base64Decode(e.value as String), id: e.key);
      } catch (_) {
        unreadable++;
      }
    }
    assets.replaceWith(fresh);
    doc = newDoc;
    if (doc.layers.isEmpty) {
      doc.layers.add(Layer(id: doc.newId('l'), name: 'Layer 1'));
    }
    currentLayerId = doc.layers.last.id;
    selection = [];
    _undo.clear();
    _redo.clear();
    editingTextId = null;
    filePath = path;
    if (path != null) noteRecent(path);
    markSaved();
    fitToView(notify: false);
    notifyListeners();
    if (unreadable > 0) {
      showToast(
        unreadable == 1
            ? "1 image couldn't be read and was left out"
            : "$unreadable images couldn't be read and were left out",
      );
    }
    return unreadable;
  }

  /// Write to a temporary file beside [f], then rename it into place, so a
  /// crash or a full disk can never leave a half-written project behind.
  static Future<void> _writeAtomic(File f, String content) async {
    final tmp = File('${f.path}.tmp');
    try {
      await tmp.writeAsString(content, flush: true);
      await tmp.rename(f.path);
    } catch (_) {
      try {
        if (tmp.existsSync()) tmp.deleteSync();
      } catch (_) {}
      rethrow;
    }
  }

  /// Returns false (and says so) if the project could not be written.
  Future<bool> saveTo(String path) async {
    finishTextEdit();
    try {
      await _writeAtomic(File(path), projectJson());
    } catch (_) {
      showToast('Could not save ${fileNameOf(path)} — nothing was changed');
      return false;
    }
    filePath = path;
    noteRecent(path);
    markSaved();
    clearRecovery();
    showToast('Saved ${fileNameOf(path)}');
    return true;
  }

  /// Render the page and write it as a PNG; false (with a message) on failure.
  Future<bool> exportPngTo(String path, {double scale = 1}) async {
    final tmp = File('$path.tmp');
    try {
      await tmp.writeAsBytes(await exportPng(scale: scale), flush: true);
      await tmp.rename(path);
    } catch (_) {
      try {
        if (tmp.existsSync()) tmp.deleteSync();
      } catch (_) {}
      showToast('Could not export ${fileNameOf(path)}');
      return false;
    }
    showToast('Exported ${fileNameOf(path)}');
    return true;
  }

  Future<void> openFrom(String path) async {
    final bad = await loadProjectJson(
      await File(path).readAsString(),
      path: path,
    );
    if (bad == 0) showToast('Opened ${fileNameOf(path)}');
  }

  /// Files the app was started with (double-click in a file manager, or
  /// `thinkspace picture.png`): a project opens, pictures go on the page.
  Future<void> openLaunchFiles(List<String> args) async {
    String? toPath(String a) {
      if (!a.startsWith('file://')) return a;
      try {
        return Uri.parse(a).toFilePath();
      } catch (_) {
        return null; // a damaged file:// address is simply skipped
      }
    }

    final paths = [
      for (final a in args)
        if (toPath(a) case final p?) p,
    ];
    final project = paths
        .where((p) => p.toLowerCase().endsWith('.thinkspace'))
        .toList();
    try {
      if (project.isNotEmpty) {
        await openFrom(project.first);
        return;
      }
      const exts = ['.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp'];
      final pics = paths
          .where((p) => exts.any((e) => p.toLowerCase().endsWith(e)))
          .toList();
      if (pics.isNotEmpty) await importFiles(pics);
    } catch (_) {
      showToast('Could not open that file');
    }
  }

  void newDocument() {
    assets.clear();
    doc = Document.blank();
    currentLayerId = doc.layers.first.id;
    selection = [];
    _undo.clear();
    _redo.clear();
    editingTextId = null;
    filePath = null;
    markSaved();
    pendingPaste = null;
    clearRecovery();
    fitToView(notify: false);
    notifyListeners();
  }

  /// Replace the document with a ready-made one (samples, tests).
  Future<void> replaceDocument(Document d, {String? title}) async {
    doc = d;
    currentLayerId = doc.layers.last.id;
    selection = [];
    _undo.clear();
    _redo.clear();
    editingTextId = null;
    filePath = null;
    markSaved();
    fitToView(notify: false);
    notifyListeners();
  }

  // ===== inspection ==========================================================

  Map<String, dynamic> stateJson() => {
    'tool': tool.name,
    'zoom': zoom,
    'pan': [pan.dx, pan.dy],
    'viewport': [viewport.width, viewport.height],
    'canvas': {
      'width': doc.canvasSize.width,
      'height': doc.canvasSize.height,
      'background': doc.background,
    },
    'grid': {'show': showGrid, 'snap': snapOn, 'size': doc.gridSize},
    'currentLayer': currentLayerId,
    'selection': selection,
    'editingText': editingTextId,
    'history': {'undo': _undo.length, 'redo': _redo.length},
    'dirty': dirty,
    'file': filePath,
    'pendingPaste': pendingPaste?.name,
    'pasteMode': pasteMode.name,
    'layers': [
      for (final l in doc.layers)
        {
          'id': l.id,
          'name': l.name,
          'visible': l.visible,
          'locked': l.locked,
          'objects': [
            for (final o in l.objects)
              {
                ...o.toJson(),
                'selected': selection.contains(o.id),
                'bounds': [
                  o.bounds.left,
                  o.bounds.top,
                  o.bounds.right,
                  o.bounds.bottom,
                ],
              },
          ],
        },
    ],
    'collection': [
      for (final c in doc.collection)
        {...c.toJson(), 'size': _assetSize(c.assetId)},
    ],
    'assets': assets.length,
  };

  List<int>? _assetSize(String id) {
    final a = assets[id];
    return a == null ? null : [a.width, a.height];
  }
}
