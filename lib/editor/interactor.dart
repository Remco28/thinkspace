import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../model/geometry.dart';
import '../model/scene.dart';
import 'controller.dart';
import 'render.dart';

enum _Mode {
  none,
  pan,
  move,
  resize,
  rotate,
  lineEnd,
  marquee,
  create,
  pen,
  lasso,
  cutBox,
  gripResize,
  textBox,
}

class Modifiers {
  const Modifiers({this.shift = false, this.ctrl = false, this.alt = false});
  final bool shift, ctrl, alt;
}

/// Turns raw pointer input into document edits. Every gesture is one undo
/// step: the picture follows the hand, the history records it on release.
class CanvasInteractor {
  CanvasInteractor(this.c);
  final EditorController c;

  _Mode _mode = _Mode.none;
  EditToken? _token;
  Offset _startScene = Offset.zero;
  Offset _startScreen = Offset.zero;
  Offset _lastScreen = Offset.zero;
  bool _moved = false;

  // move
  Rect _startBounds = Rect.zero;
  Offset _applied = Offset.zero;
  List<SceneObject> _candidates = const [];
  bool _clickOnSelectedTop = false;
  bool _stickyCycle = false;
  bool _selectTopOnRelease = false;
  bool _additive = false;
  Offset _cyclePoint = const Offset(double.infinity, 0);
  int _cycleIndex = 0;

  // handles
  HandleSpot? _handle;
  SceneObject? _startObj;
  CanvasGrip? _grip;
  Size _startCanvas = Size.zero;
  Offset _gripGrab = Offset.zero;

  // creation
  String? _createId;
  List<Offset> _penPoints = [];
  bool _penStraight = false;
  ImageObject? _cutTarget;

  // double click
  DateTime _lastDown = DateTime.fromMillisecondsSinceEpoch(0);
  Offset _lastDownScreen = Offset.zero;

  bool get active => _mode != _Mode.none;

  // ---- snapping ------------------------------------------------------------

  bool _snapping(Modifiers m) => c.snapOn && !m.ctrl;

  /// Snap one coordinate. The page's own edges and centre win when they are
  /// close (so things can be made to fill the page exactly, whatever its
  /// size); otherwise the grid.
  double _snapAxis(double v, List<double> pageLines) {
    final near = 10 / c.zoom;
    double? best;
    for (final l in pageLines) {
      if ((l - v).abs() <= near &&
          (best == null || (l - v).abs() < (best - v).abs())) {
        best = l;
      }
    }
    return best ?? snapToGrid(v, c.doc.gridSize);
  }

  List<double> get _pageXs {
    final w = c.doc.canvasSize.width;
    return [0, w / 2, w];
  }

  List<double> get _pageYs {
    final h = c.doc.canvasSize.height;
    return [0, h / 2, h];
  }

  Offset _snapPoint(Offset p, Modifiers m) {
    if (!_snapping(m)) return p;
    return Offset(_snapAxis(p.dx, _pageXs), _snapAxis(p.dy, _pageYs));
  }

  Offset _snapDelta(Rect start, Offset delta) {
    final r = start.shift(delta);
    double best(List<double> vs, List<double> pageLines) {
      double pick = 0;
      double bestAbs = double.infinity;
      for (final v in vs) {
        final d = _snapAxis(v, pageLines) - v;
        if (d.abs() < bestAbs) {
          bestAbs = d.abs();
          pick = d;
        }
      }
      return pick;
    }

    return delta +
        Offset(
          best([r.left, r.center.dx, r.right], _pageXs),
          best([r.top, r.center.dy, r.bottom], _pageYs),
        );
  }

  // ---- hover ---------------------------------------------------------------

  MouseCursor cursorAt(Offset screen, {bool spaceDown = false}) {
    if (_mode == _Mode.pan || spaceDown) return SystemMouseCursors.grab;
    if (c.tool != Tool.select) return SystemMouseCursors.precise;
    final p = c.toScene(screen);
    final h = _hitHandle(p);
    if (h != null) {
      if (h.kind == HandleKind.rotate) return SystemMouseCursors.grab;
      if (h.kind != HandleKind.resize) return SystemMouseCursors.precise;
      if (h.hx == 0) return SystemMouseCursors.resizeUpDown;
      if (h.hy == 0) return SystemMouseCursors.resizeLeftRight;
      return h.hx == h.hy
          ? SystemMouseCursors.resizeUpLeftDownRight
          : SystemMouseCursors.resizeUpRightDownLeft;
    }
    final g = _hitGrip(p);
    if (g != null) {
      return g == CanvasGrip.right
          ? SystemMouseCursors.resizeLeftRight
          : g == CanvasGrip.bottom
          ? SystemMouseCursors.resizeUpDown
          : SystemMouseCursors.resizeUpLeftDownRight;
    }
    if (c.objectsAt(p).isNotEmpty) return SystemMouseCursors.move;
    return SystemMouseCursors.basic;
  }

