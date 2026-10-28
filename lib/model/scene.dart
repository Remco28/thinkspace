import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'assets.dart';
import 'geometry.dart';

enum ObjectKind { image, text, rect, ellipse, line, stroke, badge, hide }

Offset _off(dynamic j) =>
    Offset((j[0] as num).toDouble(), (j[1] as num).toDouble());
List<double> _offJson(Offset o) => [o.dx, o.dy];

Offset? _tryOff(Object? j) {
  try {
    if (j == null) return null;
    final o = _off(j);
    return o.dx.isFinite && o.dy.isFinite ? o : null;
  } catch (_) {
    return null;
  }
}

/// Something on the page. Position, size and look are all plain data so the
/// whole document can be snapshotted for undo and written to disk.
abstract class SceneObject {
  SceneObject({
    required this.id,
    required this.name,
    this.opacity = 1,
    this.visible = true,
    this.locked = false,
  });

  final String id;
  String name;
  double opacity;
  bool visible;
  bool locked;

  ObjectKind get kind;

  /// Axis-aligned bounds in page coordinates, including rotation and stroke.
  Rect get bounds;

  /// Everything drawn for this object, including a border and its shadow.
  /// Selecting, snapping and aligning use [bounds]; whatever must hold the
  /// drawn pixels (a layer, a merge, a copy) uses this.
  Rect get paintBounds => bounds;

  bool hitTest(Offset p, double tolerance, AssetStore assets);
  void translate(Offset d);
  SceneObject copyWith({String? id, String? name});
  Map<String, dynamic> toJson();

  Map<String, dynamic> baseJson(String type) => {
    'type': type,
    'id': id,
    'name': name,
    'opacity': opacity,
    'visible': visible,
    'locked': locked,
  };

  static SceneObject fromJson(Map<String, dynamic> j) {
    switch (j['type']) {
      case 'image':
        return ImageObject.fromJson(j);
      case 'text':
        return TextObject.fromJson(j);
      case 'rect':
      case 'ellipse':
        return ShapeObject.fromJson(j);
      case 'line':
        return LineObject.fromJson(j);
      case 'stroke':
        return StrokeObject.fromJson(j);
      case 'badge':
        return BadgeObject.fromJson(j);
      case 'hide':
        return HideObject.fromJson(j);
    }
    throw FormatException('Unknown object type ${j['type']}');
  }
}

/// An object defined by a centre, a size and a rotation.
abstract class BoxObject extends SceneObject {
  BoxObject({
    required super.id,
    required super.name,
    required this.center,
    required this.size,
    this.rotation = 0,
    this.flipX = false,
    super.opacity,
    super.visible,
    super.locked,
  });

  Offset center;
  Size size;
  double rotation;
  bool flipX;

  Offset toLocal(Offset p) => rotateOffset(p - center, -rotation);
  Offset toScene(Offset local) => center + rotateOffset(local, rotation);

  List<Offset> get corners {
    final hw = size.width / 2, hh = size.height / 2;
    return [
      toScene(Offset(-hw, -hh)),
      toScene(Offset(hw, -hh)),
      toScene(Offset(hw, hh)),
      toScene(Offset(-hw, hh)),
    ];
  }

  @override
  Rect get bounds => rectFromPoints(corners);

  bool containsLocal(Offset l, double tol) =>
      l.dx.abs() <= size.width / 2 + tol && l.dy.abs() <= size.height / 2 + tol;

  @override
  bool hitTest(Offset p, double tolerance, AssetStore assets) =>
      containsLocal(toLocal(p), tolerance);

  @override
  void translate(Offset d) => center += d;

  Map<String, dynamic> boxJson(String type) => {
    ...baseJson(type),
    'center': _offJson(center),
    'size': [size.width, size.height],
    'rotation': rotation,
    'flipX': flipX,
  };

  void readBox(Map<String, dynamic> j) {
    center = _off(j['center']);
    size = Size(
      (j['size'][0] as num).toDouble(),
      (j['size'][1] as num).toDouble(),
    );
    rotation = (j['rotation'] as num?)?.toDouble() ?? 0;
    flipX = j['flipX'] as bool? ?? false;
  }
}

/// How far the shadow under a framed object falls, and how soft it is.
const Offset kShadowOffset = Offset(0, 3);
const double kShadowBlur = 6;

