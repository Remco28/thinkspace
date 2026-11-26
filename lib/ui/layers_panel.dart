import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../editor/canvas_view.dart';
import '../editor/controller.dart';
import '../model/scene.dart';
import 'context_menu.dart';
import 'menus.dart';
import 'widgets.dart';
import 'design.dart';

// One set of columns for both kinds of row, so they line up: an object's
// icon starts under its layer's name, and every eye is in one column at the
// right, with the layers' counts just before it.
const double _rowInset = kSpace8; // from the panel's edges
const double _rowPad = kSpace8; // inside a row, at both ends
const double _lead = kIcon + kIcon + kSpace4; // grip, arrow, gap
const double _countWidth = kSpace20;
const double _rowButton = kSpace24;
const double _groupGap = kSpace8;
const double _objectGap = 1; // above each object row

/// The room above every layer but the top one: the gap, the 1 px line
/// between layers and the smaller gap under it.
const double _gapAbove = _groupGap + _groupGap / 2;

/// The object's kind, drawn as its tool is in the toolbar.
Widget kindGlyph(SceneObject o, double size, Color color) => switch (o.kind) {
  ObjectKind.text => OutlineGlyph(GlyphKind.text, size, color),
  ObjectKind.badge => OutlineGlyph(GlyphKind.marker, size, color),
  ObjectKind.hide => HideDetailsGlyph(size, color),
  ObjectKind.line when !(o is LineObject && o.headEnd) => LineGlyph(
    size,
    color,
  ),
  _ => Icon(kindIcon(o), size: size, color: color),
};

IconData kindIcon(SceneObject o) => switch (o.kind) {
  ObjectKind.image => Icons.image_outlined,
  ObjectKind.text => Icons.title,
  ObjectKind.rect => Icons.crop_square,
  ObjectKind.ellipse => Icons.circle_outlined,
  ObjectKind.line =>
    o is LineObject && o.headEnd ? Icons.north_east : Icons.horizontal_rule,
  ObjectKind.stroke => Icons.edit_outlined,
  ObjectKind.badge => Icons.looks_one_outlined,
  ObjectKind.hide => Icons.grid_on,
};

class LayersPanel extends StatefulWidget {
  const LayersPanel({super.key, required this.controller});
  final EditorController controller;

  @override
  State<LayersPanel> createState() => _LayersPanelState();
}

class _LayersPanelState extends State<LayersPanel> {
  EditorController get c => widget.controller;
  final _scroll = ScrollController();
  int _seenFresh = 0;
  int _seenRename = 0;

  /// The new layer whose name is open for typing.
  String? _naming;

  static const double _layerRow = 32, _objectRow = 28, _pad = 4;