  HandleSpot? _hitHandle(Offset p) {
    final o = c.single;
    if (o == null || o.locked || c.editingTextId != null) return null;
    final r = 9 / c.zoom;
    HandleSpot? best;
    double bestD = r;
    for (final h in c.handlesFor(o)) {
      final d = (h.pos - p).distance;
      if (d <= bestD) {
        bestD = d;
        best = h;
      }
    }
    return best;
  }

  CanvasGrip? _hitGrip(Offset p) {
    final r = 14 / c.zoom;
    for (final e in c.gripPositions.entries) {
      if ((e.value - p).distance <= r) return e.key;
    }
    return null;
  }

  // ---- pointer down --------------------------------------------------------

  void pointerDown(Offset screen, Modifiers m, {bool forcePan = false}) {
    _startScreen = _lastScreen = screen;
    _startScene = c.toScene(screen);
    _moved = false;
    final now = DateTime.now();
    final isDouble =
        now.difference(_lastDown).inMilliseconds < 350 &&
        (screen - _lastDownScreen).distance < 6;
    _lastDown = now;
    _lastDownScreen = screen;

    if (forcePan) {
      _mode = _Mode.pan;
      return;
    }
    if (c.editingTextId != null) c.finishTextEdit();
    final p = _startScene;

    switch (c.tool) {
      case Tool.select:
        _downSelect(p, m, isDouble);
      case Tool.line:
      case Tool.arrow:
        _downLine(p, m);
      case Tool.rect:
      case Tool.ellipse:
        _downShape(p, m);
      case Tool.text:
        _mode = _Mode.textBox;
        _token = c.beginEdit('add text');
      case Tool.pen:
        _downPen(p);
      case Tool.badge:
        _downBadge(p, m);
      case Tool.cutout:
        _downCutout(p);
    }
  }

  void _downSelect(Offset p, Modifiers m, bool isDouble) {
    final handle = _hitHandle(p);
    if (handle != null) {
      final obj = c.single!;
      _handle = handle;
      _startObj = obj.copyWith();
      _token = c.beginEdit(
        handle.kind == HandleKind.rotate ? 'rotate' : 'resize',
      );
      _mode = switch (handle.kind) {
        HandleKind.rotate => _Mode.rotate,
        HandleKind.resize => _Mode.resize,
        _ => _Mode.lineEnd,
      };
      return;
    }
    final grip = _hitGrip(p);
    if (grip != null) {
      _grip = grip;
      _startCanvas = c.doc.canvasSize;
      // Keep the page edge under the same spot of the grip you grabbed.
      _gripGrab = c.gripPositions[grip]! - p;
      _token = c.beginEdit('resize canvas');
      _mode = _Mode.gripResize;
      return;
    }

    final hits = c.objectsAt(p);
    _candidates = hits;
    _clickOnSelectedTop = false;
    _stickyCycle = false;
    _selectTopOnRelease = false;
    _additive = m.shift;

    if (hits.isEmpty) {
      if (!m.shift) c.select([]);
      _mode = _Mode.marquee;
      return;
    }

    if (isDouble && hits.first is TextObject) {
      _mode = _Mode.none;
      c.beginTextEdit(hits.first.id);
      return;
    }

    SceneObject target = hits.first;
    if (m.alt && hits.length > 1) {
      // Alt-click reaches the object beneath the current one.
      final i = hits.indexWhere((o) => c.selection.contains(o.id));
      target = hits[(i + 1) % hits.length];
      c.select([target.id]);
    } else if (m.shift) {
      c.toggleSelect(target.id);
      if (!c.selection.contains(target.id)) {
        _mode = _Mode.none;
        return;
      }
    } else if ((p - _cyclePoint).distance < 5 / c.zoom &&
        c.selection.length == 1 &&
        _cycleIndex < hits.length &&
        hits[_cycleIndex].id == c.selection.first) {
      _stickyCycle = true; // keep going down the stack on a plain click
      target = hits[_cycleIndex];
    } else if (c.selection.length == 1 &&
        c.selection.first == target.id &&
        hits.length > 1) {
      _clickOnSelectedTop = true;
    } else if (c.selection.isNotEmpty &&
        !c.selection.contains(target.id) &&
        hits.any((o) => c.selection.contains(o.id))) {
      // Pressing where a selected object sits beneath something else keeps
      // the selection, so it can be dragged; a plain click still picks the top.
      _selectTopOnRelease = true;
    } else if (!c.selection.contains(target.id)) {
      c.select([target.id]);
    }

    _startBounds = c.selectionBounds;
    _applied = Offset.zero;
    _startObj = null;
    _token = c.beginEdit('move');
    _mode = _Mode.move;
  }