/// A border and a soft shadow around a picture or a text box. The border is
/// drawn outside the edge, so the object's own size never changes.
mixin Framed on BoxObject {
  /// 0 means no border.
  int border = 0;
  double borderWidth = 4;
  bool shadow = false;

  static const double defaultWidth = 4;

  /// How far the drawn border reaches beyond the edge.
  double get frameWidth => border != 0 ? borderWidth : 0;

  bool get framed => border != 0 || shadow;

  /// The box grown by the border, in the object's own frame.
  Rect get frameRect => Rect.fromCenter(
    center: Offset.zero,
    width: size.width + frameWidth * 2,
    height: size.height + frameWidth * 2,
  );

  @override
  Rect get paintBounds {
    if (!framed) return bounds;
    final r = frameRect;
    var out = rectFromPoints([
      toScene(r.topLeft),
      toScene(r.topRight),
      toScene(r.bottomRight),
      toScene(r.bottomLeft),
    ]);
    if (shadow) {
      out = out.expandToInclude(
        out.shift(kShadowOffset).inflate(kShadowBlur * 3),
      );
    }
    return out.expandToInclude(bounds);
  }

  /// Whether [p] is on the border itself (not the object inside it).
  bool onBorder(Offset p, double tolerance) {
    if (border == 0) return false;
    final l = toLocal(p);
    final hw = size.width / 2, hh = size.height / 2;
    final fw = hw + frameWidth + tolerance, fh = hh + frameWidth + tolerance;
    if (l.dx.abs() > fw || l.dy.abs() > fh) return false;
    return l.dx.abs() >= hw || l.dy.abs() >= hh;
  }

  void copyFrame(Framed from) {
    border = from.border;
    borderWidth = from.borderWidth;
    shadow = from.shadow;
  }

  Map<String, dynamic> frameJson() => {
    if (border != 0) 'border': border,
    if (border != 0 && borderWidth != defaultWidth) 'borderWidth': borderWidth,
    if (shadow) 'shadow': true,
  };

  /// A damaged value falls back to no border, never to a file that won't open.
  void readFrame(Map<String, dynamic> j) {
    final b = j['border'];
    border = b is int ? b : 0;
    final w = j['borderWidth'];
    borderWidth = w is num && w.isFinite && w > 0 ? w.toDouble() : defaultWidth;
    shadow = j['shadow'] == true;
  }
}

/// What a merged picture was made from, so it can be taken apart again.
class MergeRecord {
  MergeRecord({
    required this.assetId,
    required this.center,
    required this.size,
    required this.parts,
  });

  /// The merged picture's pixels when it was made. The record is only good
  /// while the object still shows exactly these pixels.
  final String assetId;

  /// Where the merged picture sat on the page at that moment.
  final Offset center;
  final Size size;

  /// The originals, bottom to top, exactly as they were saved.
  final List<Map<String, dynamic>> parts;

  Map<String, dynamic> toJson() => {
    'asset': assetId,
    'center': [center.dx, center.dy],
    'size': [size.width, size.height],
    'parts': parts,
  };

  factory MergeRecord.fromJson(Map<String, dynamic> j) => MergeRecord(
    assetId: j['asset'],
    center: Offset(
      (j['center'][0] as num).toDouble(),
      (j['center'][1] as num).toDouble(),
    ),
    size: Size(
      (j['size'][0] as num).toDouble(),
      (j['size'][1] as num).toDouble(),
    ),
    parts: [
      for (final p in j['parts'] as List) Map<String, dynamic>.from(p as Map),
    ],
  );

  /// Every picture the originals used.
  Set<String> get assets {
    final out = <String>{};
    void walk(Object? v) {
      if (v is Map) {
        for (final e in v.entries) {
          if (e.key == 'asset' && e.value is String) {
            out.add(e.value as String);
          } else {
            walk(e.value);
          }
        }
      } else if (v is List) {
        v.forEach(walk);
      }
    }

    walk(parts);
    return out;
  }
}

class ImageObject extends BoxObject with Framed {
  ImageObject({
    required super.id,
    required super.name,
    required this.assetId,
    required super.center,
    required super.size,
    super.rotation,
    super.flipX,
    super.opacity,
    super.visible,
    super.locked,
    this.merged,
    this.multiply = false,
  });

