import 'package:flutter/material.dart';

import '../editor/canvas_painter.dart';
import '../editor/controller.dart';
import 'widgets.dart';

enum MenuAction {
  newDoc,
  open,
  save,
  saveAs,
  importImage,
  sample,
  exportPng,
  exportPng2x,
  copyPage,
  pasteAsk,
  pasteLayer,
  pasteCollection,
  autoGrow,
  shortcuts,
}

class TopBar extends StatelessWidget {
  const TopBar({super.key, required this.c, required this.onMenu, required this.fileLabel});
  final EditorController c;
  final void Function(MenuAction) onMenu;
  final String fileLabel;

  static const _tools = <(Tool, IconData, String, String)>[
    (Tool.select, Icons.near_me_outlined, 'Select & move', 'V'),
    (Tool.line, Icons.show_chart, 'Straight line', 'L'),
    (Tool.arrow, Icons.north_east, 'Arrow', 'A'),
    (Tool.rect, Icons.crop_square, 'Rectangle', 'R'),
    (Tool.ellipse, Icons.circle_outlined, 'Ellipse', 'E'),
    (Tool.text, Icons.title, 'Text', 'T'),
    (Tool.pen, Icons.draw_outlined, 'Pen', 'P'),
    (Tool.cutout, Icons.content_cut, 'Cut out', 'C'),
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: kBorder))),
        child: Row(children: [
          PopupMenuButton<MenuAction>(
            key: const ValueKey('main-menu'),
            tooltip: 'Menu',
            icon: const Icon(Icons.menu, size: 20),
            onSelected: onMenu,
            itemBuilder: (_) => [
              const PopupMenuItem(value: MenuAction.newDoc, child: Text('New')),
              const PopupMenuItem(value: MenuAction.open, child: Text('Open…            Ctrl+O')),
              const PopupMenuItem(value: MenuAction.save, child: Text('Save              Ctrl+S')),
              const PopupMenuItem(value: MenuAction.saveAs, child: Text('Save as…   Ctrl+Shift+S')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: MenuAction.importImage, child: Text('Add image…       Ctrl+I')),
              const PopupMenuItem(value: MenuAction.sample, child: Text('Open the storefront sample')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: MenuAction.exportPng, child: Text('Export PNG…       Ctrl+E')),
              const PopupMenuItem(value: MenuAction.exportPng2x, child: Text('Export PNG at 2×…')),
              const PopupMenuItem(value: MenuAction.copyPage, child: Text('Copy page as image   Ctrl+Shift+C')),
              const PopupMenuDivider(),
              const PopupMenuItem(enabled: false, height: 28, child: Text('When I paste an image…', style: TextStyle(fontSize: 11.5))),
              CheckedPopupMenuItem(value: MenuAction.pasteAsk, checked: c.pasteMode == PasteMode.ask, child: const Text('Ask me')),
              CheckedPopupMenuItem(value: MenuAction.pasteLayer, checked: c.pasteMode == PasteMode.layer, child: const Text('Add to the current layer')),
              CheckedPopupMenuItem(value: MenuAction.pasteCollection, checked: c.pasteMode == PasteMode.collection, child: const Text('Add to the collection')),
              const PopupMenuDivider(),
              CheckedPopupMenuItem(value: MenuAction.autoGrow, checked: c.autoGrow, child: const Text('Grow the page as I add things')),
              const PopupMenuItem(value: MenuAction.shortcuts, child: Text('Keyboard shortcuts')),
            ],
          ),
          const SizedBox(width: 4),
          const Text('Thinkspace', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, letterSpacing: -0.2)),
          const SizedBox(width: 10),
          Flexible(
            child: Text(fileLabel, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7385))),
          ),
          const SizedBox(width: 16),
          for (final t in _tools)
            GestureDetector(
              onDoubleTap: () => c.setTool(t.$1, lock: true),
              child: SmallIconButton(
                key: ValueKey('tool-${t.$1.name}'),
                icon: t.$2,
                tooltip: '${t.$3}  (${t.$4})${t.$1 == Tool.select ? '' : ' — double-click to keep it active'}',
                active: c.tool == t.$1,
                onPressed: () => c.setTool(t.$1),
              ),
            ),
          if (c.toolLocked)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Tooltip(message: 'Tool stays active — press Esc to go back to Select', child: Icon(Icons.lock, size: 13, color: kAccent)),
            ),
          _sep(),
          SmallIconButton(key: const ValueKey('undo'), icon: Icons.undo, tooltip: 'Undo  Ctrl+Z', onPressed: c.canUndo ? c.undo : null),
          SmallIconButton(key: const ValueKey('redo'), icon: Icons.redo, tooltip: 'Redo  Ctrl+Shift+Z', onPressed: c.canRedo ? c.redo : null),
          _sep(),
          SmallIconButton(key: const ValueKey('grid'), icon: Icons.grid_4x4, tooltip: 'Show grid  (G)', active: c.showGrid, onPressed: c.toggleGrid),
          SmallIconButton(key: const ValueKey('snap'), icon: Icons.filter_center_focus, tooltip: 'Snap to grid  (Shift+G) — hold Ctrl to place freely', active: c.snapOn, onPressed: c.toggleSnap),
          const Spacer(),
          SmallIconButton(icon: Icons.content_copy, tooltip: 'Copy the page as an image', onPressed: () => onMenu(MenuAction.copyPage)),
          SmallIconButton(key: const ValueKey('export'), icon: Icons.ios_share, tooltip: 'Export PNG  Ctrl+E', onPressed: () => onMenu(MenuAction.exportPng)),
        ]),
      ),
    );
  }

  Widget _sep() => Container(width: 1, height: 22, margin: const EdgeInsets.symmetric(horizontal: 8), color: kBorder);
}