  void _downLine(Offset p, Modifiers m) {
    _token = c.beginEdit(c.tool == Tool.arrow ? 'draw arrow' : 'draw line');
    final a = _snapPoint(p, m);
    final l = LineObject(
      id: c.doc.newId('o'),
      name: c.uniqueName(c.tool == Tool.arrow ? 'arrow' : 'line'),
      p1: a,
      p2: a,
      color: c.penColor,
      width: c.penWidth,
      headEnd: c.tool == Tool.arrow,
    );
    c.currentLayer.objects.add(l);
    c.selection = [l.id];
    _createId = l.id;
    _mode = _Mode.create;
    c.notify();
  }

  void _downShape(Offset p, Modifiers m) {
    _token = c.beginEdit(
      c.tool == Tool.ellipse ? 'draw ellipse' : 'draw rectangle',
    );
    final a = _snapPoint(p, m);
    final s = ShapeObject(
      id: c.doc.newId('o'),
      name: c.uniqueName(c.tool == Tool.ellipse ? 'ellipse' : 'rectangle'),
      ellipse: c.tool == Tool.ellipse,
      center: a,
      size: const Size(1, 1),
      stroke: c.penColor,
      fill: c.fillColor,
      strokeWidth: c.penWidth,
    );
    c.currentLayer.objects.add(s);
    c.selection = [s.id];
    _createId = s.id;
    _mode = _Mode.create;
    c.notify();
  }

  void _downBadge(Offset p, Modifiers m) {
    final token = c.beginEdit('add marker');
    final at = _snapPoint(p, m);
    final n = c.nextBadgeNumber();
    final b = BadgeObject(
      id: c.doc.newId('o'),
      name: 'marker $n',
      number: n,
      center: at,
      size: const Size(44, 44),
      color: c.penColor,
    );
    c.currentLayer.objects.add(b);
    c.selection = [b.id];
    c.endEdit(token);
    _mode = _Mode.none;
    // The marker stays active so several can be dropped in a row.
  }

  void _downPen(Offset p) {
    _token = c.beginEdit('draw');
    _penPoints = [p];
    _penStraight = false;
    final s = StrokeObject(
      id: c.doc.newId('o'),
      name: c.uniqueName('pen'),
      points: [p],
      color: c.penColor,
      width: c.penWidth,
    );
    c.currentLayer.objects.add(s);
    c.selection = [s.id];
    _createId = s.id;
    _mode = _Mode.pen;
    c.notify();
  }

  void _downCutout(Offset p) {
    // The selected image wins unless the drag starts on a different image.
    final sel = c.single;
    final under = c.imageAt(p);
    ImageObject? target = under;
    if (sel is ImageObject &&
        (under == null ||
            under.id == sel.id ||
            sel.containsLocal(sel.toLocal(p), 0))) {
      target = sel;
    }
    if (target == null) {
      c.showToast('Click on an image to cut from it');
      _mode = _Mode.none;
      return;
    }
    _cutTarget = target;
    switch (c.cutoutMode) {
      case CutoutMode.wand:
        _mode = _Mode.none;
        c.select([target.id]);
        c.removeColorAt(target, p).then((ok) {
          if (ok) c.toolDone();
          c.notify();
        });
      case CutoutMode.lasso:
        c.lasso = [p];
        _mode = _Mode.lasso;
      case CutoutMode.box:
        c.cutBox = Rect.fromPoints(p, p);
        _mode = _Mode.cutBox;
    }
    c.notify();
  }

  // ---- pointer move --------------------------------------------------------

