import 'package:flutter/material.dart';

import '../editor/controller.dart';
import '../io/files.dart';
import 'menus.dart';
import 'widgets.dart';
import 'design.dart';

enum MenuAction {
  newDoc,
  open,
  openRecent,
  save,
  saveAs,
  importImage,
  exportPng,
  exportPng2x,
  copyPage,
  pasteAsk,
  pasteLayer,
  pasteCollection,
  autoGrow,
  fullscreen,
  shortcuts,
}

DateTime _lastToolTap = DateTime.fromMillisecondsSinceEpoch(0);
Tool? _lastToolTapped;

/// Height of the top bar; the page below starts here.
const double kTopBarHeight = 46;

/// Where the tools start: past the Collection panel at its usual width (270,
/// plus its divider) and the button that hides it, so the active tool's
/// keycap hangs over open page area.
const double kToolsLeft = 320;

class TopBar extends StatelessWidget {
  const TopBar({
    super.key,
    required this.c,
    required this.onMenu,
    this.fullscreen = false,
  });
  final EditorController c;
  final void Function(MenuAction) onMenu;
  final bool fullscreen;

  /// The tools in groups by what they are for: pointing at things, labels,
  /// freehand marks, and working on pictures, with the same divider between
  /// groups as between the tools and undo. A tool without a key is used too
  /// rarely to need one.
  static const _toolGroups = <List<(Tool, IconData, String, String?)>>[
    [(Tool.select, Icons.near_me_outlined, 'Select & move', 'V')],
    [
      (Tool.arrow, Icons.north_east, 'Arrow', 'A'),
      (Tool.line, Icons.horizontal_rule, 'Straight line', 'L'),
      (Tool.rect, Icons.crop_square, 'Rectangle', 'R'),
      (Tool.ellipse, Icons.circle_outlined, 'Ellipse', 'E'),
    ],
    [
      (Tool.text, Icons.title, 'Text', 'T'),
      (Tool.badge, Icons.looks_one_outlined, 'Numbered marker', 'N'),
    ],
    [
      (Tool.pen, Icons.edit_outlined, 'Pen', 'P'),
      (Tool.highlight, Icons.border_color_outlined, 'Highlighter', 'H'),
      (Tool.remove, Icons.clear, 'Remove marks', 'X'),
    ],
    [
      (Tool.cutout, Icons.content_cut, 'Cut out', 'C'),
      (Tool.hide, Icons.grid_on, 'Hide details', null),
    ],
  ];

  static PopupMenuEntry<MenuAction> _item(
    MenuAction a,
    String label,
    String keys, {
    IconData? icon,
  }) =>
      menuItem(value: a, label: label, icon: icon, shortcut: keys, width: 250);

  static PopupMenuEntry<MenuAction> _check(
    MenuAction a,
    String label,
    bool on,
  ) => menuItem(value: a, label: label, checked: on, width: 250);

