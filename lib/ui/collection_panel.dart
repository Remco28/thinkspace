import 'package:flutter/material.dart';

import '../editor/canvas_view.dart';
import '../editor/controller.dart';
import '../io/files.dart';
import '../model/scene.dart';
import 'layers_panel.dart';
import 'widgets.dart';

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
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'Keep images here until you need them.\n\nPaste (Ctrl+V) and choose “Add to collection”, or drag a file in. Drag an item onto the page to use it — the original stays here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: Color(0xFF6B7385),
                          ),
                        ),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, box) {
                        final cols = (box.maxWidth / 112).floor().clamp(1, 6);
                        return GridView.builder(
                          padding: const EdgeInsets.all(8),
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
    final image = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: kBorder),
      ),
      padding: const EdgeInsets.all(4),
      child: a == null
          ? const Icon(Icons.broken_image_outlined)
          : RawImage(
              image: a.image,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
    );
    return Draggable<CollectionDrag>(
      data: CollectionDrag(item.id),
      dragAnchorStrategy: pointerDragAnchorStrategy,
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
  }

  Widget _body(BuildContext context, Widget image) => QuickTap(
    key: ValueKey('collection-${item.id}'),
    onTap: () {},
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
        items: const [
          PopupMenuItem(value: 'place', child: Text('Place on page')),
          PopupMenuItem(value: 'rename', child: Text('Rename')),
          PopupMenuItem(value: 'remove', child: Text('Remove from collection')),
        ],
      );
      if (!context.mounted) return;
      switch (v) {
        case 'place':
          c.placeCollectionItem(item.id);
        case 'rename':
          final n = await promptText(context, 'Rename', item.name);
          if (n != null) c.renameCollectionItem(item.id, n);
        case 'remove':
          c.removeFromCollection(item.id);
      }
    },
    child: Tooltip(
      message: 'Drag onto the page, or double-click to place',
      waitDuration: const Duration(milliseconds: 700),
      child: Column(
        children: [
          Expanded(child: image),
          const SizedBox(height: 3),
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5),
          ),
        ],
      ),
    ),
  );
}