  @override
  void initState() {
    super.initState();
    _seenFresh = c.freshLayerCount;
    _seenRename = c.renameCount;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// A layer was just made: open its name and scroll it into view.
  void _noticeFresh() {
    if (c.freshLayerCount == _seenFresh) return;
    _seenFresh = c.freshLayerCount;
    final id = c.freshLayerId;
    if (c.doc.layerById(id ?? '') == null) return;
    _naming = id;
    _scrollToRow(id!);
  }

  /// A rename began (F2, a double-click, the menu): bring its row into view.
  void _noticeRename() {
    if (c.renameCount == _seenRename) return;
    _seenRename = c.renameCount;
    final id = c.renamingId;
    if (id != null) _scrollToRow(id);
  }

  /// Scroll a layer's or an object's row into view. Rows have fixed heights,
  /// so its place can be worked out without building it.
  void _scrollToRow(String id) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      var top = _pad;
      var height = _layerRow;
      var first = true;
      search:
      for (final l in c.doc.layers.reversed) {
        if (!first) top += _gapAbove;
        first = false;
        if (l.id == id) break;
        top += _layerRow;
        if (c.collapsedLayers.contains(l.id)) continue;
        for (final o in l.objects.reversed) {
          top += _objectGap;
          if (o.id == id) {
            height = _objectRow;
            break search;
          }
          top += _objectRow;
        }
      }
      final pos = _scroll.position;
      final rowBottom = top + height;
      double? to;
      if (top < pos.pixels) to = top - _pad;
      if (rowBottom > pos.pixels + pos.viewportDimension) {
        to = rowBottom - pos.viewportDimension + _pad;
      }
      if (to == null) return;
      _scroll.animateTo(
        to.clamp(0.0, pos.maxScrollExtent),
        duration: kScroll,
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c.panels,
      builder: (context, _) {
        _noticeFresh();
        _noticeRename();
        final layers = c.doc.layers;
        final n = layers.length;
        return Column(
          children: [
            PanelHeader(
              'Layers',
              actions: [
                SmallIconButton(
                  icon: Icons.add,
                  tooltip: 'Add layer',
                  onPressed: c.addLayer,
                ),
              ],
            ),
            Expanded(
              child: ReorderableListView.builder(
                scrollController: _scroll,
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.symmetric(vertical: kSpace4),
                itemCount: n,
                onReorderItem: (oldI, newI) =>
                    c.moveLayer(n - 1 - oldI, n - 1 - newI),
                itemBuilder: (context, i) {
                  final layer = layers[n - 1 - i];
                  return _LayerTile(
                    key: ValueKey(layer.id),
                    c: c,
                    layer: layer,
                    index: i,
                    collapsed: c.collapsedLayers.contains(layer.id),
                    fresh: c.freshLayerId == layer.id ? c.freshLayerCount : 0,
                    naming: _naming == layer.id || c.renamingId == layer.id,
                    onNamed: () {
                      setState(() => _naming = null);
                      c.endRename();
                    },
                    onToggle: () {
                      c.collapsedLayers.contains(layer.id)
                          ? c.collapsedLayers.remove(layer.id)
                          : c.collapsedLayers.add(layer.id);
                      c.notify();
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LayerTile extends StatelessWidget {
  const _LayerTile({
    super.key,
    required this.c,
    required this.layer,
    required this.index,
    required this.collapsed,
    required this.onToggle,
    this.fresh = 0,
    this.naming = false,
    this.onNamed,
  });
  final EditorController c;
  final Layer layer;
  final int index;
  final bool collapsed;
  final VoidCallback onToggle;

  /// Non-zero for a layer just made: the row lights up and fades back.
  final int fresh;

  /// The name is a text box, ready for typing.
  final bool naming;
  final VoidCallback? onNamed;

  @override
  Widget build(BuildContext context) {
    final isCurrent = c.currentLayerId == layer.id;
    final header = DragTarget<ObjectDrag>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) => c.moveObjectsToLayer(d.data.ids, layer.id),
      builder: (context, cand, _) => QuickTap(
        key: ValueKey('layer-${layer.id}'),
        onTap: () => c.selectLayerContents(layer.id),
        onDoubleTap: () => c.beginRename(layer.id),
        onSecondaryTapDown: (d) => _menu(context, d.globalPosition),
        child: _Hover(
          builder: (hover) => TweenAnimationBuilder<double>(
            key: ValueKey('layer-flash-$fresh'),
            tween: Tween(begin: fresh == 0 ? 0 : 1, end: 0),
            duration: kFlash,
            curve: Curves.easeIn,
            builder: (context, glow, child) => Container(
              height: 32,
              margin: const EdgeInsets.symmetric(horizontal: _rowInset),
              // The fill is for what is selected; the current layer is
              // marked by the bar at its left instead, so one thing at a
              // time looks selected. A new layer still glows briefly.
              decoration: BoxDecoration(
                color: cand.isNotEmpty
                    ? kAccent.withValues(alpha: 0.18)
                    : glow > 0
                    ? kAccent.withValues(alpha: 0.26 * glow)
                    : hover
                    ? kHover
                    : null,
                borderRadius: BorderRadius.circular(kRadius),
                border: cand.isNotEmpty || glow > 0
                    ? Border.all(
                        color: kAccent.withValues(
                          alpha: cand.isNotEmpty ? 1 : glow,
                        ),
                      )
                    : null,
              ),
              child: child,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.centerLeft,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _rowPad),
                  child: Row(
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: const MouseRegion(
                          cursor: SystemMouseCursors.grab,
                          child: Icon(
                            Icons.drag_indicator,
                            size: kIcon,
                            color: kInkFaint,
                          ),
                        ),
                      ),
                      InkResponse(
                        onTap: onToggle,
                        radius: 12,
                        child: Icon(
                          collapsed ? Icons.chevron_right : Icons.expand_more,
                          size: kIcon,
                          color: kInkSoft,
                        ),
                      ),
                      const SizedBox(width: kSpace4),
                      Expanded(
                        child: naming
                            ? _NameField(
                                key: ValueKey('layer-name-${layer.id}'),
                                strong: true,
                                initial: layer.name,
                                onDone: (v) {
                                  if (v != null && v.trim() != layer.name) {
                                    c.renameLayer(layer.id, v);
                                  }
                                  onNamed?.call();
                                },
                              )
                            : Text(
                                layer.name,
                                overflow: TextOverflow.ellipsis,
                                // The current layer, where new things go, is
                                // named in the accent colour beside its bar.
                                style: TextStyle(
                                  fontSize: kTextBody,
                                  fontWeight: kWeightStrong,
                                  color: !layer.visible
                                      ? kInkFaint
                                      : isCurrent
                                      ? kAccent
                                      : kInk,
                                ),
                              ),
                      ),
                      if (layer.locked)
                        const Padding(
                          padding: EdgeInsets.only(left: kSpace4),
                          child: Icon(
                            Icons.lock_outline,
                            size: kIconSmall,
                            color: kInkSoft,
                          ),
                        ),
                      SizedBox(
                        width: _countWidth,
                        child: Text(
                          '${layer.objects.length}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: kTextCaption,
                            color: kInkSoft,
                          ),
                        ),
                      ),
                      const SizedBox(width: kSpace4),
                      _Eye(
                        key: ValueKey('layer-eye-${layer.id}'),
                        visible: layer.visible,
                        hover: hover,
                        tooltip: layer.visible ? 'Hide layer' : 'Show layer',
                        onTap: () =>
                            c.setLayerVisible(layer.id, !layer.visible),
                      ),
                    ],
                  ),
                ),
                if (isCurrent)
                  Positioned(
                    key: const ValueKey('current-layer-bar'),
                    // Inside the row, and as wide as its margin, so the
                    // pointer can rest on it and get the tooltip.
                    left: 0,
                    width: _rowPad,
                    top: kSpace4,
                    bottom: kSpace4,
                    child: Tooltip(
                      message: 'New things go on this layer',
                      waitDuration: kTooltipWait,
                      child: Align(
                        alignment: const Alignment(-0.5, 0),
                        child: Container(
                          width: 3,
                          decoration: BoxDecoration(
                            color: kAccent,
                            borderRadius: BorderRadius.circular(kRadiusPill),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    final rows = [
      header,
      if (!collapsed)
        for (final o in layer.objects.reversed)
          _ObjectRow(c: c, layer: layer, object: o),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (index > 0)
          Container(
            height: 1,
            margin: const EdgeInsets.fromLTRB(
              _rowInset + _rowPad,
              _groupGap,
              _rowInset + _rowPad,
              _groupGap / 2 - 1,
            ),
            color: kBorder,
          ),
        ...rows,
      ],
    );
  }

  void _menu(BuildContext context, Offset at) async {
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: [
        menuItem(
          value: 'rename',
          label: 'Rename',
          icon: Icons.drive_file_rename_outline,
          width: 220,
        ),
        menuItem(
          value: 'select',
          label: 'Select everything on this layer',
          icon: Icons.select_all,
          width: 220,
        ),
        menuItem(
          value: 'duplicate',
          label: 'Duplicate layer',
          icon: Icons.copy_all_outlined,
          width: 220,
        ),
        menuItem(
          value: 'lock',
          label: layer.locked ? 'Unlock layer' : 'Lock layer',
          icon: layer.locked ? Icons.lock_open_outlined : Icons.lock_outline,
          width: 220,
        ),
        menuDivider(),
        menuItem(
          value: 'delete',
          label: 'Delete layer',
          icon: Icons.delete_outline,
          danger: true,
          width: 220,
        ),
      ],
    );
    if (!context.mounted) return;
    switch (v) {
      case 'rename':
        c.beginRename(layer.id);
      case 'select':
        c.selectLayerContents(layer.id);
      case 'duplicate':
        c.duplicateLayer(layer.id);
      case 'lock':
        c.setLayerLocked(layer.id, !layer.locked);
      case 'delete':
        c.deleteLayer(layer.id);
    }
  }
}

class _ObjectRow extends StatefulWidget {
  const _ObjectRow({
    required this.c,
    required this.layer,
    required this.object,
  });
  final EditorController c;
  final Layer layer;
  final SceneObject object;

  @override
  State<_ObjectRow> createState() => _ObjectRowState();
}

/// A row is also where other rows are dropped: on its top half they go in
/// front of it (above in the list), on its bottom half behind it. A line
/// shows which.
class _ObjectRowState extends State<_ObjectRow> {
  /// While a drag is over this row: true for its top half, false for the
  /// bottom, null when nothing is over it.
  bool? _dropAbove;

  EditorController get c => widget.c;
  Layer get layer => widget.layer;
  SceneObject get object => widget.object;

  bool _topHalf(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return true;
    return box.globalToLocal(global).dy < box.size.height / 2;
  }

  @override
  Widget build(BuildContext context) {
    return DragTarget<ObjectDrag>(
      onWillAcceptWithDetails: (d) => !d.data.ids.contains(object.id),
      onMove: (d) {
        final above = _topHalf(d.offset);
        if (above != _dropAbove) setState(() => _dropAbove = above);
      },
      onLeave: (_) => setState(() => _dropAbove = null),
      onAcceptWithDetails: (d) {
        final above = _topHalf(d.offset);
        setState(() => _dropAbove = null);
        // The list shows the front-most object first, so above is in front.
        c.moveObjectsBeside(d.data.ids, object.id, inFront: above);
      },
      builder: (context, cand, _) => Stack(
        clipBehavior: Clip.none,
        children: [
          _row(context),
          if (cand.isNotEmpty && _dropAbove != null)
            Positioned(
              key: const ValueKey('drop-line'),
              left: _rowInset + _rowPad + _lead - kSpace4,
              right: _rowInset,
              top: _dropAbove! ? -1 : null,
              bottom: _dropAbove! ? null : -1,
              child: IgnorePointer(
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    color: kAccent,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context) {
    final selected = c.selection.contains(object.id);
    final dim = !object.visible || !layer.visible;
    final row = _Hover(
      builder: (hover) => Container(
        key: ValueKey('object-${object.id}'),
        height: 28,
        margin: const EdgeInsets.only(
          left: _rowInset,
          right: _rowInset,
          top: _objectGap,
        ),
        padding: const EdgeInsets.symmetric(horizontal: _rowPad),
        decoration: BoxDecoration(
          color: selected
              ? kAccentSoft
              : hover
              ? kHover
              : null,
          borderRadius: BorderRadius.circular(kRadius),
        ),
        child: Row(
          children: [
            const SizedBox(width: _lead),
            kindGlyph(object, kIcon, dim ? kInkDisabled : kInkSoft),
            const SizedBox(width: kSpace8),
            Expanded(
              child: c.renamingId == object.id
                  ? _NameField(
                      key: ValueKey('object-name-${object.id}'),
                      initial: object.name,
                      onDone: (v) {
                        if (v != null && v.trim().isNotEmpty) {
                          if (v.trim() != object.name) {
                            c.renameObject(object.id, v.trim());
                          }
                        }
                        c.endRename();
                      },
                    )
                  : Text(
                      object.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: kTextBody,
                        color: dim ? kInkFaint : kInk,
                      ),
                    ),
            ),
            // In the column a layer's count takes, just left of the eye.
            SizedBox(
              width: _countWidth + kSpace4,
              child: object.locked
                  ? _RowButton(
                      key: ValueKey('object-lock-${object.id}'),
                      icon: Icons.lock_outline,
                      size: kIconSmall,
                      tooltip: 'Locked — click to unlock',
                      color: kInkSoft,
                      onTap: () {
                        c.select([object.id]);
                        c.editSelected('unlock', (o) => o.locked = false);
                      },
                    )
                  : null,
            ),
            _Eye(
              key: ValueKey('object-eye-${object.id}'),
              visible: object.visible,
              hover: hover,
              underHidden: !layer.visible,
              tooltip: object.visible ? 'Hide' : 'Show',
              onTap: () => c.setObjectVisible(object.id, !object.visible),
            ),
          ],
        ),
      ),
    );
    return Draggable<ObjectDrag>(
      data: ObjectDrag(selected ? List.of(c.selection) : [object.id]),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: kSpace12,
            vertical: kSpace4,
          ),
          decoration: BoxDecoration(
            color: kAccent,
            borderRadius: BorderRadius.circular(kRadius),
          ),
          child: Text(
            selected && c.selection.length > 1
                ? '${c.selection.length} objects'
                : object.name,
            style: const TextStyle(color: Colors.white, fontSize: kTextBody),
          ),
        ),
      ),
      child: QuickTap(
        onSecondaryTapDown: (d) {
          if (!c.selection.contains(object.id)) c.select([object.id]);
          showObjectMenu(context, c, d.globalPosition);
        },
        onTap: () {
          final kb = currentModifiers();
          c.clickListRow(object.id, shift: kb.shift, ctrl: kb.ctrl);
        },
        onDoubleTap: () => c.beginRename(object.id),
        child: row,
      ),
    );
  }
}

/// A layer's or an object's name, open for typing in its row with the old
/// name selected. Enter or clicking elsewhere keeps what was typed; Escape
/// keeps the name it had. Either way the keyboard goes back to the editor's
/// shortcuts.
class _NameField extends StatefulWidget {
  const _NameField({
    super.key,
    required this.initial,
    required this.onDone,
    this.strong = false,
  });
  final String initial;
  final ValueChanged<String?> onDone;

  /// In the weight of a layer's name rather than an object's.
  final bool strong;

  @override
  State<_NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<_NameField> {
  late final TextEditingController _ctl =
      TextEditingController(text: widget.initial)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.initial.length,
        );
  final FocusNode _focus = FocusNode();
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _finish(_ctl.text);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _ctl.dispose();
    super.dispose();
  }

  void _finish(String? v) {
    if (_done) return;
    _done = true;
    if (_focus.hasFocus) {
      final editor = Focus.maybeOf(context);
      editor != null ? editor.requestFocus() : _focus.unfocus();
    }
    widget.onDone(v);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 26,
    child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => _finish(null),
      },
      child: TextField(
        controller: _ctl,
        focusNode: _focus,
        style: TextStyle(
          fontSize: kTextBody,
          fontWeight: widget.strong ? kWeightStrong : kWeightRegular,
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: kSpace8,
            vertical: kSpace8,
          ),
          border: fieldBorder(),
          enabledBorder: fieldBorder(),
          focusedBorder: fieldBorder(focused: true),
        ),
        onSubmitted: _finish,
        onTapOutside: (_) => _finish(_ctl.text),
      ),
    ),
  );
}

/// Tells its builder whether the pointer is over it.
class _Hover extends StatefulWidget {
  const _Hover({required this.builder});
  final Widget Function(bool hover) builder;

  @override
  State<_Hover> createState() => _HoverState();
}

class _HoverState extends State<_Hover> {
  bool _on = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _on = true),
    onExit: (_) => setState(() => _on = false),
    child: widget.builder(_on),
  );
}

/// A small icon button inside a list row.
class _RowButton extends StatelessWidget {
  const _RowButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
    this.size = kIcon,
  });
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    waitDuration: kTooltipWait,
    child: InkResponse(
      onTap: onTap,
      radius: _rowButton / 2,
      child: SizedBox.square(
        dimension: _rowButton,
        child: Icon(icon, size: size, color: color),
      ),
    ),
  );
}

/// Shown or hidden, in the same column for layers and objects. Shown is the
/// usual case, so its eye stays quiet until the pointer is on the row;
/// hidden is the exception and stays plain. Under a hidden layer an
/// object's eye is greyed, whatever its own setting.
class _Eye extends StatelessWidget {
  const _Eye({
    super.key,
    required this.visible,
    required this.hover,
    required this.tooltip,
    required this.onTap,
    this.underHidden = false,
  });
  final bool visible, hover, underHidden;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _RowButton(
    icon: visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
    tooltip: tooltip,
    onTap: onTap,
    color: underHidden
        ? kInkDisabled
        : !visible || hover
        ? kIconInk
        : kInkFaint,
  );
}