  String assetId;

  /// Drawn multiplied onto what is under it instead of laid over it. Set on
  /// a picture made by merging highlighter marks, so the merged highlights
  /// stay see-through and keep writing readable, as the marks were.
  bool multiply;

  /// Set on a picture made by merging; see [canUnmerge].
  MergeRecord? merged;

  /// True while this picture is still exactly what the merge produced (moving,
  /// scaling, rotating and fading do not change that; cutting or recolouring
  /// does).
  bool get canUnmerge =>
      merged != null &&
      merged!.assetId == assetId &&
      merged!.size.width > 0 &&
      merged!.size.height > 0;

  @override
  ObjectKind get kind => ObjectKind.image;

  /// Transparent pixels (e.g. around a cutout) are not grabbable.
  @override
  bool hitTest(Offset p, double tolerance, AssetStore assets) {
    final l = toLocal(p);
    if (!containsLocal(l, tolerance)) return false;
    final a = assets[assetId];
    if (a == null) return true;
    var u = (l.dx / size.width + 0.5);
    if (flipX) u = 1 - u;
    final v = (l.dy / size.height + 0.5);
    final px = (u * a.width).floor(), py = (v * a.height).floor();
    // Look at a small neighbourhood so thin cutout edges stay easy to grab.
    final r = math.max(
      1,
      (tolerance * a.width / math.max(1, size.width)).ceil(),
    );
    for (int dy = -r; dy <= r; dy += r) {
      for (int dx = -r; dx <= r; dx += r) {
        if (a.alphaAt(px + dx, py + dy) > 24) return true;
      }
    }
    return false;
  }

  @override
  ImageObject copyWith({String? id, String? name}) => ImageObject(
    id: id ?? this.id,
    name: name ?? this.name,
    assetId: assetId,
    center: center,
    size: size,
    rotation: rotation,
    flipX: flipX,
    opacity: opacity,
    visible: visible,
    locked: locked,
    merged: merged,
    multiply: multiply,
  )..copyFrame(this);

  @override
  Map<String, dynamic> toJson() => {
    ...boxJson('image'),
    'asset': assetId,
    if (canUnmerge) 'merged': merged!.toJson(),
    if (multiply) 'multiply': true,
    ...frameJson(),
  };

  factory ImageObject.fromJson(Map<String, dynamic> j) {
    final o = ImageObject(
      id: j['id'],
      name: j['name'],
      assetId: j['asset'],
      center: Offset.zero,
      size: Size.zero,
      opacity: ((j['opacity'] ?? 1) as num).toDouble(),
      visible: j['visible'] ?? true,
      locked: j['locked'] ?? false,
      multiply: j['multiply'] == true,
    );
    o.readBox(j);
    o.readFrame(j);
    // The merge record is a convenience: a damaged one must not stop the
    // picture itself from opening.
    try {
      if (j['merged'] != null) {
        o.merged = MergeRecord.fromJson(
          Map<String, dynamic>.from(j['merged'] as Map),
        );
      }
    } catch (_) {}
    return o;
  }
}

/// The few typefaces text can use. Sans is the system's own font; the others
/// are bundled with the app so a project looks the same on any machine.
enum TextFont {
  sans('Sans', null),
  serif('Serif', 'Lora'),
  mono('Mono', 'JetBrains Mono'),
  hand('Hand', 'Caveat', 1.3);

  const TextFont(this.label, this.family, [this.scale = 1]);
  final String label;
  final String? family;

  /// Handwriting is small for its point size; this evens out the sizes so
  /// "28" looks about as big in every font.
  final double scale;

  static TextFont byName(Object? n) =>
      values.firstWhere((f) => f.name == n, orElse: () => sans);
}

class TextObject extends BoxObject with Framed {
  TextObject({
    required super.id,
    required super.name,
    required this.text,
    required super.center,
    required super.size,
    this.fontSize = 28,
    this.color = 0xFF222222,
    this.bold = false,
    this.italic = false,
    this.font = TextFont.sans,
    this.background = 0,
    this.align = TextAlign.left,
    super.rotation,
    super.opacity,
    super.visible,
    super.locked,
  });

  String text;
  double fontSize;
  int color;
  bool bold;
  bool italic;
  TextFont font;

