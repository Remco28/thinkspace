import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../editor/controller.dart';
import '../editor/interactor.dart';
import '../io/samples.dart';
import '../model/scene.dart';

/// A localhost-only HTTP door for developers and agents, enabled by setting
/// THINKSPACE_DEBUG_PORT. It answers "what does the screen look like" and
/// "what does the app think is happening" without guessing from pixels.
///
///   GET  /state        document, selection, layers, history as JSON
///   GET  /screenshot   PNG of the whole app window
///   GET  /export       PNG of the page itself
///   POST /do           {"cmd": ..., ...}  drive the app (see _run)
class Inspector {
  Inspector({required this.c, required this.ix, required this.shotKey, required this.port});
  final EditorController c;
  final CanvasInteractor ix;
  final GlobalKey shotKey;
  final int port;
  HttpServer? _server;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    stderr.writeln('Thinkspace inspector listening on http://127.0.0.1:$port');
    _server!.listen(_handle);
  }

  Future<void> stop() async => _server?.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    try {
      switch (req.uri.path) {
        case '/state':
          await _json(req, c.stateJson());
        case '/screenshot':
          await WidgetsBinding.instance.endOfFrame;
          final b = shotKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final img = await b.toImage(pixelRatio: 1);
          final data = await img.toByteData(format: ui.ImageByteFormat.png);
          await _bytes(req, data!.buffer.asUint8List());
        case '/export':
          final scale = double.tryParse(req.uri.queryParameters['scale'] ?? '') ?? 1;
          await _bytes(req, await c.exportPng(scale: scale));
        case '/do':
          final body = req.method == 'POST'
              ? jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>
              : Map<String, dynamic>.from(jsonDecode(req.uri.queryParameters['json'] ?? '{}') as Map);
          final result = await _run(body);
          await WidgetsBinding.instance.endOfFrame;
          await _json(req, {'ok': true, 'result': result, 'selection': c.selection, 'tool': c.tool.name, 'history': {'undo': c.undoDepth, 'redo': c.redoDepth}});
        default:
          req.response.statusCode = 404;
          await req.response.close();
      }
    } catch (e, st) {
      req.response.statusCode = 500;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({'ok': false, 'error': '$e', 'stack': '$st'.split('\n').take(6).toList()}));
      await req.response.close();
    }
  }

  Future<void> _json(HttpRequest req, Object o) async {
    req.response.headers.contentType = ContentType.json;
    req.response.write(const JsonEncoder.withIndent('  ').convert(o));
    await req.response.close();
  }

  Future<void> _bytes(HttpRequest req, Uint8List b) async {
    req.response.headers.contentType = ContentType('image', 'png');
    req.response.add(b);
    await req.response.close();
  }

  Offset _pt(dynamic v, Map<String, dynamic> cmd) {
    final p = Offset((v[0] as num).toDouble(), (v[1] as num).toDouble());
    return (cmd['space'] == 'screen') ? p : c.toScreen(p);
  }

  Modifiers _mods(Map<String, dynamic> cmd) =>
      Modifiers(shift: cmd['shift'] == true, ctrl: cmd['ctrl'] == true, alt: cmd['alt'] == true);

  SceneObject? _find(Map<String, dynamic> cmd) {
    final id = cmd['id'] as String?;
    final name = cmd['name'] as String?;
    for (final o in c.doc.allObjects) {
      if (o.id == id || (name != null && o.name == name)) return o;
    }
    return null;
  }

  Future<Object?> _run(Map<String, dynamic> cmd) async {
    switch (cmd['cmd']) {
      case 'sample':
        await loadStorefrontSample(c);
      case 'new':
        c.newDocument();
      case 'tool':
        c.setTool(Tool.values.byName(cmd['tool'] as String));
      case 'cutoutMode':
        c.cutoutMode = CutoutMode.values.byName(cmd['mode'] as String);
        c.notify();
      case 'select':
        final names = [for (final n in (cmd['names'] ?? const []) as List) n as String];
        final ids = [for (final i in (cmd['ids'] ?? const []) as List) i as String];
        for (final o in c.doc.allObjects) {
          if (names.contains(o.name)) ids.add(o.id);
        }
        c.select(ids);
      case 'click':
        final p = _pt(cmd['at'], cmd);
        ix.pointerDown(p, _mods(cmd));
        ix.pointerUp(p, _mods(cmd));
        await Future<void>.delayed(const Duration(milliseconds: 60));
      case 'drag':
        final a = _pt(cmd['from'], cmd), b = _pt(cmd['to'], cmd);
        final steps = (cmd['steps'] as int?) ?? 8;
        final m = _mods(cmd);
        ix.pointerDown(a, m);
        for (int i = 1; i <= steps; i++) {
          ix.pointerMove(Offset.lerp(a, b, i / steps)!, m);
        }
        ix.pointerUp(b, m);
        await Future<void>.delayed(const Duration(milliseconds: 150));
      case 'path':
        // A freehand gesture through several points.
        final pts = [for (final p in cmd['points'] as List) _pt(p, cmd)];
        final m = _mods(cmd);
        ix.pointerDown(pts.first, m);
        for (final p in pts.skip(1)) {
          ix.pointerMove(p, m);
        }
        ix.pointerUp(pts.last, m);
        await Future<void>.delayed(const Duration(milliseconds: 250));
      case 'undo':
        c.undo();
      case 'redo':
        c.redo();
      case 'delete':
        c.deleteSelection();
      case 'duplicate':
        c.duplicateSelection();
      case 'paste':
        await c.paste();
      case 'resolvePaste':
        c.resolvePaste(toCollection: cmd['collection'] == true);
      case 'opacity':
        final o = _find(cmd);
        if (o != null) {
          c.select([o.id]);
          c.editSelected('opacity', (x) => x.opacity = (cmd['value'] as num).toDouble());
        }
      case 'rotation':
        final o = _find(cmd);
        if (o != null) {
          c.select([o.id]);
          c.editSelected('rotate', (x) => (x as BoxObject).rotation = (cmd['degrees'] as num).toDouble() * math.pi / 180);
        }
      case 'layerVisible':
        final l = c.doc.layers.firstWhere((l) => l.id == cmd['layer'] || l.name == cmd['layer']);
        c.setLayerVisible(l.id, cmd['visible'] == true);
      case 'moveToLayer':
        final l = c.doc.layers.firstWhere((l) => l.id == cmd['layer'] || l.name == cmd['layer']);
        final ids = [for (final o in c.doc.allObjects) if (cmd['names'].contains(o.name)) o.id];
        c.moveObjectsToLayer(ids, l.id);
      case 'addLayer':
        c.addLayer();
      case 'selectLayer':
        final l = c.doc.layers.firstWhere((l) => l.id == cmd['layer'] || l.name == cmd['layer']);
        c.selectLayerContents(l.id);
      case 'grid':
        c.showGrid = cmd['show'] != false;
        c.snapOn = cmd['snap'] == true;
        c.notify();
      case 'zoom':
        if (cmd['fit'] == true) {
          c.fitToView();
        } else {
          c.zoomTo((cmd['value'] as num).toDouble());
        }
      case 'canvasSize':
        c.setCanvasSize(Size((cmd['w'] as num).toDouble(), (cmd['h'] as num).toDouble()));
      case 'removeBackground':
        final o = _find(cmd);
        if (o is ImageObject) await c.removeBackgroundFrom(o);
      case 'save':
        await c.saveTo(cmd['path'] as String);
      case 'open':
        await c.openFrom(cmd['path'] as String);
      case 'exportPng':
        await File(cmd['path'] as String).writeAsBytes(await c.exportPng(scale: (cmd['scale'] as num?)?.toDouble() ?? 1));
      case 'importFile':
        await c.importFiles([cmd['path'] as String], toCollection: cmd['collection'] == true);
      case 'editText':
        final o = _find(cmd);
        if (o is TextObject) {
          c.beginTextEdit(o.id);
          c.updateEditingText(cmd['text'] as String);
          c.finishTextEdit();
        }
      default:
        throw ArgumentError('unknown cmd ${cmd['cmd']}');
    }
    return null;
  }
}
