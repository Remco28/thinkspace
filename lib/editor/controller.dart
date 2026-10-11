import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:flutter/services.dart';

import '../io/clipboard.dart';
import '../model/assets.dart';
import '../model/geometry.dart';
import '../model/scene.dart';
import 'image_ops.dart';
import 'render.dart';

enum Tool { select, line, arrow, rect, ellipse, text, pen, badge, cutout }

enum CutoutMode { lasso, box, wand }

enum PasteMode { ask, layer, collection }

enum HandleKind { resize, rotate, lineStart, lineEnd }

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
    _savedSig = doc.signature();
    dirty = false;
  }

  late Document doc;
  final AssetStore assets = AssetStore();

  // --- selection & tools -------------------------------------------------
  List<String> selection = [];
  late String currentLayerId;
  Tool tool = Tool.select;
  bool toolLocked = false;
  CutoutMode cutoutMode = CutoutMode.lasso;
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
  int penColor = kPalette[0];
  double penWidth = 5;
  int fillColor = 0;
  int textColor = 0xFF222222;
  double textSize = 28;
  TextFont textFont = TextFont.sans;
  PasteMode pasteMode = PasteMode.ask;
  PendingPaste? pendingPaste;

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

  Future<void> restoreRecovery() async {
    final f = recoveryFile;
    if (f == null) return;
    await loadProjectJson(await f.readAsString());
    _savedSig = null; // it has never been saved under a real name
    dirty = true;
    _needsAutosave = true;
    notifyListeners();
  }

  void notify() => notifyListeners();

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

  EditToken beginEdit(String label) => EditToken._(_capture(label));

  /// Record [token]'s state for undo if the document changed since.
  void endEdit(EditToken token) {
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

  void undo() {
    finishTextEdit();
    if (_undo.isEmpty) return;
    final s = _undo.removeLast();
    _redo.add(_capture(s.label));
    _restore(s);
    showToast('Undid ${s.label}');
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
    if (ids.isNotEmpty) _collectionSel = null;
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
    notifyListeners();
  }

  void setTool(Tool t, {bool lock = false}) {
    finishTextEdit();
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
    final tol = 4 / zoom;
    final out = <SceneObject>[];
    for (final layer in doc.layers.reversed) {
      if (!layer.visible || layer.locked) continue;
      for (final o in layer.objects.reversed) {
        if (!o.visible || o.locked) continue;
        if (o.hitTest(p, tol, assets)) out.add(o);
      }
    }
    return out;
  }

  List<HandleSpot> handlesFor(SceneObject o) {
    if (o is LineObject) {
      return [
        HandleSpot(HandleKind.lineStart, o.p1),
        HandleSpot(HandleKind.lineEnd, o.p2),
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

  void addLayer() => transact('add layer', () {
    final idx = doc.layers.indexWhere((l) => l.id == currentLayerId);
    final n = doc.layers.length + 1;
    final layer = Layer(id: doc.newId('l'), name: 'Layer $n');
    doc.layers.insert(idx < 0 ? doc.layers.length : idx + 1, layer);
    currentLayerId = layer.id;
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
      final copy = Layer(
        id: doc.newId('l'),
        name: '${src.name} copy',
        visible: src.visible,
        locked: src.locked,
        objects: [for (final o in src.objects) o.copyWith(id: doc.newId('o'))],
      );
      doc.layers.insert(doc.layers.indexOf(src) + 1, copy);
      currentLayerId = copy.id;
      selection = [for (final o in copy.objects) o.id];
    });
  }

  /// Line objects up. With several selected they align to each other; with
  /// one, to the page. [how] is left, centre, right, top, middle or bottom.
  void alignSelection(String how) {
    final objs = selectedObjects.where((o) => !o.locked).toList();
    if (objs.isEmpty) return;
    final frame = objs.length > 1
        ? unionRects(objs.map((o) => o.bounds))
        : Offset.zero & doc.canvasSize;
    transact('align', () {
      for (final o in objs) {
        final b = o.bounds;
        final d = switch (how) {
          'left' => Offset(frame.left - b.left, 0),
          'right' => Offset(frame.right - b.right, 0),
          'centre' => Offset(frame.center.dx - b.center.dx, 0),
          'top' => Offset(0, frame.top - b.top),
          'bottom' => Offset(0, frame.bottom - b.bottom),
          'middle' => Offset(0, frame.center.dy - b.center.dy),
          _ => Offset.zero,
        };
        o.translate(d);
      }
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
      for (final o in objs) {
        final layer = doc.layerOf(o.id) ?? currentLayer;
        final copy = o.copyWith(id: doc.newId('o'))
          ..translate(const Offset(24, 24));
        layer.objects.add(copy);
        ids.add(copy.id);
      }
      selection = ids;
    });
  }

  void nudge(Offset d) {
    final objs = selectedObjects.where((o) => !o.locked).toList();
    if (objs.isEmpty) return;
    transact('nudge', () {
      for (final o in objs) {
        o.translate(d);
      }
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

  CollectionItem addToCollection(Asset a, {String? name}) {
    final item = CollectionItem(
      id: doc.newId('c'),
      name: name ?? 'item ${doc.collection.length + 1}',
      assetId: a.id,
    );
    transact('add to collection', () => doc.collection.add(item));
    return item;
  }

  void removeFromCollection(String id) {
    final i = doc.collection.indexWhere((c) => c.id == id);
    transact(
      'remove from collection',
      () => doc.collection.removeWhere((c) => c.id == id),
    );
    // Keep the highlight on a neighbour, so Delete can carry on down the shelf.
    if (_collectionSel == id) {
      _collectionSel = doc.collection.isEmpty
          ? null
          : doc.collection[i.clamp(0, doc.collection.length - 1)].id;
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

  void renameCollectionItem(String id, String name) =>
      transact('rename item', () {
        for (final c in doc.collection) {
          if (c.id == id && name.trim().isNotEmpty) c.name = name.trim();
        }
      });

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
          CollectionItem(id: doc.newId('c'), name: o.name, assetId: o.assetId),
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

  /// Paste an image straight into the collection, skipping the question.
  Future<void> pasteToCollection() async {
    final bytes = await SystemClipboard.readImage();
    if (bytes == null) {
      showToast('There is no image on the clipboard');
      return;
    }
    final a = await assets.addEncoded(bytes);
    addToCollection(a, name: uniqueName('image'));
  }

  /// Offer to place a new image on the page or in the collection.
  void _receiveImage(Asset a, String name) {
    switch (pasteMode) {
      case PasteMode.layer:
        placeAsset(a);
      case PasteMode.collection:
        addToCollection(a, name: uniqueName('image'));
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
        addToCollection(a, name: uniqueName('image'));
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
        final base = path.split('/').last.replaceAll(RegExp(r'\.[^.]+$'), '');
        if (toCollection) {
          addToCollection(a, name: base);
        } else {
          placeAsset(a, name: uniqueName(base), at: at);
        }
      } catch (_) {
        showToast('Could not open ${path.split('/').last}');
      }
    }
  }

  void copySelection() {
    final objs = selectedObjects;
    if (objs.isEmpty) return;
    _clip = [for (final o in objs) o.copyWith()];
    _pasteCount = 0;
    showToast('Copied');
    unawaited(_copyRenderedSelection(objs));
  }

  Future<void> _copyRenderedSelection(List<SceneObject> objs) async {
    try {
      final b = unionRects(objs.map((o) => o.bounds)).inflate(2);
      final rec = ui.PictureRecorder();
      final c = ui.Canvas(rec);
      c.translate(-b.left, -b.top);
      for (final o in objs) {
        paintObject(c, o, assets);
      }
      final img = await rec.endRecording().toImage(
        b.width.ceil(),
        b.height.ceil(),
      );
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      final png = data!.buffer.asUint8List();
      _lastCopySig = _sig(png);
      if (!await SystemClipboard.writeImage(png)) {
        showToast(
          'Copied inside Thinkspace. To paste into other apps, install xclip (X11) or wl-clipboard (Wayland)',
        );
      }
    } catch (_) {
      showToast("Couldn't copy the selection as a picture");
    }
  }

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
      for (final o in _clip) {
        final copy = o.copyWith(id: doc.newId('o'))..translate(off);
        currentLayer.objects.add(copy);
        ids.add(copy.id);
      }
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
      showToast(
        ok
            ? 'Copied the page as an image'
            : 'Install xclip (X11) or wl-clipboard (Wayland) to copy images',
      );
    } catch (_) {
      showToast("Couldn't copy the page as an image");
    }
  }

  /// Merge the selected objects into one picture. The originals are replaced
  /// (undo brings them back).
  Future<ImageObject?> flattenSelection() async {
    if (_flattening) return null; // a second press while one is under way
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
    final ordered = mergeable;
    final chosen = {for (final o in ordered) o.id};
    if (ordered.isEmpty) return null;
    final b = unionRects(ordered.map((o) => o.bounds)).inflate(1);
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
    for (final o in ordered) {
      if (o.visible) paintObject(canvas, o, assets);
    }
    final img = await rec.endRecording().toImage(
      (b.width * scale).ceil(),
      (b.height * scale).ceil(),
    );
    final asset = await assets.addImage(img);
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
        parts: [for (final o in ordered) o.toJson()],
      ),
    );
    transact('merge into one image', () {
      for (final l in doc.layers) {
        l.objects.removeWhere((o) => chosen.contains(o.id));
      }
      topLayer.objects.add(merged);
      selection = [merged.id];
      currentLayerId = topLayer.id;
    });
    return merged;
  }

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
    final sel = mergeable;
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
      showToast("Couldn't unmerge this picture");
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
      for (final j in rec.parts) {
        final json = Map<String, dynamic>.from(j)..['id'] = doc.newId('o');
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
          case LineObject():
            p.p1 = map(p.p1);
            p.p2 = map(p.p2);
            p.width *= k;
          case StrokeObject():
            p.points = [for (final q in p.points) map(q)];
            p.width *= k;
        }
        made.add(p);
      }
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

  Future<bool> removeBackgroundFrom(ImageObject o, {double? tolerance}) async {
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
    return true;
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
    markSaved();
    fitToView(notify: false);
    notifyListeners();
    if (unreadable > 0) {
      showToast(
        unreadable == 1
            ? "1 picture couldn't be read and was left out"
            : "$unreadable pictures couldn't be read and were left out",
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
      showToast('Could not save ${path.split('/').last} — nothing was changed');
      return false;
    }
    filePath = path;
    markSaved();
    clearRecovery();
    showToast('Saved ${path.split('/').last}');
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
      showToast('Could not export ${path.split('/').last}');
      return false;
    }
    showToast('Exported ${path.split('/').last}');
    return true;
  }

  Future<void> openFrom(String path) async {
    final bad = await loadProjectJson(
      await File(path).readAsString(),
      path: path,
    );
    if (bad == 0) showToast('Opened ${path.split('/').last}');
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
