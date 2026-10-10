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

DateTime _lastToolTap = DateTime.fromMillisecondsSinceEpoch(0);
Tool? _lastToolTapped;

class TopBar extends StatelessWidget {
  const TopBar(
      {super.key,
      required this.c,
      required this.onMenu,
      required this.fileLabel});
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

  static PopupMenuEntry<MenuAction> _item(
          MenuAction a, String label, String keys) =>
      PopupMenuItem(
        value: a,
        height: 34,
        child: SizedBox(
          width: 250,
          child: Row(children: [
            Expanded(
                child: Text(label, style: const TextStyle(fontSize: 13.5))),
            Text(keys,
                style: const TextStyle(fontSize: 12, color: Color(0xFF8A90A0))),
          ]),
        ),
      );

  static PopupMenuEntry<MenuAction> _check(
          MenuAction a, String label, bool on) =>
      CheckedPopupMenuItem(
        value: a,
        checked: on,
        height: 34,
        child: Text(label, style: const TextStyle(fontSize: 13.5)),
      );

  /// A second click on the same tool within a moment keeps it active.
  void _toolTap(Tool t) {
    final now = DateTime.now();
    final again = _lastToolTapped == t &&
        now.difference(_lastToolTap).inMilliseconds < 400;
    _lastToolTap = now;
    _lastToolTapped = t;
    c.setTool(t, lock: again);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: kBorder))),
        child: Row(children: [
          PopupMenuButton<MenuAction>(
            key: const ValueKey('main-menu'),
            tooltip: 'Menu',
            icon: const Icon(Icons.menu, size: 20),
            onSelected: onMenu,
            itemBuilder: (_) => [
              _item(MenuAction.newDoc, 'New', 'Ctrl+N'),
              _item(MenuAction.open, 'Open…', 'Ctrl+O'),
              _item(MenuAction.save, 'Save', 'Ctrl+S'),
              _item(MenuAction.saveAs, 'Save as…', 'Ctrl+Shift+S'),
              const PopupMenuDivider(height: 8),
              _item(MenuAction.importImage, 'Add image…', 'Ctrl+I'),
              _item(MenuAction.sample, 'Open the storefront sample', ''),
              const PopupMenuDivider(height: 8),
              _item(MenuAction.exportPng, 'Export PNG…', 'Ctrl+E'),
              _item(MenuAction.exportPng2x, 'Export PNG at 2×…', ''),
              _item(MenuAction.copyPage, 'Copy page as image', 'Ctrl+Shift+C'),
              const PopupMenuDivider(height: 8),
              const PopupMenuItem(
                enabled: false,
                height: 26,
                child: Text(
                  'When I paste an image…',
                  style: TextStyle(fontSize: 11.5),
                ),
              ),
              _check(
                  MenuAction.pasteAsk, 'Ask me', c.pasteMode == PasteMode.ask),
              _check(MenuAction.pasteLayer, 'Add to the current layer',
                  c.pasteMode == PasteMode.layer),
              _check(MenuAction.pasteCollection, 'Add to the collection',
                  c.pasteMode == PasteMode.collection),
              const PopupMenuDivider(height: 8),
              _check(MenuAction.autoGrow, 'Grow the page as I add things',
                  c.autoGrow),
              _item(MenuAction.shortcuts, 'Keyboard shortcuts', ''),
            ],
          ),
          const SizedBox(width: 4),
          const Text('Thinkspace',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14.5,
                  letterSpacing: -0.2)),
          const SizedBox(width: 10),
          Flexible(
            child: Text(fileLabel,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7385))),
          ),
          const SizedBox(width: 16),
          for (final t in _tools)
            SmallIconButton(
              key: ValueKey('tool-${t.$1.name}'),
              icon: t.$2,
              tooltip:
                  '${t.$3}  (${t.$4})${t.$1 == Tool.select ? '' : ' — double-click to keep it active'}',
              active: c.tool == t.$1,
              onPressed: () => _toolTap(t.$1),
            ),
          if (c.toolLocked)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Tooltip(
                  message: 'Tool stays active — press Esc to go back to Select',
                  child: Icon(Icons.lock, size: 13, color: kAccent)),
            ),
          _sep(),
          SmallIconButton(
              key: const ValueKey('undo'),
              icon: Icons.undo,
              tooltip: c.undoLabel == null
                  ? 'Undo  Ctrl+Z'
                  : 'Undo ${c.undoLabel}  Ctrl+Z',
              onPressed: c.canUndo ? c.undo : null),
          SmallIconButton(
              key: const ValueKey('redo'),
              icon: Icons.redo,
              tooltip: c.redoLabel == null
                  ? 'Redo  Ctrl+Shift+Z'
                  : 'Redo ${c.redoLabel}  Ctrl+Shift+Z',
              onPressed: c.canRedo ? c.redo : null),
          _sep(),
          SmallIconButton(
              key: const ValueKey('grid'),
              icon: Icons.grid_4x4,
              tooltip: 'Show grid  (G)',
              active: c.showGrid,
              onPressed: c.toggleGrid),
          SmallIconButton(
              key: const ValueKey('snap'),
              icon: Icons.filter_center_focus,
              tooltip: 'Snap to grid  (Shift+G) — hold Ctrl to place freely',
              active: c.snapOn,
              onPressed: c.toggleSnap),
          const Spacer(),
          SmallIconButton(
              icon: Icons.content_copy,
              tooltip: 'Copy the page as an image',
              onPressed: () => onMenu(MenuAction.copyPage)),
          SmallIconButton(
              key: const ValueKey('export'),
              icon: Icons.ios_share,
              tooltip: 'Export PNG  Ctrl+E',
              onPressed: () => onMenu(MenuAction.exportPng)),
        ]),
      ),
    );
  }

  Widget _sep() => Container(
      width: 1,
      height: 22,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: kBorder);
}