  /// 0 means no background.
  int background;
  TextAlign align;

  static const double pad = 6;

  @override
  ObjectKind get kind => ObjectKind.text;

  @override
  TextObject copyWith({String? id, String? name}) => TextObject(
    id: id ?? this.id,
    name: name ?? this.name,
    text: text,
    center: center,
    size: size,
    fontSize: fontSize,
    color: color,
    bold: bold,
    italic: italic,
    font: font,
    background: background,
    align: align,
    rotation: rotation,
    opacity: opacity,
    visible: visible,
    locked: locked,
  )..copyFrame(this);

  @override
  Map<String, dynamic> toJson() => {
    ...boxJson('text'),
    'text': text,
    'fontSize': fontSize,
    'color': color,
    'bold': bold,
    'italic': italic,
    if (font != TextFont.sans) 'font': font.name,
    'background': background,
    'align': align.index,
    ...frameJson(),
  };

  factory TextObject.fromJson(Map<String, dynamic> j) {
    final o = TextObject(
      id: j['id'],
      name: j['name'],
      text: j['text'],
      center: Offset.zero,
      size: Size.zero,
      fontSize: (j['fontSize'] as num).toDouble(),
      color: j['color'],
      bold: j['bold'] ?? false,
      italic: j['italic'] ?? false,
      font: TextFont.byName(j['font']),
      background: j['background'] ?? 0,
      align:
          TextAlign.values[(_asInt(j['align']) ?? 0).clamp(
            0,
            TextAlign.values.length - 1,
          )],
      opacity: ((j['opacity'] ?? 1) as num).toDouble(),
      visible: j['visible'] ?? true,
      locked: j['locked'] ?? false,
    );
    o.readBox(j);
    o.readFrame(j);
    return o;
  }
}

/// How a highlighter mark sits on the page. Multiply tints what is under it
/// and keeps dark writing dark, like a real marker; plain is a see-through
/// colour, for dark pictures where multiply would vanish.
enum HighlightStyle {
  none,
  multiply,
  plain;

  static HighlightStyle byName(Object? n) =>
      values.firstWhere((h) => h.name == n, orElse: () => none);
}

class ShapeObject extends BoxObject {
  ShapeObject({
    required super.id,
    required super.name,
    required this.ellipse,
    required super.center,
    required super.size,
    this.stroke = 0xFFE53935,
    this.fill = 0,
    this.strokeWidth = 4,
    this.highlight = HighlightStyle.none,
    super.rotation,
    super.opacity,
    super.visible,
    super.locked,
  });

  final bool ellipse;
  int stroke;

  /// The outline is drawn centred on the edge, so it sticks out by half.
  @override
  Rect get bounds => super.bounds.inflate(strokeWidth / 2);

  /// 0 means unfilled.
  int fill;
  double strokeWidth;

  /// A box made with the highlighter.
  HighlightStyle highlight;

  @override
  ObjectKind get kind => ellipse ? ObjectKind.ellipse : ObjectKind.rect;

  @override
  bool hitTest(Offset p, double tolerance, AssetStore assets) {
    final l = toLocal(p);
    final hw = size.width / 2 + tolerance + strokeWidth / 2;
    final hh = size.height / 2 + tolerance + strokeWidth / 2;
    if (l.dx.abs() > hw || l.dy.abs() > hh) return false;
    if (ellipse) {
      final x = l.dx / hw, y = l.dy / hh;
      if (x * x + y * y > 1) return false; // outside the outer ellipse
    }
    if (fill != 0) return true;
    // Unfilled: only the outline is grabbable, so shapes drawn around other
    // things don't swallow clicks meant for what's inside.
    final band = tolerance + strokeWidth / 2;
    final iw = size.width / 2 - band, ih = size.height / 2 - band;
    if (iw <= 0 || ih <= 0) return true;
    if (ellipse) {
      final x = l.dx / iw, y = l.dy / ih;
      return x * x + y * y >= 1;
    }
    return l.dx.abs() >= iw || l.dy.abs() >= ih;
  }

  @override
  ShapeObject copyWith({String? id, String? name}) => ShapeObject(
    id: id ?? this.id,
    name: name ?? this.name,
    ellipse: ellipse,
    center: center,
    size: size,
    stroke: stroke,
    fill: fill,
    strokeWidth: strokeWidth,
    highlight: highlight,
    rotation: rotation,
    opacity: opacity,
    visible: visible,
    locked: locked,
  );

