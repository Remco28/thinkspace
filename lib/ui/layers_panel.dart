import 'package:flutter/material.dart';

import '../editor/canvas_painter.dart';
import '../editor/canvas_view.dart';
import '../editor/controller.dart';
import '../model/scene.dart';
import 'context_menu.dart';
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
          onSubmitted: (v) => Navigator.pop(ctx, v)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, ctl.text),
            child: const Text('OK')),
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
      ObjectKind.stroke => Icons.draw_outlined,
      ObjectKind.badge => Icons.looks_one_outlined,
    };

class LayersPanel extends StatefulWidget {
  const LayersPanel({super.key, required this.controller});
  final EditorController controller;

  @override
  State<LayersPanel> createState() => _LayersPanelState();
}

class _LayersPanelState extends State<LayersPanel> {
  final Set<String> _collapsed = {};
  EditorController get c => widget.controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final layers = c.doc.layers;
        final n = layers.length;
        return Column(children: [
          PanelHeader('Layers', actions: [
            SmallIconButton(
                icon: Icons.add, tooltip: 'Add layer', onPressed: c.addLayer),
          ]),
          Expanded(
            child: ReorderableListView.builder(
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
                    collapsed: _collapsed.contains(layer.id),
                    onToggle: () {
                      setState(() => _collapsed.contains(layer.id)
                          ? _collapsed.remove(layer.id)
                          : _collapsed.add(layer.id));
                    });
              },
            ),
          ),
        ]);
      },
    );
  }
}

class _LayerTile extends StatelessWidget {
  const _LayerTile(
      {super.key,
      required this.c,
      required this.layer,
      required this.index,
      required this.collapsed,
      required this.onToggle});
  final EditorController c;
  final Layer layer;
  final int index;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final isCurrent = c.currentLayerId == layer.id;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      DragTarget<ObjectDrag>(
        onWillAcceptWithDetails: (_) => true,
        onAcceptWithDetails: (d) => c.moveObjectsToLayer(d.data.ids, layer.id),
        builder: (context, cand, _) => QuickTap(
          key: ValueKey('layer-${layer.id}'),
          onTap: () => c.selectLayerContents(layer.id),
          onDoubleTap: () async {
            final v = await promptText(context, 'Rename layer', layer.name);
            if (v != null) c.renameLayer(layer.id, v);
          },
          onSecondaryTapDown: (d) => _menu(context, d.globalPosition),
          child: Container(
            height: 34,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            padding: const EdgeInsets.only(left: 2, right: 4),
            decoration: BoxDecoration(
              color: cand.isNotEmpty
                  ? kAccent.withValues(alpha: 0.18)
                  : isCurrent
                      ? kAccent.withValues(alpha: 0.09)
                      : null,
              borderRadius: BorderRadius.circular(6),
              border: cand.isNotEmpty ? Border.all(color: kAccent) : null,
            ),
            child: Row(children: [
              ReorderableDragStartListener(
                index: index,
                child: const MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(Icons.drag_indicator,
                            size: 16, color: Color(0xFF9AA0AE)))),
              ),
              InkResponse(
                onTap: onToggle,
                radius: 12,
                child: Icon(collapsed ? Icons.chevron_right : Icons.expand_more,
                    size: 18, color: const Color(0xFF5B6272)),
              ),
              const SizedBox(width: 2),
              SmallIconButton(
                key: ValueKey('layer-eye-${layer.id}'),
                icon: layer.visible
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                tooltip: layer.visible ? 'Hide layer' : 'Show layer',
                onPressed: () => c.setLayerVisible(layer.id, !layer.visible),
                color: layer.visible ? null : const Color(0xFFB4B8C2),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(layer.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: layer.visible
                            ? const Color(0xFF222733)
                            : const Color(0xFF9AA0AE))),
              ),
              if (layer.locked)
                const Icon(Icons.lock_outline,
                    size: 14, color: Color(0xFF8A90A0)),
              Text('${layer.objects.length}',
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFF8A90A0))),
            ]),
          ),
        ),
      ),
      if (!collapsed)
        for (final o in layer.objects.reversed)
          _ObjectRow(c: c, layer: layer, object: o),
    ]);
  }

  void _menu(BuildContext context, Offset at) async {
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: [
        const PopupMenuItem(value: 'rename', child: Text('Rename')),
        const PopupMenuItem(
            value: 'select', child: Text('Select everything on this layer')),
        PopupMenuItem(
            value: 'lock',
            child: Text(layer.locked ? 'Unlock layer' : 'Lock layer')),
        const PopupMenuItem(value: 'delete', child: Text('Delete layer')),
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
  const _ObjectRow(
      {required this.c, required this.layer, required this.object});
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
      child: Row(children: [
        Icon(kindIcon(object),
            size: 15,
            color: dim ? const Color(0xFFB4B8C2) : const Color(0xFF5B6272)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(object.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12.5,
                  color:
                      dim ? const Color(0xFF9AA0AE) : const Color(0xFF222733),
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
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
      ]),
    );
    return Draggable<ObjectDrag>(
      data: ObjectDrag(selected ? List.of(c.selection) : [object.id]),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
              color: kAccent, borderRadius: BorderRadius.circular(6)),
          child: Text(
              selected && c.selection.length > 1
                  ? '${c.selection.length} objects'
                  : object.name,
              style: const TextStyle(color: Colors.white, fontSize: 12)),
        ),
      ),
      child: QuickTap(
        onSecondaryTapDown: (d) {
          if (!c.selection.contains(object.id)) c.select([object.id]);
          showObjectMenu(context, c, d.globalPosition);
        },
        onTap: () {
          final kb = currentModifiers();
          if (!layer.visible || !object.visible) {
            c.select([object.id]);
          } else if (kb.shift || kb.ctrl) {
            c.toggleSelect(object.id);
          } else {
            c.select([object.id]);
          }
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
