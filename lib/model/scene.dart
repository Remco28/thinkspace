import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'assets.dart';
import 'geometry.dart';

enum ObjectKind { image, text, rect, ellipse, line, stroke }

Offset _off(dynamic j) => Offset((j[0] as num).toDouble(), (j[1] as num).toDouble());
List<double> _offJson(Offset o) => [o.dx, o.dy];

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
    size = Size((j['size'][0] as num).toDouble(), (j['size'][1] as num).toDouble());
    rotation = (j['rotation'] as num?)?.toDouble() ?? 0;
    flipX = j['flipX'] as bool? ?? false;
  }
}

class ImageObject extends BoxObject {
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
  });

  String assetId;

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
    final r = math.max(1, (tolerance * a.width / math.max(1, size.width)).ceil());
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
      );

  @override
  Map<String, dynamic> toJson() => {...boxJson('image'), 'asset': assetId};

  factory ImageObject.fromJson(Map<String, dynamic> j) {
    final o = ImageObject(
      id: j['id'],
      name: j['name'],
      assetId: j['asset'],
      center: Offset.zero,
      size: Size.zero,
      opacity: (j['opacity'] as num).toDouble(),
      visible: j['visible'] ?? true,
      locked: j['locked'] ?? false,
    );
    o.readBox(j);
    return o;
  }
}

class TextObject extends BoxObject {
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
        background: background,
        align: align,
        rotation: rotation,
        opacity: opacity,
        visible: visible,
        locked: locked,
      );

  @override
  Map<String, dynamic> toJson() => {
        ...boxJson('text'),
        'text': text,
        'fontSize': fontSize,
        'color': color,
        'bold': bold,
        'italic': italic,
        'background': background,
        'align': align.index,
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
      background: j['background'] ?? 0,
      align: TextAlign.values[j['align'] ?? 0],
      opacity: (j['opacity'] as num).toDouble(),
      visible: j['visible'] ?? true,
      locked: j['locked'] ?? false,
    );
    o.readBox(j);
    return o;
  }
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
    super.rotation,
    super.opacity,
    super.visible,
    super.locked,
  });

  final bool ellipse;
  int stroke;

  /// 0 means unfilled.
  int fill;
  double strokeWidth;

  @override
  ObjectKind get kind => ellipse ? ObjectKind.ellipse : ObjectKind.rect;

  @override
  bool hitTest(Offset p, double tolerance, AssetStore assets) {
    final l = toLocal(p);
    final hw = size.width / 2 + tolerance + strokeWidth / 2;
    final hh = size.height / 2 + tolerance + strokeWidth / 2;
    if (l.dx.abs() > hw || l.dy.abs() > hh) return false;
    if (fill != 0) {
      if (!ellipse) return true;
      final x = l.dx / hw, y = l.dy / hh;
      return x * x + y * y <= 1;
    }
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
      opacity: (j['opacity'] as num).toDouble(),
      visible: j['visible'] ?? true,
      locked: j['locked'] ?? false,
    );
    o.readBox(j);
    return o;
  }
}

/// A straight line or arrow between two points. Dragging the ends resizes it.
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
    super.opacity,
    super.visible,
    super.locked,
  });

  Offset p1, p2;
  int color;
  double width;
  bool headEnd, headStart, dashed;

  @override
  ObjectKind get kind => ObjectKind.line;

  double get headSize => math.max(14, width * 3.6);
  double get length => (p2 - p1).distance;

  @override
  Rect get bounds => rectFromPoints([p1, p2]).inflate(width / 2 + ((headEnd || headStart) ? headSize / 2 : 0));

  @override
  bool hitTest(Offset p, double tolerance, AssetStore assets) =>
      distToSegment(p, p1, p2) <= tolerance + width / 2;

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
        opacity: (j['opacity'] as num).toDouble(),
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
    super.opacity,
    super.visible,
    super.locked,
  });

  List<Offset> points;
  int color;
  double width;

  @override
  ObjectKind get kind => ObjectKind.stroke;

  @override
  Rect get bounds => rectFromPoints(points).inflate(width / 2);

  @override
  bool hitTest(Offset p, double tolerance, AssetStore assets) {
    if (points.length == 1) return (p - points.first).distance <= tolerance + width / 2;
    for (int i = 0; i < points.length - 1; i++) {
      if (distToSegment(p, points[i], points[i + 1]) <= tolerance + width / 2) return true;
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
      };

  factory StrokeObject.fromJson(Map<String, dynamic> j) => StrokeObject(
        id: j['id'],
        name: j['name'],
        points: [for (final p in j['points']) _off(p)],
        color: j['color'],
        width: (j['width'] as num).toDouble(),
        opacity: (j['opacity'] as num).toDouble(),
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
          for (final o in j['objects']) SceneObject.fromJson(Map<String, dynamic>.from(o)),
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
  })  : layers = layers ?? [],
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
          if (o is ImageObject) o.assetId,
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
        canvasSize: Size((j['canvas'][0] as num).toDouble(), (j['canvas'][1] as num).toDouble()),
        background: j['background'] ?? kDefaultBackground,
        gridSize: (j['gridSize'] as num?)?.toDouble() ?? 40,
        nextId: j['nextId'] ?? 1,
        layers: [for (final l in j['layers']) Layer.fromJson(Map<String, dynamic>.from(l))],
        collection: [
          for (final c in j['collection'] ?? const [])
            CollectionItem.fromJson(Map<String, dynamic>.from(c)),
        ],
      );

  factory Document.decode(String s) => Document.fromJson(jsonDecode(s) as Map<String, dynamic>);

  /// A fresh page with one empty layer.
  factory Document.blank() {
    final d = Document();
    d.layers.add(Layer(id: d.newId('l'), name: 'Layer 1'));
    return d;
  }
}
