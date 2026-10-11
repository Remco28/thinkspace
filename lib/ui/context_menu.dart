import 'package:flutter/material.dart';

import '../editor/controller.dart';
import '../model/scene.dart';
import 'menus.dart';

enum _Act {
  copy,
  cut,
  duplicate,
  delete,
  front,
  back,
  lock,
  cutout,
  removeBg,
  keep,
  merge,
  unmerge,
  paste,
  selectAll,
  fit,
}

/// The right-click menu: what you can do with the thing under the pointer.
Future<void> showObjectMenu(
  BuildContext context,
  EditorController c,
  Offset global,
) async {
  final sel = c.selectedObjects;
  final one = c.single;
  final others = c.doc.layers
      .where(
        (l) =>
            sel.isNotEmpty && sel.any((o) => c.doc.layerOf(o.id)?.id != l.id),
      )
      .toList()
      .reversed
      .toList();
  const w = 220.0;
  final items = <PopupMenuEntry<Object>>[
    if (sel.isNotEmpty) ...[
      menuItem(
        value: _Act.copy,
        label: 'Copy',
        icon: Icons.content_copy,
        shortcut: 'Ctrl+C',
        width: w,
      ),
      menuItem(
        value: _Act.cut,
        label: 'Cut',
        icon: Icons.content_cut,
        shortcut: 'Ctrl+X',
        width: w,
      ),
      menuItem(
        value: _Act.duplicate,
        label: 'Duplicate',
        icon: Icons.copy_all_outlined,
        shortcut: 'Ctrl+D',
        width: w,
      ),
      menuItem(
        value: _Act.delete,
        label: 'Delete',
        icon: Icons.delete_outline,
        shortcut: 'Del',
        danger: true,
        width: w,
      ),
      menuDivider(),
      menuItem(
        value: _Act.front,
        label: 'Bring to front',
        icon: Icons.flip_to_front,
        shortcut: 'Ctrl+Shift+]',
        width: w,
      ),
      menuItem(
        value: _Act.back,
        label: 'Send to back',
        icon: Icons.flip_to_back,
        shortcut: 'Ctrl+Shift+[',
        width: w,
      ),
      if (others.isNotEmpty) ...[
        menuDivider(),
        menuLabel('Move to layer', width: w),
        for (final l in others)
          menuItem(
            value: l.id,
            label: l.name,
            icon: Icons.layers_outlined,
            width: w,
          ),
      ],
      menuDivider(),
      if (one is ImageObject) ...[
        menuItem(
          value: _Act.cutout,
          label: 'Cut out…',
          icon: Icons.content_cut,
          width: w,
        ),
        menuItem(
          value: _Act.removeBg,
          label: 'Remove background',
          icon: Icons.auto_fix_high,
          width: w,
        ),
        menuItem(
          value: _Act.keep,
          label: 'Keep in collection',
          icon: Icons.collections_outlined,
          width: w,
        ),
      ],
      if (c.canUnmerge)
        menuItem(
          value: _Act.unmerge,
          label: 'Unmerge into the original pieces',
          icon: Icons.call_split,
          shortcut: 'U',
          width: w,
        )
      else
        menuItem(
          value: _Act.merge,
          label: sel.length > 1 ? 'Merge into one image' : 'Turn into an image',
          icon: Icons.layers_clear_outlined,
          shortcut: 'M',
          width: w,
        ),
      menuItem(
        value: _Act.lock,
        label: sel.every((o) => o.locked) ? 'Unlock' : 'Lock in place',
        icon: sel.every((o) => o.locked)
            ? Icons.lock_open_outlined
            : Icons.lock_outline,
        width: w,
      ),
    ] else ...[
      menuItem(
        value: _Act.paste,
        label: 'Paste',
        icon: Icons.content_paste,
        shortcut: 'Ctrl+V',
        width: w,
      ),
      menuItem(
        value: _Act.selectAll,
        label: 'Select everything',
        icon: Icons.select_all,
        shortcut: 'Ctrl+A',
        width: w,
      ),
      menuItem(
        value: _Act.fit,
        label: 'Fit the page in view',
        icon: Icons.fit_screen_outlined,
        shortcut: 'F',
        width: w,
      ),
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
    case _Act.unmerge:
      c.unmerge();
    case _Act.paste:
      await c.paste();
    case _Act.selectAll:
      c.selectAll();
    case _Act.fit:
      c.fitToView();
  }
}