  void pointerMove(Offset screen, Modifiers m) {
    final deltaScreen = screen - _lastScreen;
    _lastScreen = screen;
    final p = c.toScene(screen);
    if (!_moved && (screen - _startScreen).distance > 3) _moved = true;

    switch (_mode) {
      case _Mode.none:
        return;
      case _Mode.pan:
        c.panBy(deltaScreen);
      case _Mode.move:
        if (!_moved) return;
        _doMove(p, m);
      case _Mode.resize:
        _doResize(p, m);
      case _Mode.rotate:
        _doRotate(p, m);
      case _Mode.lineEnd:
        _doLineEnd(p, m);
      case _Mode.marquee:
        c.marquee = Rect.fromPoints(_startScene, p);
        c.notify();
      case _Mode.create:
        _doCreate(p, m);
      case _Mode.pen:
        _doPen(p, m);
      case _Mode.lasso:
        final pts = c.lasso!;
        if ((pts.last - p).distance * c.zoom > 2) pts.add(p);
        c.notify();
      case _Mode.cutBox:
        c.cutBox = Rect.fromPoints(_startScene, p);
        c.notify();
      case _Mode.gripResize:
        _doGrip(p, m);
      case _Mode.textBox:
        c.marquee = Rect.fromPoints(_startScene, p);
        c.notify();
    }
  }

  void _doMove(Offset p, Modifiers m) {
    var total = p - _startScene;
    if (m.shift) {
      // Hold shift to keep to one axis.
      if (total.dx.abs() > total.dy.abs()) {
        total = Offset(total.dx, 0);
      } else {
        total = Offset(0, total.dy);
      }
    }
    if (_snapping(m)) total = _snapDelta(_startBounds, total);
    final step = total - _applied;
    if (step == Offset.zero) return;
    for (final o in c.selectedObjects) {
      if (!o.locked) o.translate(step);
    }
    _applied = total;
    c.notify();
  }

  void _doResize(Offset p, Modifiers m) {
    final h = _handle!;
    final start = _startObj as BoxObject;
    final live = c.doc.objectById(start.id) as BoxObject?;
    if (live == null) return;
    final sp = (start.rotation == 0) ? _snapPoint(p, m) : p;
    final q = start.toLocal(sp);
    final w0 = start.size.width, h0 = start.size.height;
    final ax = h.hx == 0 ? 0.0 : -h.hx * w0 / 2;
    final ay = h.hy == 0 ? 0.0 : -h.hy * h0 / 2;
    const minS = 8.0;
    var nw = h.hx == 0 ? w0 : math.max(minS, (q.dx - ax) * h.hx);
    var nh = h.hy == 0 ? h0 : math.max(minS, (q.dy - ay) * h.hy);
    final corner = h.hx != 0 && h.hy != 0;

    if (live is TextObject && start is TextObject) {
      nw = math.max(nw, 40.0);
      if (corner) {
        final k = math.max(nw / w0, 0.1);
        live.fontSize = (start.fontSize * k).clamp(6, 600).toDouble();
        nw = w0 * k;
      }
      live.size = Size(nw, h0);
      live.size = Size(nw, measureTextHeight(live));
      // A top handle moves the top edge, so the bottom stays put.
      final cy = h.hy < 0
          ? h0 / 2 - live.size.height / 2
          : -h0 / 2 + live.size.height / 2;
      final cx = h.hx == 0 ? 0.0 : ax + h.hx * nw / 2;
      live.center = start.toScene(Offset(cx, cy));
      c.notify();
      return;
    }

    final lockAspect =
        start is BadgeObject || (start is ImageObject ? !m.shift : m.shift);
    if (corner && lockAspect) {
      final k = math.max(nw / w0, nh / h0);
      nw = w0 * k;
      nh = h0 * k;
    }
    live.size = Size(nw, nh);
    final cx = h.hx == 0 ? 0.0 : ax + h.hx * nw / 2;
    final cy = h.hy == 0 ? 0.0 : ay + h.hy * nh / 2;
    live.center = start.toScene(Offset(cx, cy));
    c.notify();
  }

  void _doRotate(Offset p, Modifiers m) {
    final start = _startObj as BoxObject;
    final live = c.doc.objectById(start.id) as BoxObject?;
    if (live == null) return;
    var a =
        math.atan2(p.dy - start.center.dy, p.dx - start.center.dx) +
        math.pi / 2;
    const step = math.pi / 12;
    final nearest = (a / step).roundToDouble() * step;
    if (m.shift || (!m.ctrl && (a - nearest).abs() < 0.07)) a = nearest;
    live.rotation = normalizeAngle(a);
    c.notify();
  }