  @override
  Map<String, dynamic> toJson() => {
    ...boxJson(ellipse ? 'ellipse' : 'rect'),
    'stroke': stroke,
    'fill': fill,
    'strokeWidth': strokeWidth,
    if (highlight != HighlightStyle.none) 'highlight': highlight.name,
  };

  factory ShapeObject.fromJson(Map<String, dynamic> j) {
    final o = ShapeObject(
      id: j['id'],
      name: j['name'],
      ellipse: j['type'] == 'ellipse',
      center: Offset.zero,
      size: Size.zero,
      stroke: j['stroke'],
      fill: j['fill'] ?? 0,
      strokeWidth: (j['strokeWidth'] as num).toDouble(),
      highlight: HighlightStyle.byName(j['highlight']),
      opacity: ((j['opacity'] ?? 1) as num).toDouble(),
      visible: j['visible'] ?? true,
      locked: j['locked'] ?? false,
    );
    o.readBox(j);
    return o;
  }
}

/// A numbered circle for pointing out steps: "1", "2", "3"…
class BadgeObject extends BoxObject {
  BadgeObject({
    required super.id,
    required super.name,
    required this.number,
    required super.center,
    required super.size,
    this.color = 0xFFE53935,
    super.rotation,
    super.opacity,
    super.visible,
    super.locked,
  });

  int number;
  int color;

  @override
  ObjectKind get kind => ObjectKind.badge;

  @override
  bool hitTest(Offset p, double tolerance, AssetStore assets) {
    final l = toLocal(p);
    final rx = size.width / 2 + tolerance, ry = size.height / 2 + tolerance;
    final x = l.dx / rx, y = l.dy / ry;
    return x * x + y * y <= 1;
  }

  @override
  BadgeObject copyWith({String? id, String? name}) => BadgeObject(
    id: id ?? this.id,
    name: name ?? this.name,
    number: number,
    center: center,
    size: size,
    color: color,
    rotation: rotation,
    opacity: opacity,
    visible: visible,
    locked: locked,
  );

  @override
  Map<String, dynamic> toJson() => {
    ...boxJson('badge'),
    'number': number,
    'color': color,
  };

  factory BadgeObject.fromJson(Map<String, dynamic> j) {
    final o = BadgeObject(
      id: j['id'],
      name: j['name'],
      number: j['number'],
      center: Offset.zero,
      size: Size.zero,
      color: j['color'],
      opacity: ((j['opacity'] ?? 1) as num).toDouble(),
      visible: j['visible'] ?? true,
      locked: j['locked'] ?? false,
    );
    o.readBox(j);
    return o;
  }
}

/// A box that hides what is under it: pixelated, or covered with a solid
/// colour. It stays editable; the pixels underneath are only lost on export.
class HideObject extends BoxObject {
  HideObject({
    required super.id,
    required super.name,
    required super.center,
    required super.size,
    this.solid = false,
    this.color = 0xFF222222,
    this.block = 14,
    super.rotation,
    super.opacity,
    super.visible,
    super.locked,
  });

  /// Covered with [color] instead of pixelated.
  bool solid;
  int color;

  /// How big the mosaic's tiles are, in page pixels.
  double block;

  @override
  ObjectKind get kind => ObjectKind.hide;

  @override
  HideObject copyWith({String? id, String? name}) => HideObject(
    id: id ?? this.id,
    name: name ?? this.name,
    center: center,
    size: size,
    solid: solid,
    color: color,
    block: block,
    rotation: rotation,
    opacity: opacity,
    visible: visible,
    locked: locked,
  );

  @override
  Map<String, dynamic> toJson() => {
    ...boxJson('hide'),
    'solid': solid,
    'color': color,
    'block': block,
  };

  factory HideObject.fromJson(Map<String, dynamic> j) {
    final o = HideObject(
      id: j['id'],
      name: j['name'],
      center: Offset.zero,
      size: Size.zero,
      solid: j['solid'] ?? false,
      color: j['color'] ?? 0xFF222222,
      block: ((j['block'] ?? 14) as num).toDouble(),
      opacity: ((j['opacity'] ?? 1) as num).toDouble(),
      visible: j['visible'] ?? true,
      locked: j['locked'] ?? false,
    );
    o.readBox(j);
    return o;
  }
}

