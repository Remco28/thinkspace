import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../editor/canvas_painter.dart';
import '../editor/canvas_view.dart';
import '../editor/controller.dart';
import '../model/scene.dart';
import 'context_menu.dart';
import 'menus.dart';
import 'widgets.dart';

Future<String?> promptText(BuildContext context, String title, String initial) {
  final ctl = TextEditingController(text: initial);
  ctl.selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        autofocus: true,
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctl.text),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

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

  /// The new layer whose name is open for typing.
  String? _naming;

  static const double _layerRow = 34, _objectRow = 28, _pad = 4;

  @override
  void initState() {
    super.initState();
    _seenFresh = c.freshLayerCount;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// A layer was just made: open its name and scroll it into view (rows have
  /// fixed heights, so its place can be worked out without building it).
  void _noticeFresh() {
    if (c.freshLayerCount == _seenFresh) return;
    _seenFresh = c.freshLayerCount;
    final id = c.freshLayerId;
    if (c.doc.layerById(id ?? '') == null) return;
    _naming = id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      var top = _pad;
      for (final l in c.doc.layers.reversed) {
        if (l.id == id) break;
        top += _layerRow;
        if (!c.collapsedLayers.contains(l.id)) {
          top += l.objects.length * _objectRow;
        }
      }
      final pos = _scroll.position;
      final rowBottom = top + _layerRow;
      double? to;
      if (top < pos.pixels) to = top - _pad;
      if (rowBottom > pos.pixels + pos.viewportDimension) {
        to = rowBottom - pos.viewportDimension + _pad;
      }
      if (to == null) return;
      _scroll.animateTo(
        to.clamp(0.0, pos.maxScrollExtent),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        _noticeFresh();
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
                padding: const EdgeInsets.symmetric(vertical: 4),
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
                    naming: _naming == layer.id,
                    onNamed: () => setState(() => _naming = null),
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DragTarget<ObjectDrag>(
          onWillAcceptWithDetails: (_) => true,
          onAcceptWithDetails: (d) =>
              c.moveObjectsToLayer(d.data.ids, layer.id),
          builder: (context, cand, _) => QuickTap(
            key: ValueKey('layer-${layer.id}'),
            onTap: () => c.selectLayerContents(layer.id),
            onDoubleTap: () async {
              final v = await promptText(context, 'Rename layer', layer.name);
              if (v != null) c.renameLayer(layer.id, v);
            },
            onSecondaryTapDown: (d) => _menu(context, d.globalPosition),
            child: TweenAnimationBuilder<double>(
              key: ValueKey('layer-flash-$fresh'),
              tween: Tween(begin: fresh == 0 ? 0 : 1, end: 0),
              duration: const Duration(milliseconds: 1400),
              curve: Curves.easeIn,
              builder: (context, glow, child) => Container(
                height: 34,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                padding: const EdgeInsets.only(left: 2, right: 4),
                decoration: BoxDecoration(
                  color: cand.isNotEmpty
                      ? kAccent.withValues(alpha: 0.18)
                      : isCurrent
                      ? kAccent.withValues(alpha: 0.09 + 0.26 * glow)
                      : null,
                  borderRadius: BorderRadius.circular(6),
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
              child: Row(
                children: [
                  ReorderableDragStartListener(
                    index: index,
                    child: const MouseRegion(
                      cursor: SystemMouseCursors.grab,
                      child: Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(
                          Icons.drag_indicator,
                          size: 16,
                          color: Color(0xFF9AA0AE),
                        ),
                      ),
                    ),
                  ),
                  InkResponse(
                    onTap: onToggle,
                    radius: 12,
                    child: Icon(
                      collapsed ? Icons.chevron_right : Icons.expand_more,
                      size: 18,
                      color: const Color(0xFF5B6272),
                    ),
                  ),
                  const SizedBox(width: 2),
                  SmallIconButton(
                    key: ValueKey('layer-eye-${layer.id}'),
                    icon: layer.visible
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    tooltip: layer.visible ? 'Hide layer' : 'Show layer',
                    onPressed: () =>
                        c.setLayerVisible(layer.id, !layer.visible),
                    color: layer.visible ? null : const Color(0xFFB4B8C2),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: naming
                        ? _LayerNameField(
                            key: ValueKey('layer-name-${layer.id}'),
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
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: layer.visible
                                  ? const Color(0xFF222733)
                                  : const Color(0xFF9AA0AE),
                            ),
                          ),
                  ),
                  if (layer.locked)
                    const Icon(
                      Icons.lock_outline,
                      size: 14,
                      color: Color(0xFF8A90A0),
                    ),
                  Text(
                    '${layer.objects.length}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF8A90A0),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (!collapsed)
          for (final o in layer.objects.reversed)
            _ObjectRow(c: c, layer: layer, object: o),
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
        final n = await promptText(context, 'Rename layer', layer.name);
        if (n != null) c.renameLayer(layer.id, n);
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

class _ObjectRow extends StatelessWidget {
  const _ObjectRow({
    required this.c,
    required this.layer,
    required this.object,
  });
  final EditorController c;
  final Layer layer;
  final SceneObject object;

  @override
  Widget build(BuildContext context) {
    final selected = c.selection.contains(object.id);
    final dim = !object.visible || !layer.visible;
    final row = Container(
      key: ValueKey('object-${object.id}'),
      height: 28,
      margin: const EdgeInsets.only(left: 30, right: 6),
      padding: const EdgeInsets.only(left: 6, right: 2),
      decoration: BoxDecoration(
        color: selected ? kAccent.withValues(alpha: 0.16) : null,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        children: [
          Icon(
            kindIcon(object),
            size: 15,
            color: dim ? const Color(0xFFB4B8C2) : const Color(0xFF5B6272),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              object.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                color: dim ? const Color(0xFF9AA0AE) : const Color(0xFF222733),
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          if (object.locked)
            SmallIconButton(
              key: ValueKey('object-lock-${object.id}'),
              icon: Icons.lock_outline,
              tooltip: 'Locked — click to unlock',
              size: 14,
              color: const Color(0xFF8A90A0),
              onPressed: () {
                c.select([object.id]);
                c.editSelected('unlock', (o) => o.locked = false);
              },
            ),
          SmallIconButton(
            key: ValueKey('object-eye-${object.id}'),
            icon: object.visible
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            tooltip: object.visible ? 'Hide' : 'Show',
            size: 15,
            onPressed: () => c.setObjectVisible(object.id, !object.visible),
            color: object.visible ? null : const Color(0xFFB4B8C2),
          ),
        ],
      ),
    );
    return Draggable<ObjectDrag>(
      data: ObjectDrag(selected ? List.of(c.selection) : [object.id]),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: kAccent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            selected && c.selection.length > 1
                ? '${c.selection.length} objects'
                : object.name,
            style: const TextStyle(color: Colors.white, fontSize: 12),
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
        onDoubleTap: () async {
          final v = await promptText(context, 'Rename', object.name);
          if (v != null) c.renameObject(object.id, v);
        },
        child: row,
      ),
    );
  }
}

/// A new layer's name, open for typing with the old name selected. Enter or
/// clicking elsewhere keeps what was typed; Escape keeps the name it had.
/// Either way the keyboard goes back to the editor's shortcuts.
class _LayerNameField extends StatefulWidget {
  const _LayerNameField({
    super.key,
    required this.initial,
    required this.onDone,
  });
  final String initial;
  final ValueChanged<String?> onDone;

  @override
  State<_LayerNameField> createState() => _LayerNameFieldState();
}

class _LayerNameFieldState extends State<_LayerNameField> {
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
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 6,
            vertical: 6,
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