  /// A second click on the same tool within a moment keeps it active.
  void _toolTap(Tool t) {
    final now = DateTime.now();
    final again =
        _lastToolTapped == t &&
        now.difference(_lastToolTap).inMilliseconds < 400;
    _lastToolTap = now;
    _lastToolTapped = t;
    c.setTool(t, lock: again);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => LayoutBuilder(
        builder: (context, box) => Container(
          height: kTopBarHeight,
          padding: const EdgeInsets.symmetric(horizontal: kSpace8),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: kBorder)),
          ),
          child: Row(
            children: [
              // The menu, the name and the file name take a fixed width, so the
              // tools start just past the Collection panel at its usual width
              // and the active tool's keycap hangs over the page area.
              SizedBox(
                width: _leadWidth(box.maxWidth),
                child: Row(
                  children: [
                    PopupMenuButton<MenuAction>(
                      key: const ValueKey('main-menu'),
                      tooltip: 'Menu',
                      icon: const Icon(Icons.menu, size: kIconLarge),
                      onSelected: onMenu,
                      position: PopupMenuPosition.under,
                      offset: const Offset(0, 4),
                      itemBuilder: (_) => [
                        _item(
                          MenuAction.newDoc,
                          'New',
                          'Ctrl+N',
                          icon: Icons.note_add_outlined,
                        ),
                        _item(
                          MenuAction.open,
                          'Open…',
                          'Ctrl+O',
                          icon: Icons.folder_open_outlined,
                        ),
                        menuItem(
                          value: MenuAction.openRecent,
                          label: 'Open recent',
                          icon: Icons.history,
                          shortcut: c.recentFiles.isEmpty ? '' : '›',
                          enabled: c.recentFiles.isNotEmpty,
                          width: 250,
                        ),
                        _item(
                          MenuAction.save,
                          'Save',
                          'Ctrl+S',
                          icon: Icons.save_outlined,
                        ),
                        _item(
                          MenuAction.saveAs,
                          'Save as…',
                          'Ctrl+Shift+S',
                          icon: Icons.save_as_outlined,
                        ),
                        menuDivider(),
                        _item(
                          MenuAction.importImage,
                          'Add image…',
                          'Ctrl+I',
                          icon: Icons.add_photo_alternate_outlined,
                        ),
                        menuDivider(),
                        _item(
                          MenuAction.exportPng,
                          'Export PNG…',
                          'Ctrl+E',
                          icon: Icons.ios_share,
                        ),
                        _item(
                          MenuAction.exportPng2x,
                          'Export PNG at 2×…',
                          '',
                          icon: Icons.high_quality_outlined,
                        ),
                        _item(
                          MenuAction.copyPage,
                          'Copy page as image',
                          'Ctrl+Shift+C',
                          icon: Icons.content_copy,
                        ),
                        menuDivider(),
                        menuLabel('When I paste an image', width: 250),
                        _check(
                          MenuAction.pasteAsk,
                          'Ask me',
                          c.pasteMode == PasteMode.ask,
                        ),
                        _check(
                          MenuAction.pasteLayer,
                          'Add to the current layer',
                          c.pasteMode == PasteMode.layer,
                        ),
                        _check(
                          MenuAction.pasteCollection,
                          'Add to the collection',
                          c.pasteMode == PasteMode.collection,
                        ),
                        menuDivider(),
                        _check(
                          MenuAction.autoGrow,
                          'Grow the page as I add things',
                          c.autoGrow,
                        ),
                        menuDivider(),
                        _item(
                          MenuAction.fullscreen,
                          fullscreen ? 'Leave full screen' : 'Full screen',
                          'F11',
                          icon: fullscreen
                              ? Icons.fullscreen_exit
                              : Icons.fullscreen,
                        ),
                        _item(
                          MenuAction.shortcuts,
                          'Keyboard shortcuts',
                          '?',
                          icon: Icons.keyboard_outlined,
                        ),
                      ],
                    ),
                    const SizedBox(width: kSpace4),
                    const Text(
                      'Thinkspace',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: kTextTitle,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(width: kSpace12),
                    Flexible(
                      child: Text(
                        '${c.filePath == null ? 'Untitled' : baseName(c.filePath!)}${c.dirty ? ' •' : ''}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: kTextBody,
                          color: kInkSoft,
                        ),
                      ),
                    ),
                    const SizedBox(width: kSpace16),
                  ],
                ),
              ),
              for (final (i, group) in _toolGroups.indexed) ...[
                if (i > 0) _sep(),
                for (final t in group) _toolButton(t),
              ],
              if (c.toolLocked)
                const Padding(
                  padding: EdgeInsets.only(left: kSpace4),
                  child: Tooltip(
                    message:
                        'Tool stays active — press Esc to go back to Select',
                    child: Icon(Icons.lock, size: kIconSmall, color: kAccent),
                  ),
                ),
              _sep(),
              SmallIconButton(
                key: const ValueKey('undo'),
                icon: Icons.undo,
                tooltip: c.undoLabel == null
                    ? 'Undo  Ctrl+Z'
                    : 'Undo ${c.undoLabel}  Ctrl+Z',
                onPressed: c.canUndo ? c.undo : null,
              ),
              SmallIconButton(
                key: const ValueKey('redo'),
                icon: Icons.redo,
                tooltip: c.redoLabel == null
                    ? 'Redo  Ctrl+Shift+Z'
                    : 'Redo ${c.redoLabel}  Ctrl+Shift+Z',
                onPressed: c.canRedo ? c.redo : null,
              ),
              _sep(),
              SmallIconButton(
                key: const ValueKey('grid'),
                icon: Icons.grid_4x4,
                tooltip: 'Show grid  (G)',
                active: c.showGrid,
                onPressed: c.toggleGrid,
              ),
              SmallIconButton(
                key: const ValueKey('snap'),
                icon: Icons.filter_center_focus,
                tooltip: 'Snap to grid  (Shift+G) — hold Ctrl to place freely',
                active: c.snapOn,
                onPressed: c.toggleSnap,
              ),
              const Spacer(),
              SmallIconButton(
                icon: Icons.content_copy,
                tooltip: 'Copy the page as an image',
                onPressed: () => onMenu(MenuAction.copyPage),
              ),
              SmallIconButton(
                key: const ValueKey('export'),
                icon: Icons.ios_share,
                tooltip: 'Export PNG  Ctrl+E',
                onPressed: () => onMenu(MenuAction.exportPng),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolButton((Tool, IconData, String, String?) t) {
    final (tool, icon, label, key) = t;
    final name = key == null ? label : '$label  ($key)';
    return Stack(
      clipBehavior: Clip.none,
      children: [
        SmallIconButton(
          key: ValueKey('tool-${tool.name}'),
          icon: icon,
          glyph: switch (tool) {
            Tool.line => LineGlyph.new,
            Tool.highlight => HighlighterGlyph.new,
            Tool.remove => RemoveMarksGlyph.new,
            Tool.hide => HideDetailsGlyph.new,
            _ => null,
          },
          tooltip: switch (tool) {
            Tool.select => name,
            Tool.remove =>
              '$name — drag across pen marks, lines and shapes to remove them. Images and text stay.',
            Tool.hide =>
              '$name — drag a box over names, passwords or numbers to pixelate them. Double-click to keep it active',
            _ => '$name — double-click to keep it active',
          },
          active: c.tool == tool,
          onPressed: () => _toolTap(tool),
        ),
        // The active tool shows its key as a little keycap hanging over the
        // bar's lower edge, so the shortcuts get learned without anyone
        // reading a list and the row stays level.
        if (c.tool == tool && key != null)
          Positioned(
            left: -8,
            right: -8,
            top: 30,
            child: IgnorePointer(
              child: Center(
                child: KeyCap(
                  key,
                  key: ValueKey('tool-key-${tool.name}'),
                  compact: true,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Everything right of the name: every button is a control's width, every
  /// divider 1 px plus its margins, and the padding at both ends.
  double get _toolsWidth {
    final buttons =
        _toolGroups.fold<int>(0, (n, g) => n + g.length) + 6; // + undo, redo,
    // grid, snap, copy and export
    final dividers = _toolGroups.length - 1 + 2;
    return buttons * kControlHeight +
        dividers * (1 + 2 * kSpace8) +
        (c.toolLocked ? kIconSmall + kSpace4 : 0) +
        2 * kSpace8;
  }

  /// The menu, name and file name: as wide as [kToolsLeft] asks when the
  /// window has room, narrower (the file name shortening) when it does not.
  double _leadWidth(double window) =>
      (window - _toolsWidth - kSpace8).clamp(150.0, kToolsLeft - kSpace8);

  Widget _sep() => Container(
    width: 1,
    height: 22,
    margin: const EdgeInsets.symmetric(horizontal: kSpace8),
    color: kBorder,
  );
}