/// What one end of a line is attached to: [to] is the object's id. With [at]
/// the end is pinned to that spot of a picture, in the picture's own frame as
/// fractions of its size, measured before flipping (so the pin flips with
/// it). Without it the end rides the object's outline.
class Attachment {
  const Attachment(this.to, [this.at]);
  final String to;
  final Offset? at;

  bool get pinned => at != null;

  Map<String, dynamic> toJson() => {
    'to': to,
    if (at != null) 'at': _offJson(at!),
  };

  /// A damaged note leaves a free end rather than a file that won't open.
  static Attachment? tryRead(Object? j) {
    try {
      if (j is! Map || j['to'] is! String) return null;
      final at = j['at'] == null ? null : _off(j['at']);
      if (at != null && !(at.dx.isFinite && at.dy.isFinite)) return null;
      return Attachment(j['to'] as String, at);
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Attachment && other.to == to && other.at == at;

  @override
  int get hashCode => Object.hash(to, at);
}

/// A line or arrow between two points. Dragging the ends resizes it; dragging
/// its middle bends it into a curve.
class LineObject extends SceneObject {
  LineObject({
    required super.id,
    required super.name,
    required this.p1,
    required this.p2,
    this.color = 0xFFE53935,
    this.width = 5,
    this.headEnd = false,
    this.headStart = false,
    this.dashed = false,
    this.bend = Offset.zero,
    this.start,
    this.end,
    this.anchorBend,
    super.opacity,
    super.visible,
    super.locked,
  });

  Offset p1, p2;

  /// What each end is attached to, if anything. [p1] and [p2] are always the
  /// real ends, kept up to date by `relinkConnectors`; these only say where
  /// they come from.
  Attachment? start, end;

  /// For a curved line with an end riding an outline: its bend measured over
  /// the line between the ends' anchors (the pins, or the centres of what the
  /// ends ride), which is what keeps its shape as those move. [bend] is
  /// worked out from it.
  Offset? anchorBend;

  bool get attached => start != null || end != null;

  /// An end rides an outline: the line connects things, rather than being a
  /// mark on a picture.
  bool get connects =>
      (start != null && !start!.pinned) || (end != null && !end!.pinned);
  int color;
  double width;
  bool headEnd, headStart, dashed;

  /// Where the middle of the curve sits, measured in the line's own frame:
  /// along the line in [dx] and across it in [dy], both as a fraction of the
  /// line's length. Zero is straight. Kept relative so the curve keeps its
  /// shape when an end is dragged or the line is moved.
  Offset bend;

  @override
  ObjectKind get kind => ObjectKind.line;

  double get headSize => math.max(14, width * 3.6);
  double get length => (p2 - p1).distance;
  bool get curved => bend != Offset.zero;

  /// The point halfway along the curve (the bend handle).
  Offset get mid {
    final d = p2 - p1;
    return (p1 + p2) / 2 + d * bend.dx + Offset(-d.dy, d.dx) * bend.dy;
  }

  set mid(Offset m) {
    final d = p2 - p1;
    final len2 = d.dx * d.dx + d.dy * d.dy;
    if (len2 == 0) {
      bend = Offset.zero;
      return;
    }
    final v = m - (p1 + p2) / 2;
    bend = Offset(
      (v.dx * d.dx + v.dy * d.dy) / len2,
      (v.dy * d.dx - v.dx * d.dy) / len2,
    );
  }

  /// The quadratic curve's control point: the curve passes through [mid].
  Offset get control => mid * 2 - (p1 + p2) / 2;

  Offset pointAt(double t) {
    final c = control, u = 1 - t;
    return p1 * (u * u) + c * (2 * u * t) + p2 * (t * t);
  }

  /// The curve as short straight pieces, for hit testing and bounds.
  List<Offset> get samples =>
      curved ? [for (int i = 0; i <= 32; i++) pointAt(i / 32)] : [p1, p2];

  @override
  Rect get bounds => rectFromPoints(
    samples,
  ).inflate(width / 2 + ((headEnd || headStart) ? headSize / 2 : 0));

  @override
  bool hitTest(Offset p, double tolerance, AssetStore assets) {
    final pts = samples;
    for (int i = 1; i < pts.length; i++) {
      if (distToSegment(p, pts[i - 1], pts[i]) <= tolerance + width / 2) {
        return true;
      }
    }
    return false;
  }

  @override
  void translate(Offset d) {
    p1 += d;
    p2 += d;
  }

  @override
  LineObject copyWith({String? id, String? name}) => LineObject(
    id: id ?? this.id,
    name: name ?? this.name,
    p1: p1,
    p2: p2,
    color: color,
    width: width,
    headEnd: headEnd,
    headStart: headStart,
    dashed: dashed,
    bend: bend,
    start: start,
    end: end,
    anchorBend: anchorBend,
    opacity: opacity,
    visible: visible,
    locked: locked,
  );

  @override
  Map<String, dynamic> toJson() => {
    ...baseJson('line'),
    'p1': _offJson(p1),
    'p2': _offJson(p2),
    'color': color,
    'width': width,
    'headEnd': headEnd,
    'headStart': headStart,
    'dashed': dashed,
    if (curved) 'bend': _offJson(bend),
    if (start != null) 'start': start!.toJson(),
    if (end != null) 'end': end!.toJson(),
    if (anchorBend != null) 'anchorBend': _offJson(anchorBend!),
  };

  factory LineObject.fromJson(Map<String, dynamic> j) => LineObject(
    id: j['id'],
    name: j['name'],
    p1: _off(j['p1']),
    p2: _off(j['p2']),
    color: j['color'],
    width: (j['width'] as num).toDouble(),
    headEnd: j['headEnd'] ?? false,
    headStart: j['headStart'] ?? false,
    dashed: j['dashed'] ?? false,
    bend: j['bend'] == null ? Offset.zero : _off(j['bend']),
    start: Attachment.tryRead(j['start']),
    end: Attachment.tryRead(j['end']),
    anchorBend: _tryOff(j['anchorBend']),
    opacity: ((j['opacity'] ?? 1) as num).toDouble(),
    visible: j['visible'] ?? true,
    locked: j['locked'] ?? false,
  );
}

/// A freehand mark. Points are page coordinates.
class StrokeObject extends SceneObject {
  StrokeObject({
    required super.id,
    required super.name,
    required this.points,
    this.color = 0xFFE53935,
    this.width = 5,
    this.highlight = HighlightStyle.none,
    super.opacity,
    super.visible,
    super.locked,
  });

  List<Offset> points;
  int color;
  double width;

  /// A mark made with the highlighter (flat ends, and see-through).
  HighlightStyle highlight;

  @override
  ObjectKind get kind => ObjectKind.stroke;

  @override
  Rect get bounds => rectFromPoints(points).inflate(width / 2);

  @override
  bool hitTest(Offset p, double tolerance, AssetStore assets) {
    if (points.length == 1) {
      return (p - points.first).distance <= tolerance + width / 2;
    }
    for (int i = 0; i < points.length - 1; i++) {
      if (distToSegment(p, points[i], points[i + 1]) <= tolerance + width / 2) {
        return true;
      }
    }
    return false;
  }

  @override
  void translate(Offset d) => points = [for (final p in points) p + d];

  @override
  StrokeObject copyWith({String? id, String? name}) => StrokeObject(
    id: id ?? this.id,
    name: name ?? this.name,
    points: List.of(points),
    color: color,
    width: width,
    highlight: highlight,
    opacity: opacity,
    visible: visible,
    locked: locked,
  );

  @override
  Map<String, dynamic> toJson() => {
    ...baseJson('stroke'),
    'points': [for (final p in points) _offJson(p)],
    'color': color,
    'width': width,
    if (highlight != HighlightStyle.none) 'highlight': highlight.name,
  };

  factory StrokeObject.fromJson(Map<String, dynamic> j) => StrokeObject(
    id: j['id'],
    name: j['name'],
    points: [for (final p in j['points']) _off(p)],
    color: j['color'],
    width: (j['width'] as num).toDouble(),
    highlight: HighlightStyle.byName(j['highlight']),
    opacity: ((j['opacity'] ?? 1) as num).toDouble(),
    visible: j['visible'] ?? true,
    locked: j['locked'] ?? false,
  );
}

/// A named, ordered group of objects. Objects are listed bottom to top.
class Layer {
  Layer({
    required this.id,
    required this.name,
    this.visible = true,
    this.locked = false,
    List<SceneObject>? objects,
  }) : objects = objects ?? [];

  final String id;
  String name;
  bool visible;
  bool locked;
  final List<SceneObject> objects;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'visible': visible,
    'locked': locked,
    'objects': [for (final o in objects) o.toJson()],
  };

  factory Layer.fromJson(Map<String, dynamic> j) => Layer(
    id: j['id'],
    name: j['name'],
    visible: j['visible'] ?? true,
    locked: j['locked'] ?? false,
    objects: [
      for (final o in j['objects'])
        SceneObject.fromJson(Map<String, dynamic>.from(o)),
    ],
  );
}

/// A source image kept around for repeated use. Distinct from the objects
/// that get placed on the page.
class CollectionItem {
  CollectionItem({required this.id, required this.name, required this.assetId});
  final String id;
  String name;
  final String assetId;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'asset': assetId};
  factory CollectionItem.fromJson(Map<String, dynamic> j) =>
      CollectionItem(id: j['id'], name: j['name'], assetId: j['asset']);
}

