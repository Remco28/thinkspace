import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../editor/canvas_painter.dart' show kAccent;
import '../editor/controller.dart';
import '../model/scene.dart';
import 'kit.dart';
import 'widgets.dart';

/// The settings for whatever is selected, or for the page when nothing is.
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
        final title = objs.isEmpty
            ? (c.tool == Tool.select ? 'Page' : 'New ${_toolLabel(c.tool)}')
            : (objs.length == 1
                  ? _kindLabel(objs.first)
                  : '${objs.length} selected');
        return Column(
          children: [
            PanelHeader(title),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  kPanelPad,
                  12,
                  kPanelPad,
                  20,
                ),
                child: objs.isEmpty
                    ? _page(context)
                    : _selection(context, objs),
              ),
            ),
          ],
        );
      },
    );
  }

  String _toolLabel(Tool t) => switch (t) {
    Tool.badge => 'marker',
    Tool.rect => 'rectangle',
    Tool.pen => 'pen stroke',
    Tool.highlight => 'highlight',
    _ => t.name,
  };

  String _kindLabel(SceneObject o) =>
      ((o is StrokeObject && o.highlight != HighlightStyle.none) ||
          (o is ShapeObject && o.highlight != HighlightStyle.none))
      ? 'Highlight'
      : _kindOf(o);

  String _kindOf(SceneObject o) => switch (o.kind) {
    ObjectKind.image => 'Image',
    ObjectKind.text => 'Text',
    ObjectKind.rect => 'Rectangle',
    ObjectKind.ellipse => 'Ellipse',
    ObjectKind.line => o is LineObject && o.headEnd ? 'Arrow' : 'Line',
    ObjectKind.stroke => 'Pen stroke',
    ObjectKind.badge => 'Marker',
  };

  // ---- nothing selected ---------------------------------------------------

  Widget _page(BuildContext context) {
    final drawing = c.tool != Tool.select && c.tool != Tool.cutout;
    final d = c.doc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (drawing) _toolDefaults(),
        Section(
          first: !drawing,
          title: 'Page size',
          children: [
            Row(
              children: [
                NumberField(
                  key: const ValueKey('canvas-w'),
                  value: d.canvasSize.width,
                  suffix: ' wide',
                  width: 104,
                  onSubmitted: (v) =>
                      c.setCanvasSize(Size(v, d.canvasSize.height)),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('×', style: TextStyle(color: kLabel)),
                ),
                NumberField(
                  key: const ValueKey('canvas-h'),
                  value: d.canvasSize.height,
                  suffix: ' high',
                  width: 104,
                  onSubmitted: (v) =>
                      c.setCanvasSize(Size(d.canvasSize.width, v)),
                ),
              ],
            ),
            ActionButton(
              key: const ValueKey('fit-page'),
              label: 'Fit page to content',
              icon: Icons.crop_free,
              tooltip:
                  'Resize the page to exactly fit everything on it, whether that makes it bigger or smaller',
              onPressed: c.fitCanvasToContent,
            ),
            SwitchRow(
              key: const ValueKey('grow-page'),
              label: 'Grow the page as I add things',
              hint:
                  'The page gets bigger when you place something past its edge.',
              value: c.autoGrow,
              onChanged: (v) {
                c.autoGrow = v;
                c.notify();
              },
            ),
            const Hint(
              'You can also drag the handles on the page’s edge. Resizing never changes what is on it.',
            ),
          ],
        ),
        Section(
          title: 'Page colour',
          children: [
            ColorRow(
              allowNone: true,
              value: d.background,
              onChanged: c.setBackground,
            ),
          ],
        ),
        Section(
          title: 'Grid',
          children: [
            PropRow(
              'Spacing',
              NumberField(
                key: const ValueKey('grid-size'),
                value: d.gridSize,
                suffix: ' px',
                width: 88,
                onSubmitted: (v) => c.setGridSize(v),
              ),
            ),
            ButtonRow([
              ActionButton(
                key: const ValueKey('grid-show'),
                label: 'Show grid',
                icon: Icons.grid_4x4,
                selected: c.showGrid,
                tooltip: 'Show the grid  (G)',
                onPressed: c.toggleGrid,
              ),
              ActionButton(
                key: const ValueKey('grid-snap'),
                label: 'Snap',
                icon: Icons.filter_center_focus,
                selected: c.snapOn,
                tooltip:
                    'Snap to the grid  (Shift+G). Hold Ctrl while dragging to place freely.',
                onPressed: c.toggleSnap,
              ),
            ]),
          ],
        ),
      ],
    );
  }

  /// Colour, width and so on for the next thing drawn.
  Widget _toolDefaults() {
    final rows = <Widget>[];
    if (c.tool == Tool.highlight) {
      rows.addAll(_highlightDefaults());
    } else if (c.tool == Tool.text) {
      rows.addAll([
        _colour('Colour', c.textColor, (v) {
          c.textColor = v;
          c.notify();
        }),
        PropRow(
          'Font',
          _FontPicker(
            value: c.textFont,
            onChanged: (f) {
              c.textFont = f;
              c.notify();
            },
          ),
        ),
        PropRow(
          'Size',
          _plainSlider(c.textSize, 8, 160, (v) {
            c.textSize = v.roundToDouble();
            c.notify();
          }),
        ),
      ]);
    } else {
      rows.add(
        _colour('Colour', c.penColor, (v) {
          c.penColor = v;
          c.notify();
        }),
      );
      if (c.tool == Tool.badge) {
        rows.add(
          PropRow(
            'Size',
            _plainSlider(c.markerSize, 16, 160, (v) {
              c.markerSize = v.roundToDouble();
              c.notify();
            }),
          ),
        );
      } else {
        rows.add(
          PropRow(
            'Width',
            _plainSlider(c.penWidth, 1, 30, (v) {
              c.penWidth = v.roundToDouble();
              c.notify();
            }),
          ),
        );
      }
      if (c.tool == Tool.rect || c.tool == Tool.ellipse) {
        rows.add(
          _colour('Fill', c.fillColor, (v) {
            c.fillColor = v;
            c.notify();
          }, allowNone: true),
        );
      }
    }
    return Section(first: true, children: rows);
  }

  Widget _plainSlider(
    double v,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) => SizedBox(
    width: double.infinity,
    child: SliderTheme(
      data: const SliderThemeData(
        trackHeight: 3,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: RoundSliderOverlayShape(overlayRadius: 0),
      ),
      child: Slider(
        value: v.clamp(min, max),
        min: min,
        max: max,
        onChanged: onChanged,
      ),
    ),
  );

  Widget _colour(
    String label,
    int value,
    ValueChanged<int> onChanged, {
    bool allowNone = false,
    List<int> palette = kPalette,
  }) => PropRow(
    label,
    ColorRow(
      value: value,
      onChanged: onChanged,
      allowNone: allowNone,
      palette: palette,
    ),
    stacked: true,
  );

  // ---- the highlighter ------------------------------------------------------

  /// Settings for the next highlight.
  List<Widget> _highlightDefaults() => [
    PropRow(
      'Style',
      SizedBox(
        width: 190,
        child: ButtonRow([
          ActionButton(
            key: const ValueKey('hl-marker'),
            label: 'Marker',
            icon: Icons.border_color_outlined,
            selected: !c.hlBox,
            tooltip: 'Drag over the text like a marker',
            onPressed: () {
              c.hlBox = false;
              c.notify();
            },
          ),
          ActionButton(
            key: const ValueKey('hl-box'),
            label: 'Box',
            icon: Icons.crop_square,
            selected: c.hlBox,
            tooltip: 'Drag a rectangle over a whole area',
            onPressed: () {
              c.hlBox = true;
              c.notify();
            },
          ),
        ]),
      ),
    ),
    _colour('Colour', c.hlColor, (v) {
      c.hlColor = v;
      c.notify();
    }, palette: kHighlightPalette),
    if (!c.hlBox)
      PropRow(
        'Width',
        _plainSlider(c.hlWidth, 8, 80, (v) {
          c.hlWidth = v.roundToDouble();
          c.notify();
        }),
      ),
    SwitchRow(
      key: const ValueKey('hl-keep-text'),
      label: 'Keep the text readable',
      hint:
          'Tints the page and keeps writing under it dark. Turn off for dark pictures.',
      value: c.hlKeepText,
      onChanged: (v) {
        c.hlKeepText = v;
        c.notify();
      },
    ),
  ];

  /// Settings for a highlight that is already on the page.
  Section _highlightSection(SceneObject o) {
    final style = o is StrokeObject
        ? o.highlight
        : (o as ShapeObject).highlight;
    final colour = o is StrokeObject ? o.color : (o as ShapeObject).fill;
    return Section(
      title: 'Highlight',
      children: [
        _colour('Colour', colour, (v) {
          c.editSelected('highlight colour', (x) {
            if (x is StrokeObject) x.color = v;
            if (x is ShapeObject) {
              x.fill = v;
              x.stroke = v;
            }
          });
          c.hlColor = v;
        }, palette: kHighlightPalette),
        if (o is StrokeObject)
          PropRow(
            'Width',
            LiveSlider(
              controller: c,
              value: o.width,
              min: 8,
              max: 80,
              label: 'width',
              apply: (v) => c.liveEditSelected((x) {
                (x as StrokeObject).width = v.roundToDouble();
                c.hlWidth = v.roundToDouble();
              }),
            ),
          ),
        SwitchRow(
          key: const ValueKey('hl-keep-text'),
          label: 'Keep the text readable',
          hint:
              'Tints the page and keeps writing under it dark. Turn off for dark pictures.',
          value: style == HighlightStyle.multiply,
          onChanged: (keep) {
            c.editSelected('highlight blend', (x) {
              final h = keep ? HighlightStyle.multiply : HighlightStyle.plain;
              if (x is StrokeObject) x.highlight = h;
              if (x is ShapeObject) x.highlight = h;
              // Plain needs to be see-through; multiply does not.
              if (!keep && x.opacity > 0.95) x.opacity = 0.45;
              if (keep && x.opacity <= 0.5) x.opacity = 1;
            });
            c.hlKeepText = keep;
          },
        ),
      ],
    );
  }

  // ---- selection ----------------------------------------------------------

  Widget _selection(BuildContext context, List<SceneObject> objs) {
    final one = objs.length == 1 ? objs.first : null;
    final kinds = objs.map((o) => o.kind).toSet();
    final sameKind = kinds.length == 1;
    final first = objs.first;
    final layerIds = objs.map((o) => c.doc.layerOf(o.id)?.id).toSet();
    final locked = objs.any((o) => o.locked);

    final specific = one != null
        ? _typeSection(context, one)
        : sameKind
        ? _typeSectionMulti(objs)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Section(
          first: true,
          children: [
            if (one != null)
              PropRow(
                'Name',
                SizedBox(
                  height: kControlHeight,
                  child: TextFormField(
                    key: ValueKey('name-${one.id}-${one.name}'),
                    initialValue: one.name,
                    style: const TextStyle(fontSize: 12.5),
                    decoration: InputDecoration(
                      isDense: true,
                      border: fieldBorder(),
                      enabledBorder: fieldBorder(),
                      focusedBorder: fieldBorder(focused: true),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                    ),
                    onFieldSubmitted: (v) => c.renameObject(one.id, v),
                  ),
                ),
              ),
            PropRow(
              'Layer',
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  isDense: true,
                  style: const TextStyle(fontSize: 12.5, color: kInk),
                  value: layerIds.length == 1 ? layerIds.first : null,
                  hint: const Text('Several layers'),
                  items: [
                    for (final l in c.doc.layers.reversed)
                      DropdownMenuItem(
                        value: l.id,
                        child: Text(l.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      c.moveObjectsToLayer(objs.map((o) => o.id).toList(), v);
                    }
                  },
                ),
              ),
            ),
            PropRow(
              'Opacity',
              Row(
                children: [
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
                  SizedBox(
                    width: 38,
                    child: Text(
                      '${(first.opacity * 100).round()}%',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12, color: kInk),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (one is BoxObject)
          Section(title: 'Size and rotation', children: _transform(one)),
        ?specific,
        if (c.mergeable.length > 1)
          Section(
            title: 'Combine',
            children: [
              ActionButton(
                key: const ValueKey('merge-button'),
                label: 'Merge into one image',
                icon: Icons.layers_clear_outlined,
                tooltip:
                    'Turn everything selected into a single picture  (M). You can take it apart again later.',
                onPressed: c.flattenSelection,
              ),
            ],
          ),
        Section(
          title: 'Align',
          children: [
            Row(
              children: [
                IconGroup(
                  buttons: [
                    GroupButton(
                      icon: Icons.align_horizontal_left,
                      tooltip: objs.length > 1
                          ? 'Align left edges'
                          : 'Align to the left of the page',
                      onPressed: () => c.alignSelection('left'),
                    ),
                    GroupButton(
                      icon: Icons.align_horizontal_center,
                      tooltip: 'Centre horizontally',
                      onPressed: () => c.alignSelection('centre'),
                    ),
                    GroupButton(
                      icon: Icons.align_horizontal_right,
                      tooltip: 'Align right edges',
                      onPressed: () => c.alignSelection('right'),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                IconGroup(
                  buttons: [
                    GroupButton(
                      icon: Icons.align_vertical_top,
                      tooltip: 'Align top edges',
                      onPressed: () => c.alignSelection('top'),
                    ),
                    GroupButton(
                      icon: Icons.align_vertical_center,
                      tooltip: 'Centre vertically',
                      onPressed: () => c.alignSelection('middle'),
                    ),
                    GroupButton(
                      icon: Icons.align_vertical_bottom,
                      tooltip: 'Align bottom edges',
                      onPressed: () => c.alignSelection('bottom'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        Section(
          title: 'Arrange',
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                IconGroup(
                  buttons: [
                    GroupButton(
                      icon: Icons.flip_to_front,
                      tooltip: 'Bring to front  Ctrl+Shift+]',
                      onPressed: () => c.reorderSelection('front'),
                    ),
                    GroupButton(
                      icon: Icons.arrow_upward,
                      tooltip: 'Forward  ]',
                      onPressed: () => c.reorderSelection('forward'),
                    ),
                    GroupButton(
                      icon: Icons.arrow_downward,
                      tooltip: 'Backward  [',
                      onPressed: () => c.reorderSelection('backward'),
                    ),
                    GroupButton(
                      icon: Icons.flip_to_back,
                      tooltip: 'Send to back  Ctrl+Shift+[',
                      onPressed: () => c.reorderSelection('back'),
                    ),
                  ],
                ),
                IconGroup(
                  buttons: [
                    GroupButton(
                      icon: Icons.copy_all_outlined,
                      tooltip: 'Duplicate  Ctrl+D',
                      onPressed: c.duplicateSelection,
                    ),
                    GroupButton(
                      icon: locked ? Icons.lock : Icons.lock_outline,
                      tooltip: locked
                          ? 'Unlock so it can be grabbed again'
                          : 'Lock so it can’t be grabbed',
                      active: locked,
                      onPressed: () => c.editSelected(
                        locked ? 'unlock' : 'lock',
                        (o) => o.locked = !locked,
                      ),
                    ),
                    if (objs.any((o) => o is ImageObject))
                      GroupButton(
                        icon: Icons.collections_outlined,
                        tooltip: 'Keep a copy in the collection',
                        onPressed: c.sendSelectionToCollection,
                      ),
                    GroupButton(
                      icon: Icons.delete_outline,
                      tooltip: 'Delete  Del',
                      danger: true,
                      onPressed: c.deleteSelection,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  /// Size, turning and flipping: how the thing sits on the page.
  List<Widget> _transform(BoxObject one) {
    final a = one is ImageObject ? c.assets[one.assetId] : null;
    return [
      if (one is BadgeObject)
        PropRow(
          'Size',
          Row(
            children: [
              Expanded(
                child: LiveSlider(
                  key: const ValueKey('marker-size'),
                  controller: c,
                  value: math.max(one.size.width, one.size.height),
                  min: 16,
                  max: 160,
                  label: 'marker size',
                  apply: (v) => c.liveEditSelected((x) {
                    final n = v.roundToDouble();
                    (x as BadgeObject).size = Size(n, n);
                    c.markerSize = n;
                  }),
                ),
              ),
              SizedBox(
                width: 34,
                child: Text(
                  '${math.max(one.size.width, one.size.height).round()}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 12, color: kInk),
                ),
              ),
            ],
          ),
        )
      else if (one is! TextObject)
        PropRow(
          'Size',
          Row(
            children: [
              NumberField(
                key: const ValueKey('size-w'),
                value: one.size.width,
                width: 64,
                onSubmitted: (v) => c.editSelected(
                  'resize',
                  (o) => (o as BoxObject).size = Size(
                    math.max(4, v),
                    o.size.height,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text('×', style: TextStyle(color: kLabel)),
              ),
              NumberField(
                key: const ValueKey('size-h'),
                value: one.size.height,
                width: 64,
                onSubmitted: (v) => c.editSelected(
                  'resize',
                  (o) => (o as BoxObject).size = Size(
                    o.size.width,
                    math.max(4, v),
                  ),
                ),
              ),
              if (a != null) ...[
                const SizedBox(width: 6),
                SmallIconButton(
                  icon: Icons.photo_size_select_actual_outlined,
                  tooltip:
                      'Back to the picture’s own size (${a.width} × ${a.height})',
                  onPressed: () => c.editSelected(
                    'original size',
                    (x) => (x as ImageObject).size = Size(
                      a.width.toDouble(),
                      a.height.toDouble(),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      PropRow(
        'Rotate',
        Row(
          children: [
            NumberField(
              key: const ValueKey('rotation'),
              value: (one.rotation * 180 / math.pi),
              suffix: '°',
              width: 76,
              onSubmitted: (v) => c.editSelected(
                'rotate',
                (o) => (o as BoxObject).rotation = v * math.pi / 180,
              ),
            ),
            const SizedBox(width: 8),
            IconGroup(
              buttons: [
                GroupButton(
                  icon: Icons.rotate_90_degrees_ccw,
                  tooltip: 'Rotate 90° left',
                  onPressed: () => c.editSelected(
                    'rotate',
                    (o) => (o as BoxObject).rotation -= math.pi / 2,
                  ),
                ),
                GroupButton(
                  icon: Icons.rotate_90_degrees_cw,
                  tooltip: 'Rotate 90° right',
                  onPressed: () => c.editSelected(
                    'rotate',
                    (o) => (o as BoxObject).rotation += math.pi / 2,
                  ),
                ),
                if (one is ImageObject)
                  GroupButton(
                    icon: Icons.flip,
                    tooltip: 'Flip left to right',
                    active: one.flipX,
                    onPressed: () => c.editSelected(
                      'flip',
                      (x) => (x as ImageObject).flipX = !x.flipX,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  // ---- what is specific to the kind of thing ------------------------------

  int _colorOf(SceneObject o) => o is LineObject
      ? o.color
      : o is StrokeObject
      ? o.color
      : o is ShapeObject
      ? o.stroke
      : 0;

  void _setColor(SceneObject o, int v) {
    if (o is LineObject) o.color = v;
    if (o is StrokeObject) o.color = v;
    if (o is ShapeObject) o.stroke = v;
    c.penColor = v;
  }

  Widget? _typeSectionMulti(List<SceneObject> objs) {
    final f = objs.first;
    if (f is LineObject || f is StrokeObject || f is ShapeObject) {
      return Section(
        children: [
          _colour(
            'Colour',
            _colorOf(f),
            (v) => c.editSelected('colour', (o) => _setColor(o, v)),
          ),
        ],
      );
    }
    return null;
  }

  Widget? _typeSection(BuildContext context, SceneObject o) {
    if ((o is StrokeObject && o.highlight != HighlightStyle.none) ||
        (o is ShapeObject && o.highlight != HighlightStyle.none)) {
      return _highlightSection(o);
    }
    if (o is BadgeObject) {
      return Section(
        title: 'Marker',
        children: [
          PropRow(
            'Number',
            NumberField(
              key: const ValueKey('badge-number'),
              value: o.number.toDouble(),
              width: 76,
              onSubmitted: (v) => c.editSelected(
                'renumber',
                (x) => (x as BadgeObject).number = v.round().clamp(0, 999),
              ),
            ),
          ),
          _colour('Colour', o.color, (v) {
            c.editSelected('colour', (x) => (x as BadgeObject).color = v);
            c.penColor = v;
          }),
          if (c.markersUnlike(o) > 0)
            ActionButton(
              key: const ValueKey('match-markers'),
              label: 'Make all markers this size',
              icon: Icons.format_size,
              tooltip:
                  'Resize every other marker to match this one (${c.markersUnlike(o)} differ)',
              onPressed: () => c.matchMarkerSizes(o),
            ),
        ],
      );
    }
    if (o is LineObject) {
      return Section(
        title: o.headEnd ? 'Arrow' : 'Line',
        children: [
          _colour(
            'Colour',
            o.color,
            (v) => c.editSelected('colour', (x) => _setColor(x, v)),
          ),
          PropRow(
            'Width',
            LiveSlider(
              controller: c,
              value: o.width,
              min: 1,
              max: 30,
              label: 'width',
              apply: (v) => c.liveEditSelected((x) {
                (x as LineObject).width = v.roundToDouble();
                c.penWidth = v.roundToDouble();
              }),
            ),
          ),
          PropRow(
            'Ends',
            IconGroup(
              buttons: [
                GroupButton(
                  icon: Icons.arrow_back,
                  tooltip: 'Arrowhead at the start',
                  active: o.headStart,
                  onPressed: () => c.editSelected(
                    'arrowhead',
                    (x) => (x as LineObject).headStart = !x.headStart,
                  ),
                ),
                GroupButton(
                  icon: Icons.arrow_forward,
                  tooltip: 'Arrowhead at the end',
                  active: o.headEnd,
                  onPressed: () => c.editSelected(
                    'arrowhead',
                    (x) => (x as LineObject).headEnd = !x.headEnd,
                  ),
                ),
                GroupButton(
                  icon: Icons.more_horiz,
                  tooltip: 'Dashed',
                  active: o.dashed,
                  onPressed: () => c.editSelected(
                    'dashed',
                    (x) => (x as LineObject).dashed = !x.dashed,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    if (o is StrokeObject) {
      return Section(
        title: 'Pen stroke',
        children: [
          _colour(
            'Colour',
            o.color,
            (v) => c.editSelected('colour', (x) => _setColor(x, v)),
          ),
          PropRow(
            'Width',
            LiveSlider(
              controller: c,
              value: o.width,
              min: 1,
              max: 30,
              label: 'width',
              apply: (v) => c.liveEditSelected((x) {
                (x as StrokeObject).width = v.roundToDouble();
              }),
            ),
          ),
        ],
      );
    }
    if (o is ShapeObject) {
      return Section(
        title: o.ellipse ? 'Ellipse' : 'Rectangle',
        children: [
          _colour(
            'Outline',
            o.stroke,
            (v) => c.editSelected('colour', (x) => _setColor(x, v)),
          ),
          _colour('Fill', o.fill, (v) {
            c.editSelected('fill', (x) => (x as ShapeObject).fill = v);
            c.fillColor = v;
          }, allowNone: true),
          PropRow(
            'Width',
            LiveSlider(
              controller: c,
              value: o.strokeWidth,
              min: 0,
              max: 30,
              label: 'width',
              apply: (v) => c.liveEditSelected((x) {
                (x as ShapeObject).strokeWidth = v.roundToDouble();
              }),
            ),
          ),
        ],
      );
    }
    if (o is TextObject) {
      return Section(
        title: 'Text',
        children: [
          _colour('Colour', o.color, (v) {
            c.editSelected('text colour', (x) => (x as TextObject).color = v);
            c.textColor = v;
          }),
          PropRow(
            'Font',
            _FontPicker(
              value: o.font,
              onChanged: (f) {
                c.editSelected('font', (x) => (x as TextObject).font = f);
                c.textFont = f;
              },
            ),
          ),
          PropRow(
            'Size',
            Row(
              children: [
                Expanded(
                  child: LiveSlider(
                    controller: c,
                    value: o.fontSize,
                    min: 8,
                    max: 160,
                    label: 'text size',
                    apply: (v) => c.liveEditSelected((x) {
                      (x as TextObject).fontSize = v.roundToDouble();
                      c.textSize = v.roundToDouble();
                    }),
                  ),
                ),
                SizedBox(
                  width: 30,
                  child: Text(
                    '${o.fontSize.round()}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 12, color: kInk),
                  ),
                ),
              ],
            ),
          ),
          PropRow(
            'Style',
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                IconGroup(
                  buttons: [
                    GroupButton(
                      icon: Icons.format_bold,
                      tooltip: 'Bold',
                      active: o.bold,
                      onPressed: () => c.editSelected(
                        'bold',
                        (x) => (x as TextObject).bold = !x.bold,
                      ),
                    ),
                    GroupButton(
                      icon: Icons.format_italic,
                      tooltip: 'Italic',
                      active: o.italic,
                      onPressed: () => c.editSelected(
                        'italic',
                        (x) => (x as TextObject).italic = !x.italic,
                      ),
                    ),
                  ],
                ),
                IconGroup(
                  buttons: [
                    for (final (icon, tip, al) in [
                      (Icons.format_align_left, 'Align left', TextAlign.left),
                      (Icons.format_align_center, 'Centre', TextAlign.center),
                      (
                        Icons.format_align_right,
                        'Align right',
                        TextAlign.right,
                      ),
                    ])
                      GroupButton(
                        icon: icon,
                        tooltip: tip,
                        active: o.align == al,
                        onPressed: () => c.editSelected(
                          'align',
                          (x) => (x as TextObject).align = al,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          _colour('Backdrop', o.background, (v) {
            c.editSelected(
              'text backdrop',
              (x) => (x as TextObject).background = v,
            );
          }, allowNone: true),
          ActionButton(
            label: 'Edit text',
            icon: Icons.text_fields,
            tooltip: 'Type in the text box  (Enter or F2)',
            onPressed: () => c.beginTextEdit(o.id),
          ),
        ],
      );
    }
    if (o is ImageObject) {
      return Section(
        title: 'Picture',
        children: [
          ActionButton(
            key: const ValueKey('cutout-button'),
            label: 'Cut out…',
            icon: Icons.content_cut,
            tooltip:
                'Draw around the part you want. It becomes its own picture.  (C)',
            onPressed: () => c.setTool(Tool.cutout),
          ),
          ActionButton(
            key: const ValueKey('remove-bg-button'),
            label: 'Remove background',
            icon: Icons.auto_fix_high,
            tooltip:
                'Make the background around the picture see-through. You can fine-tune it afterwards.',
            onPressed: () => c.removeBackgroundFrom(o),
          ),

          if (c.canUnmerge)
            ActionButton(
              key: const ValueKey('unmerge-button'),
              label: 'Unmerge into the original pieces',
              icon: Icons.call_split,
              tooltip: 'Take this merged picture apart again  (U)',
              onPressed: c.unmerge,
            ),
        ],
      );
    }
    return null;
  }
}

/// Four little "Aa" buttons, each drawn in its own typeface.
class _FontPicker extends StatelessWidget {
  const _FontPicker({required this.value, required this.onChanged});
  final TextFont value;
  final ValueChanged<TextFont> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final f in TextFont.values)
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Tooltip(
            message: f.label,
            child: InkWell(
              key: ValueKey('font-${f.name}'),
              borderRadius: BorderRadius.circular(7),
              onTap: () => onChanged(f),
              child: Container(
                width: 38,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: f == value ? kAccent.withValues(alpha: 0.14) : null,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: f == value ? kAccent : const Color(0xFFD0D4DD),
                  ),
                ),
                child: Text(
                  'Aa',
                  style: TextStyle(
                    fontFamily: f.family,
                    fontSize: f == TextFont.hand ? 17 : 14,
                    height: 1.1,
                    color: kInk,
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
