import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../editor/canvas_view.dart';
import '../editor/controller.dart';
import '../io/files.dart';
import '../model/scene.dart';
import 'menus.dart';
import 'widgets.dart';
import 'design.dart';

class CollectionPanel extends StatelessWidget {
  const CollectionPanel({super.key, required this.controller});
  final EditorController controller;
  EditorController get c => controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final items = c.doc.collection;
        return Column(
          children: [
            PanelHeader(
              'Collection',
              actions: [
                SmallIconButton(
                  key: const ValueKey('collection-import'),
                  icon: Icons.add_photo_alternate_outlined,
                  tooltip: 'Add images to the collection',
                  onPressed: () async {
                    final paths = await pickImages();
                    if (paths.isNotEmpty) {
                      await c.importFiles(paths, toCollection: true);
                    }
                  },
                ),
                SmallIconButton(
                  icon: Icons.content_paste,
                  tooltip: 'Paste an image into the collection',
                  onPressed: () => c.pasteToCollection(),
                ),
              ],
            ),
            Expanded(
              child: items.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(kSpace20),
                        child: Text(
                          'Keep images here until you need them.\n\nPaste (Ctrl+V) and choose “Add to collection”, or drag a file in. Drag an item onto the page to use it — the original stays here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: kTextBody,
                            height: 1.4,
                            color: kInkSoft,
                          ),
                        ),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, box) {
                        final cols = (box.maxWidth / 112).floor().clamp(1, 6);
                        return GridView.builder(
                          padding: const EdgeInsets.all(kSpace8),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: cols,
                                mainAxisSpacing: 8,
                                crossAxisSpacing: 8,
                                childAspectRatio: 0.86,
                              ),
                          itemCount: items.length,
                          itemBuilder: (context, i) =>
                              _Thumb(c: c, item: items[i]),
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

class _Thumb extends StatelessWidget {
  const _Thumb({required this.c, required this.item});
  final EditorController c;
  final CollectionItem item;

  @override
  Widget build(BuildContext context) {
    final a = c.assets[item.assetId];
    final chosen = c.selectedCollectionId == item.id;
    final image = Container(
      decoration: BoxDecoration(
        color: chosen ? kAccent.withValues(alpha: 0.08) : Colors.white,
        borderRadius: BorderRadius.circular(kRadius),
        border: Border.all(
          color: chosen ? kAccent : kBorder,
          width: chosen ? 2 : 1,
        ),
      ),
      padding: const EdgeInsets.all(kSpace4),
      child: a == null
          ? const Icon(Icons.broken_image_outlined)
          : RawImage(
              image: a.image,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
    );
    final drag = Draggable<CollectionDrag>(
      data: CollectionDrag(item.id),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () => c.selectCollectionItem(item.id),
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.85,
          child: SizedBox(width: 96, height: 80, child: image),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.5, child: _body(context, image)),
      child: _body(context, image),
    );
    // Dropping another item here rearranges the shelf; a bar on the side it
    // will land shows where.
    return DragTarget<CollectionDrag>(
      onWillAcceptWithDetails: (d) => d.data.itemId != item.id,
      onAcceptWithDetails: (d) => c.moveCollectionItem(d.data.itemId, item.id),
      builder: (context, hovering, _) {
        if (hovering.isEmpty) return drag;
        final items = c.doc.collection;
        final from = items.indexWhere((x) => x.id == hovering.first!.itemId);
        final to = items.indexWhere((x) => x.id == item.id);
        final after = from >= 0 && from < to;
        return Stack(
          children: [
            Positioned.fill(child: drag),
            Positioned(
              left: after ? null : -5,
              right: after ? -5 : null,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(
                  key: const ValueKey('collection-drop-bar'),
                  width: 3,
                  decoration: BoxDecoration(
                    color: kAccent,
                    borderRadius: BorderRadius.circular(kRadius),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _body(BuildContext context, Widget image) => QuickTap(
    key: ValueKey('collection-${item.id}'),
    onTap: () => c.selectCollectionItem(item.id),
    onDoubleTap: () => c.placeCollectionItem(item.id),
    onSecondaryTapDown: (d) async {
      final v = await showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(
          d.globalPosition.dx,
          d.globalPosition.dy,
          d.globalPosition.dx,
          d.globalPosition.dy,
        ),
        items: [
          menuItem(
            value: 'place',
            label: 'Place on page',
            icon: Icons.add_photo_alternate_outlined,
            shortcut: 'Enter',
            width: 210,
          ),
          menuItem(
            value: 'rename',
            label: 'Rename',
            icon: Icons.drive_file_rename_outline,
            shortcut: 'F2',
            width: 210,
          ),
          menuDivider(),
          menuItem(
            value: 'remove',
            label: 'Remove from collection',
            icon: Icons.delete_outline,
            shortcut: 'Del',
            danger: true,
            width: 210,
          ),
        ],
      );
      if (!context.mounted) return;
      switch (v) {
        case 'place':
          c.placeCollectionItem(item.id);
        case 'rename':
          c.beginCollectionRename(item.id);
        case 'remove':
          c.removeFromCollection(item.id);
      }
    },
    child: Tooltip(
      message:
          'Drag onto the page, or double-click to place. Drag onto another to rearrange. F2 renames.',
      waitDuration: kTooltipWait,
      child: Column(
        children: [
          Expanded(child: image),
          const SizedBox(height: kSpace4),
          if (c.renamingCollectionId == item.id)
            _NameField(
              key: ValueKey('rename-${item.id}'),
              initial: item.name,
              onDone: c.finishCollectionRename,
            )
          else
            Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: kTextCaption,
                fontWeight: c.selectedCollectionId == item.id
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
        ],
      ),
    ),
  );
}

/// The tile's name, editable in place: Enter keeps it, Esc leaves it alone,
/// and clicking elsewhere keeps what was typed. Keyboard focus then returns to
/// the editor so the one-key shortcuts work straight away.
class _NameField extends StatefulWidget {
  const _NameField({super.key, required this.initial, required this.onDone});
  final String initial;
  final void Function(String? name) onDone;

  @override
  State<_NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<_NameField> {
  late final TextEditingController _text;
  final FocusNode _focus = FocusNode();
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.initial);
    _text.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  void _finish(String? name) {
    if (_done) return;
    _done = true;
    final editor = Focus.maybeOf(context);
    widget.onDone(name);
    editor?.requestFocus();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: kSpace20,
    child: Focus(
      onKeyEvent: (node, e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
          _finish(null);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TextField(
        key: const ValueKey('collection-rename'),
        controller: _text,
        focusNode: _focus,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: kTextCaption),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(
            vertical: kSpace2,
            horizontal: kSpace2,
          ),
          border: OutlineInputBorder(),
        ),
        onSubmitted: _finish,
        onTapOutside: (_) => _finish(_text.text),
      ),
    ),
  );
}
