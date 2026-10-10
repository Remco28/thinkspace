import 'package:flutter/material.dart';

import '../editor/controller.dart';
import '../model/scene.dart';

enum _Act { copy, cut, duplicate, delete, front, back, lock, cutout, removeBg, keep, merge, paste, selectAll, fit }

/// The right-click menu: what you can do with the thing under the pointer.
Future<void> showObjectMenu(BuildContext context, EditorController c, Offset global) async {
  final sel = c.selectedObjects;
  final one = c.single;
  final others = c.doc.layers.where((l) => sel.isNotEmpty && sel.any((o) => c.doc.layerOf(o.id)?.id != l.id)).toList().reversed.toList();
  final items = <PopupMenuEntry<Object>>[
    if (sel.isNotEmpty) ...[
      const PopupMenuItem(value: _Act.copy, child: Text('Copy')),
      const PopupMenuItem(value: _Act.cut, child: Text('Cut')),
      const PopupMenuItem(value: _Act.duplicate, child: Text('Duplicate')),
      const PopupMenuItem(value: _Act.delete, child: Text('Delete')),
      const PopupMenuDivider(),
      const PopupMenuItem(value: _Act.front, child: Text('Bring to front')),
      const PopupMenuItem(value: _Act.back, child: Text('Send to back')),
      for (final l in others) PopupMenuItem(value: l.id, child: Text('Move to “${l.name}”')),
      const PopupMenuDivider(),
      if (one is ImageObject) ...[
        const PopupMenuItem(value: _Act.cutout, child: Text('Cut out…')),
        const PopupMenuItem(value: _Act.removeBg, child: Text('Remove background')),
        const PopupMenuItem(value: _Act.keep, child: Text('Keep in collection')),
      ],
      PopupMenuItem(value: _Act.merge, child: Text(sel.length > 1 ? 'Merge into one image' : 'Turn into an image')),
      PopupMenuItem(value: _Act.lock, child: Text(sel.every((o) => o.locked) ? 'Unlock' : 'Lock in place')),
    ] else ...[
      const PopupMenuItem(value: _Act.paste, child: Text('Paste')),
      const PopupMenuItem(value: _Act.selectAll, child: Text('Select everything')),
      const PopupMenuItem(value: _Act.fit, child: Text('Fit the page in view')),
    ],
  ];
  final v = await showMenu<Object>(
    context: context,
    position: RelativeRect.fromLTRB(global.dx, global.dy, global.dx, global.dy),
    items: items,
  );
  if (v == null) return;
  if (v is String) {
    c.moveObjectsToLayer(sel.map((o) => o.id).toList(), v);
    return;
  }
  switch (v as _Act) {
    case _Act.copy:
      c.copySelection();
    case _Act.cut:
      c.cutSelection();
    case _Act.duplicate:
      c.duplicateSelection();
    case _Act.delete:
      c.deleteSelection();
    case _Act.front:
      c.reorderSelection('front');
    case _Act.back:
      c.reorderSelection('back');
    case _Act.lock:
      final lock = !sel.every((o) => o.locked);
      c.editSelected(lock ? 'lock' : 'unlock', (o) => o.locked = lock);
    case _Act.cutout:
      c.setTool(Tool.cutout);
    case _Act.removeBg:
      if (one is ImageObject) await c.removeBackgroundFrom(one);
    case _Act.keep:
      c.sendSelectionToCollection();
    case _Act.merge:
      await c.flattenSelection();
    case _Act.paste:
      await c.paste();
    case _Act.selectAll:
      c.selectAll();
    case _Act.fit:
      c.fitToView();
  }
}