const int kDefaultBackground = 0xFFFFFFFF;

class Document {
  Document({
    this.canvasSize = const Size(1600, 1000),
    this.background = kDefaultBackground,
    this.gridSize = 40,
    List<Layer>? layers,
    List<CollectionItem>? collection,
    this.nextId = 1,
  }) : layers = layers ?? [],
       collection = collection ?? [];

  Size canvasSize;

  /// 0 means a transparent page.
  int background;
  double gridSize;
  final List<Layer> layers;
  final List<CollectionItem> collection;
  int nextId;

  String newId(String prefix) => '$prefix${nextId++}';

  Layer? layerById(String id) {
    for (final l in layers) {
      if (l.id == id) return l;
    }
    return null;
  }

  Layer? layerOf(String objectId) {
    for (final l in layers) {
      if (l.objects.any((o) => o.id == objectId)) return l;
    }
    return null;
  }

  SceneObject? objectById(String id) {
    for (final l in layers) {
      for (final o in l.objects) {
        if (o.id == id) return o;
      }
    }
    return null;
  }

  Iterable<SceneObject> get allObjects sync* {
    for (final l in layers) {
      yield* l.objects;
    }
  }

  Set<String> get usedAssets => {
    for (final o in allObjects)
      if (o is ImageObject) ...[
        o.assetId,
        if (o.canUnmerge) ...o.merged!.assets,
      ],
    for (final c in collection) c.assetId,
  };

