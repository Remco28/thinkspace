import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../editor/controller.dart';
import '../model/scene.dart';
import 'widgets.dart';

class PropertiesPanel extends StatelessWidget {
  const PropertiesPanel({super.key, required this.controller});
  final EditorController controller;
  EditorController get c => controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final objs = c.selectedObjects;
        final title = objs.isEmpty ? (c.tool == Tool.select ? 'Page' : 'New ${c.tool.name}') : (objs.length == 1 ? _kindLabel(objs.first) : '${objs.length} selected');
        return Column(children: [
          PanelHeader(title),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              child: objs.isEmpty ? _page(context) : _selection(context, objs),
            ),
          ),
        ]);
      },
    );
  }

  String _kindLabel(SceneObject o) => switch (o.kind) {
        ObjectKind.image => 'Image',
        ObjectKind.text => 'Text',
        ObjectKind.rect => 'Rectangle',
        ObjectKind.ellipse => 'Ellipse',
        ObjectKind.line => o is LineObject && o.headEnd ? 'Arrow' : 'Line',
        ObjectKind.stroke => 'Pen stroke',
      };

  // ---- nothing selected ---------------------------------------------------

  Widget _page(BuildContext context) {
    final drawing = c.tool != Tool.select && c.tool != Tool.cutout;
    final d = c.doc;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (drawing) ...[
        if (c.tool != Tool.text) ...[
          LabeledRow('Colour', ColorRow(value: c.penColor, onChanged: (v) {
            c.penColor = v;
            c.notify();
          })),
          LabeledRow('Width', _plainSlider(c.penWidth, 1, 30, (v) {
            c.penWidth = v.roundToDouble();
            c.notify();
          })),
          if (c.tool == Tool.rect || c.tool == Tool.ellipse)
            LabeledRow('Fill', ColorRow(allowNone: true, value: c.fillColor, onChanged: (v) {
              c.fillColor = v;
              c.notify();
            })),
        ] else ...[
          LabeledRow('Colour', ColorRow(value: c.textColor, onChanged: (v) {
            c.textColor = v;
            c.notify();
          })),
          LabeledRow('Size', _plainSlider(c.textSize, 8, 160, (v) {
            c.textSize = v.roundToDouble();
            c.notify();
          })),
        ],
        const Divider(height: 24),
      ],
      const _Caption('Canvas size'),
      Row(children: [
        NumberField(key: const ValueKey('canvas-w'), value: d.canvasSize.width, suffix: ' w', onSubmitted: (v) => c.setCanvasSize(Size(v, d.canvasSize.height))),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('×')),
        NumberField(key: const ValueKey('canvas-h'), value: d.canvasSize.height, suffix: ' h', onSubmitted: (v) => c.setCanvasSize(Size(d.canvasSize.width, v))),
      ]),
      const SizedBox(height: 6),
      const Text('Drag the grips on the page edge to resize it. Resizing never touches the objects on it.',
          style: TextStyle(fontSize: 11.5, color: Color(0xFF6B7385), height: 1.35)),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        OutlinedButton(onPressed: c.fitCanvasToContent, child: const Text('Fit page to content')),
      ]),
      InkWell(
        onTap: () {
          c.autoGrow = !c.autoGrow;
          c.notify();
        },
        child: Row(children: [
          Checkbox(
            value: c.autoGrow,
            visualDensity: VisualDensity.compact,
            onChanged: (v) {
              c.autoGrow = v ?? false;
              c.notify();
            },
          ),
          const Expanded(child: Text('Grow the page as I add things', style: TextStyle(fontSize: 12.5))),
        ]),
      ),
      const Divider(height: 20),
      const _Caption('Page colour'),
      ColorRow(allowNone: true, value: d.background, onChanged: c.setBackground),
      const SizedBox(height: 10),
      const _Caption('Grid'),
      Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        const Text('Spacing', style: TextStyle(fontSize: 12)),
        NumberField(key: const ValueKey('grid-size'), value: d.gridSize, width: 60, onSubmitted: (v) => c.setGridSize(v)),
        FilterChip(
          label: const Text('Show'),
          selected: c.showGrid,
          onSelected: (_) => c.toggleGrid(),
          visualDensity: VisualDensity.compact,
        ),
        FilterChip(
          label: const Text('Snap'),
          selected: c.snapOn,
          onSelected: (_) => c.toggleSnap(),
          visualDensity: VisualDensity.compact,
        ),
      ]),
      const SizedBox(height: 4),
      const Text('Hold Ctrl while dragging to ignore snapping.', style: TextStyle(fontSize: 11.5, color: Color(0xFF6B7385))),
    ]);
  }

  Widget _plainSlider(double v, double min, double max, ValueChanged<double> onChanged) => SliderTheme(
        data: const SliderThemeData(trackHeight: 3, thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7), overlayShape: RoundSliderOverlayShape(overlayRadius: 0)),
        child: Slider(value: v.clamp(min, max), min: min, max: max, onChanged: onChanged),
      );

  // ---- selection ----------------------------------------------------------

  Widget _selection(BuildContext context, List<SceneObject> objs) {
    final one = objs.length == 1 ? objs.first : null;
    final kinds = objs.map((o) => o.kind).toSet();
    final sameKind = kinds.length == 1;
    final first = objs.first;
    final layerIds = objs.map((o) => c.doc.layerOf(o.id)?.id).toSet();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (one != null)
        LabeledRow(
          'Name',
          SizedBox(
            height: 30,
            child: TextFormField(
              key: ValueKey('name-${one.id}-${one.name}'),
              initialValue: one.name,
              style: const TextStyle(fontSize: 12.5),
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
              onFieldSubmitted: (v) => c.renameObject(one.id, v),
            ),
          ),
        ),
      LabeledRow(
        'Layer',
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            isDense: true,
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF222733)),
            value: layerIds.length == 1 ? layerIds.first : null,
            hint: const Text('Several layers'),
            items: [for (final l in c.doc.layers.reversed) DropdownMenuItem(value: l.id, child: Text(l.name, overflow: TextOverflow.ellipsis))],
            onChanged: (v) {
              if (v != null) c.moveObjectsToLayer(objs.map((o) => o.id).toList(), v);
            },
          ),
        ),
      ),
      LabeledRow(
        'Opacity',
        Row(children: [
          Expanded(
            child: LiveSlider(
              key: const ValueKey('opacity'),
              controller: c,
              value: first.opacity,
              min: 0.05,
              max: 1,
              label: 'opacity',
              apply: (v) => c.liveEditSelected((o) => o.opacity = v),
            ),
          ),
          SizedBox(width: 38, child: Text('${(first.opacity * 100).round()}%', style: const TextStyle(fontSize: 12))),
        ]),
      ),
      if (one is BoxObject) ...[
        LabeledRow(
          'Rotate',
          Row(children: [
            NumberField(
              key: const ValueKey('rotation'),
              value: (one.rotation * 180 / math.pi),
              suffix: '°',
              width: 76,
              onSubmitted: (v) => c.editSelected('rotate', (o) => (o as BoxObject).rotation = v * math.pi / 180),
            ),
            const SizedBox(width: 6),
            SmallIconButton(icon: Icons.rotate_90_degrees_ccw, tooltip: 'Rotate 90° left', onPressed: () => c.editSelected('rotate', (o) => (o as BoxObject).rotation -= math.pi / 2)),
            SmallIconButton(icon: Icons.rotate_90_degrees_cw, tooltip: 'Rotate 90° right', onPressed: () => c.editSelected('rotate', (o) => (o as BoxObject).rotation += math.pi / 2)),
          ]),
        ),
        if (one is! TextObject)
          LabeledRow(
            'Size',
            Row(children: [
              NumberField(key: const ValueKey('size-w'), value: one.size.width, width: 62, onSubmitted: (v) => c.editSelected('resize', (o) => (o as BoxObject).size = Size(math.max(4, v), o.size.height))),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 5), child: Text('×')),
              NumberField(key: const ValueKey('size-h'), value: one.size.height, width: 62, onSubmitted: (v) => c.editSelected('resize', (o) => (o as BoxObject).size = Size(o.size.width, math.max(4, v)))),
            ]),
          ),
      ],
      const SizedBox(height: 4),
      if (sameKind && one != null) _typeControls(context, one) else if (sameKind) _typeControlsMulti(context, objs),
      const Divider(height: 22),
      const _Caption('Arrange'),
      Wrap(spacing: 2, children: [
        SmallIconButton(icon: Icons.flip_to_front, tooltip: 'Bring to front  Ctrl+Shift+]', onPressed: () => c.reorderSelection('front')),
        SmallIconButton(icon: Icons.arrow_upward, tooltip: 'Forward  ]', onPressed: () => c.reorderSelection('forward')),
        SmallIconButton(icon: Icons.arrow_downward, tooltip: 'Backward  [', onPressed: () => c.reorderSelection('backward')),
        SmallIconButton(icon: Icons.flip_to_back, tooltip: 'Send to back  Ctrl+Shift+[', onPressed: () => c.reorderSelection('back')),
        const SizedBox(width: 8),
        SmallIconButton(icon: Icons.copy_all_outlined, tooltip: 'Duplicate  Ctrl+D', onPressed: c.duplicateSelection),
        SmallIconButton(icon: Icons.lock_outline, tooltip: 'Lock so it can’t be grabbed', onPressed: () => c.editSelected('lock', (o) => o.locked = true)),
        SmallIconButton(icon: Icons.delete_outline, tooltip: 'Delete  Del', onPressed: c.deleteSelection, color: const Color(0xFFC62828)),
      ]),
      if (objs.any((o) => o.locked))
        TextButton(onPressed: () => c.editSelected('unlock', (o) => o.locked = false), child: const Text('Unlock')),
    ]);
  }

  Widget _typeControlsMulti(BuildContext context, List<SceneObject> objs) => Column(children: [
        if (objs.first is LineObject || objs.first is StrokeObject || objs.first is ShapeObject)
          LabeledRow('Colour', ColorRow(
            value: _colorOf(objs.first),
            onChanged: (v) => c.editSelected('colour', (o) => _setColor(o, v)),
          )),
      ]);

  int _colorOf(SceneObject o) => o is LineObject ? o.color : o is StrokeObject ? o.color : o is ShapeObject ? o.stroke : 0;

  void _setColor(SceneObject o, int v) {
    if (o is LineObject) o.color = v;
    if (o is StrokeObject) o.color = v;
    if (o is ShapeObject) o.stroke = v;
    c.penColor = v;
  }

  Widget _typeControls(BuildContext context, SceneObject o) {
    if (o is LineObject) {
      return Column(children: [
        LabeledRow('Colour', ColorRow(value: o.color, onChanged: (v) => c.editSelected('colour', (x) => _setColor(x, v)))),
        LabeledRow('Width', LiveSlider(controller: c, value: o.width, min: 1, max: 30, label: 'width', apply: (v) => c.liveEditSelected((x) {
              (x as LineObject).width = v.roundToDouble();
              c.penWidth = v.roundToDouble();
            }))),
        LabeledRow('Ends', Wrap(spacing: 6, children: [
          FilterChip(label: const Text('Arrow at start'), selected: o.headStart, visualDensity: VisualDensity.compact, onSelected: (v) => c.editSelected('arrowhead', (x) => (x as LineObject).headStart = v)),
          FilterChip(label: const Text('Arrow at end'), selected: o.headEnd, visualDensity: VisualDensity.compact, onSelected: (v) => c.editSelected('arrowhead', (x) => (x as LineObject).headEnd = v)),
          FilterChip(label: const Text('Dashed'), selected: o.dashed, visualDensity: VisualDensity.compact, onSelected: (v) => c.editSelected('dashed', (x) => (x as LineObject).dashed = v)),
        ])),
      ]);
    }
    if (o is StrokeObject) {
      return Column(children: [
        LabeledRow('Colour', ColorRow(value: o.color, onChanged: (v) => c.editSelected('colour', (x) => _setColor(x, v)))),
        LabeledRow('Width', LiveSlider(controller: c, value: o.width, min: 1, max: 30, label: 'width', apply: (v) => c.liveEditSelected((x) {
              (x as StrokeObject).width = v.roundToDouble();
            }))),
      ]);
    }
    if (o is ShapeObject) {
      return Column(children: [
        LabeledRow('Outline', ColorRow(value: o.stroke, onChanged: (v) => c.editSelected('colour', (x) => _setColor(x, v)))),
        LabeledRow('Fill', ColorRow(allowNone: true, value: o.fill, onChanged: (v) {
          c.editSelected('fill', (x) => (x as ShapeObject).fill = v);
          c.fillColor = v;
        })),
        LabeledRow('Width', LiveSlider(controller: c, value: o.strokeWidth, min: 0, max: 30, label: 'width', apply: (v) => c.liveEditSelected((x) {
              (x as ShapeObject).strokeWidth = v.roundToDouble();
            }))),
      ]);
    }
    if (o is TextObject) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LabeledRow('Colour', ColorRow(value: o.color, onChanged: (v) {
          c.editSelected('text colour', (x) => (x as TextObject).color = v);
          c.textColor = v;
        })),
        LabeledRow('Size', Row(children: [
          Expanded(child: LiveSlider(controller: c, value: o.fontSize, min: 8, max: 160, label: 'text size', apply: (v) => c.liveEditSelected((x) {
                (x as TextObject).fontSize = v.roundToDouble();
                c.textSize = v.roundToDouble();
              }))),
          SizedBox(width: 30, child: Text('${o.fontSize.round()}', style: const TextStyle(fontSize: 12))),
        ])),
        LabeledRow('Style', Wrap(spacing: 4, children: [
          SmallIconButton(icon: Icons.format_bold, tooltip: 'Bold', active: o.bold, onPressed: () => c.editSelected('bold', (x) => (x as TextObject).bold = !x.bold)),
          SmallIconButton(icon: Icons.format_italic, tooltip: 'Italic', active: o.italic, onPressed: () => c.editSelected('italic', (x) => (x as TextObject).italic = !x.italic)),
          SmallIconButton(icon: Icons.format_align_left, tooltip: 'Align left', active: o.align == TextAlign.left, onPressed: () => c.editSelected('align', (x) => (x as TextObject).align = TextAlign.left)),
          SmallIconButton(icon: Icons.format_align_center, tooltip: 'Center', active: o.align == TextAlign.center, onPressed: () => c.editSelected('align', (x) => (x as TextObject).align = TextAlign.center)),
          SmallIconButton(icon: Icons.format_align_right, tooltip: 'Align right', active: o.align == TextAlign.right, onPressed: () => c.editSelected('align', (x) => (x as TextObject).align = TextAlign.right)),
        ])),
        LabeledRow('Backdrop', ColorRow(allowNone: true, value: o.background, onChanged: (v) => c.editSelected('text backdrop', (x) => (x as TextObject).background = v))),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: OutlinedButton.icon(onPressed: () => c.beginTextEdit(o.id), icon: const Icon(Icons.edit, size: 16), label: const Text('Edit text')),
        ),
      ]);
    }
    if (o is ImageObject) {
      final a = c.assets[o.assetId];
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (a != null) Text('${a.width} × ${a.height} px', style: const TextStyle(fontSize: 11.5, color: Color(0xFF6B7385))),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          OutlinedButton.icon(
            key: const ValueKey('cutout-button'),
            onPressed: () => c.setTool(Tool.cutout),
            icon: const Icon(Icons.content_cut, size: 16),
            label: const Text('Cut out…'),
          ),
          OutlinedButton.icon(
            key: const ValueKey('remove-bg-button'),
            onPressed: () => c.removeBackgroundFrom(o),
            icon: const Icon(Icons.auto_fix_high, size: 16),
            label: const Text('Remove background'),
          ),
          OutlinedButton.icon(
            onPressed: () => c.editSelected('flip', (x) => (x as ImageObject).flipX = !x.flipX),
            icon: const Icon(Icons.flip, size: 16),
            label: const Text('Flip'),
          ),
          if (a != null)
            OutlinedButton(
              onPressed: () => c.editSelected('original size', (x) => (x as ImageObject).size = Size(a.width.toDouble(), a.height.toDouble())),
              child: const Text('Original size'),
            ),
          OutlinedButton.icon(
            onPressed: c.sendSelectionToCollection,
            icon: const Icon(Icons.collections_outlined, size: 16),
            label: const Text('Keep in collection'),
          ),
        ]),
        const SizedBox(height: 6),
        const Text('Background tolerance', style: TextStyle(fontSize: 11.5, color: Color(0xFF6B7385))),
        _plainSlider(c.wandTolerance, 0.02, 0.5, (v) {
          c.wandTolerance = v;
          c.notify();
        }),
      ]);
    }
    return const SizedBox.shrink();
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF5B6272))),
      );
}