  void _doLineEnd(Offset p, Modifiers m) {
    final h = _handle!;
    final start = _startObj as LineObject;
    final live = c.doc.objectById(start.id) as LineObject?;
    if (live == null) return;
    final fixed = h.kind == HandleKind.lineStart ? start.p2 : start.p1;
    final np = _constrain(fixed, _snapPoint(p, m), m);
    if (h.kind == HandleKind.lineStart) {
      live.p1 = np;
    } else {
      live.p2 = np;
    }
    c.notify();
  }

  Offset _constrain(Offset from, Offset to, Modifiers m) {
    if (!m.shift) return to;
    final d = to - from;
    final len = d.distance;
    if (len == 0) return to;
    const step = math.pi / 12;
    final a = (math.atan2(d.dy, d.dx) / step).roundToDouble() * step;
    return from + Offset(math.cos(a), math.sin(a)) * len;
  }

  void _doCreate(Offset p, Modifiers m) {
    final o = c.doc.objectById(_createId!);
    if (o is LineObject) {
      o.p2 = _constrain(o.p1, _snapPoint(p, m), m);
    } else if (o is ShapeObject) {
      final a = _snapPoint(_startScene, m);
      var b = _snapPoint(p, m);
      if (m.shift) {
        final d = b - a;
        final s = math.max(d.dx.abs(), d.dy.abs());
        b = a + Offset(d.dx.isNegative ? -s : s, d.dy.isNegative ? -s : s);
      }
      final r = Rect.fromPoints(a, b);
      o.center = r.center;
      o.size = Size(math.max(1, r.width), math.max(1, r.height));
    }
    c.notify();
  }

  void _doPen(Offset p, Modifiers m) {
    final o = c.doc.objectById(_createId!) as StrokeObject?;
    if (o == null) return;
    // Holding Shift turns the stroke into one straight line from where it
    // began, at the nearest 15 degrees; letting go carries on freehand.
    _penStraight = m.shift;
    if (m.shift) {
      _penPoints = [_penPoints.first, _constrain(_penPoints.first, p, m)];
      o.points = List.of(_penPoints);
      c.notify();
      return;
    }
    if ((_penPoints.last - p).distance * c.zoom < 1.5) return;
    _penPoints.add(p);
    o.points = List.of(_penPoints);
    c.notify();
  }

  void _doGrip(Offset p, Modifiers m) {
    final target = p + _gripGrab;
    final content = contentBounds(c.doc);
    final near = 10 / c.zoom;
    // Priority: land exactly on the content's far edge, then the grid, then
    // whole pixels. Ctrl turns the first two off.
    double fit(double v, double? contentEdge) {
      if (!m.ctrl && contentEdge != null && (v - contentEdge).abs() <= near) {
        return contentEdge;
      }
      return _snapping(m) ? snapToGrid(v, c.doc.gridSize) : v.roundToDouble();
    }

    final has = !content.isEmpty;
    var w = _startCanvas.width, h = _startCanvas.height;
    if (_grip != CanvasGrip.bottom) {
      w = math.max(64, fit(target.dx, has ? content.right : null));
    }
    if (_grip != CanvasGrip.right) {
      h = math.max(64, fit(target.dy, has ? content.bottom : null));
    }
    if (_grip == CanvasGrip.corner && m.shift) {
      final k = math.max(w / _startCanvas.width, h / _startCanvas.height);
      w = _startCanvas.width * k;
      h = _startCanvas.height * k;
    }
    c.doc.canvasSize = Size(
      w.clamp(64, 12000).toDouble(),
      h.clamp(64, 12000).toDouble(),
    );
    c.notify();
  }

  // ---- pointer up ----------------------------------------------------------