  Map<String, dynamic> toJson() => {
    'canvas': [canvasSize.width, canvasSize.height],
    'background': background,
    'gridSize': gridSize,
    'nextId': nextId,
    'layers': [for (final l in layers) l.toJson()],
    'collection': [for (final c in collection) c.toJson()],
  };

  String encode() => jsonEncode(toJson());

  /// Everything the user can see or change, but not the id counter, so an
  /// abandoned gesture that burned an id doesn't count as an edit.
  String signature() {
    final j = toJson()..remove('nextId');
    return jsonEncode(j);
  }

  factory Document.fromJson(Map<String, dynamic> j) => Document(
    canvasSize: Size(
      (j['canvas'][0] as num).toDouble(),
      (j['canvas'][1] as num).toDouble(),
    ),
    background: j['background'] ?? kDefaultBackground,
    gridSize: (j['gridSize'] as num?)?.toDouble() ?? 40,
    nextId: j['nextId'] ?? 1,
    layers: [
      for (final l in j['layers']) Layer.fromJson(Map<String, dynamic>.from(l)),
    ],
    collection: [
      for (final c in j['collection'] ?? const [])
        CollectionItem.fromJson(Map<String, dynamic>.from(c)),
    ],
  );

  factory Document.decode(String s) =>
      Document.fromJson(jsonDecode(s) as Map<String, dynamic>);

  /// A fresh page with one empty layer.
  factory Document.blank() {
    final d = Document();
    d.layers.add(Layer(id: d.newId('l'), name: 'Layer 1'));
    return d;
  }
}

/// A whole number from a JSON value that may be an int, a decimal or text.
int? _asInt(Object? v) => v is num ? v.toInt() : int.tryParse('$v');