  void pointerUp(Offset screen, Modifiers m) {
    final p = c.toScene(screen);
    final mode = _mode;
    _mode = _Mode.none;
    final token = _token;
    _token = null;

    switch (mode) {
      case _Mode.none:
      case _Mode.pan:
        return;
      case _Mode.move:
        if (!_moved) {
          _finishClick(p);
        }
        if (token != null) c.endEdit(token);
      case _Mode.resize:
      case _Mode.rotate:
      case _Mode.lineEnd:
      case _Mode.gripResize:
        if (token != null) c.endEdit(token);
      case _Mode.marquee:
        final r = c.marquee;
        c.marquee = null;
        if (r != null && _moved) _finishMarquee(r);
        c.notify();
      case _Mode.create:
        _finishCreate(token, p, m);
      case _Mode.pen:
        _finishPen(token);
      case _Mode.textBox:
        _finishTextBox(token, p, m);
      case _Mode.lasso:
        final pts = c.lasso;
        c.lasso = null;
        if (pts != null) _finishCut(simplifyPolyline(pts, 1 / c.zoom));
      case _Mode.cutBox:
        final r = c.cutBox;
        c.cutBox = null;
        if (r != null) {
          _finishCut([r.topLeft, r.topRight, r.bottomRight, r.bottomLeft]);
        }
    }
    c.notify();
  }

  void _finishClick(Offset p) {
    final hits = _candidates;
    if (_selectTopOnRelease && hits.isNotEmpty) {
      c.select([hits.first.id]);
      return;
    }
    if (hits.length < 2) return;
    if (_clickOnSelectedTop || _stickyCycle) {
      final cur = _stickyCycle ? _cycleIndex : 0;
      final next = (cur + 1) % hits.length;
      _cyclePoint = p;
      _cycleIndex = next;
      c.select([hits[next].id]);
      c.showToast('${hits[next].name} (click again for the next one beneath)');
    }
  }

  void _finishMarquee(Rect r) {
    final ids = <String>[
      for (final layer in c.doc.layers)
        if (layer.visible && !layer.locked)
          for (final o in layer.objects)
            if (o.visible && !o.locked && o.bounds.overlaps(r)) o.id,
    ];
    if (_additive) {
      c.select({...c.selection, ...ids}.toList());
    } else {
      c.select(ids);
    }
  }

  void _finishCreate(EditToken? token, Offset p, Modifiers m) {
    final o = c.doc.objectById(_createId!);
    var keep = true;
    if (o is LineObject && o.length < 4) keep = false;
    if (o is ShapeObject && (o.size.width < 6 && o.size.height < 6)) {
      // A plain click makes a default-sized shape.
      o.size = const Size(180, 120);
      o.center = _snapPoint(_startScene, m) + const Offset(90, 60);
    }
    if (!keep) {
      c.doc.layerOf(o!.id)?.objects.remove(o);
      c.selection = [];
    } else {
      c.toolDone();
    }
    if (token != null) c.endEdit(token);
  }

  void _finishPen(EditToken? token) {
    final o = c.doc.objectById(_createId!) as StrokeObject?;
    if (o != null && o.points.length > 2 && !_penStraight) {
      o.points = simplifyPolyline(o.points, 1.2 / c.zoom);
    }
    if (token != null) c.endEdit(token);
    // The pen stays active: sketching is usually many strokes.
  }

  void _finishTextBox(EditToken? token, Offset p, Modifiers m) {
    c.marquee = null;
    final a = _snapPoint(_startScene, m);
    final w = _moved ? math.max(80.0, (p.dx - a.dx).abs()) : 320.0;
    final left = _moved ? math.min(a.dx, p.dx) : a.dx;
    final t = c.createText(Offset(left, a.dy), width: w, text: '');
    t.text = 'Text';
    t.size = Size(w, measureTextHeight(t));
    t.center = Offset(left + w / 2, a.dy + t.size.height / 2);
    c.currentLayer.objects.add(t);
    c.toolDone();
    c.beginTextEdit(t.id, token: token);
  }

  void _finishCut(List<Offset> poly) {
    final target = _cutTarget;
    _cutTarget = null;
    if (target == null || poly.length < 3) return;
    c.cutout(target, poly).then((res) {
      if (res != null) {
        c.toolDone();
        c.showToast('Cut out — drag the new piece away');
      }
      c.notify();
    });
  }

  /// Escape: drop the gesture in progress.
  void cancel() {
    final t = _token;
    _mode = _Mode.none;
    _token = null;
    c.marquee = null;
    c.lasso = null;
    c.cutBox = null;
    if (t != null) c.abortEdit(t);
  }

  // ---- wheel ---------------------------------------------------------------

  void scroll(Offset screen, Offset delta, Modifiers m) {
    if (m.shift) {
      c.panBy(Offset(-delta.dy, 0));
      return;
    }
    final f = math.exp(-delta.dy / 400);
    c.zoomTo(c.zoom * f, anchorScreen: screen);
  }
}
