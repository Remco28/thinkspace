import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../editor/canvas_painter.dart' show kAccent;
import '../editor/controller.dart';
import '../editor/image_ops.dart' show HoleFill;
import '../model/scene.dart';
import 'kit.dart';
import 'widgets.dart';

/// The cut-out tool's options, asked in the order the decisions are made:
/// what to select, what happens to the original, what is left behind. It
/// opens in the middle of the page so it cannot be missed; Start (or just
/// beginning to draw) puts it away.
class CutoutCard extends StatelessWidget {
  const CutoutCard({super.key, required this.c});
  final EditorController c;

  void _start() {
    c.cutoutOptionsOpen = false;
    c.notify();
  }

  @override
  Widget build(BuildContext context) {
    final wand = c.cutoutMode == CutoutMode.wand;
    return Material(
      key: const ValueKey('cutout-card'),
      color: Colors.white,
      elevation: 12,
      shadowColor: const Color(0x55000000),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 332,
        constraints: BoxConstraints(
          maxHeight: math.max(200, MediaQuery.sizeOf(context).height - 120),
        ),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kBorder),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.content_cut, size: 18, color: kAccent),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Cut out',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  SmallIconButton(
                    icon: Icons.close,
                    tooltip: 'Cancel  Esc',
                    onPressed: () => c.setTool(Tool.select),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _Question(
                '1',
                'What do you want to select?',
                children: [
                  _Choice(
                    key: const ValueKey('cut-mode-lasso'),
                    icon: Icons.gesture,
                    title: 'Draw around it',
                    note: 'Trace the part with the mouse',
                    selected: c.cutoutMode == CutoutMode.lasso,
                    onTap: () => _mode(CutoutMode.lasso),
                  ),
                  _Choice(
                    key: const ValueKey('cut-mode-box'),
                    icon: Icons.crop_din,
                    title: 'Draw a box',
                    note: 'Drag a rectangle over the part',
                    selected: c.cutoutMode == CutoutMode.box,
                    onTap: () => _mode(CutoutMode.box),
                  ),
                  _Choice(
                    key: const ValueKey('cut-mode-wand'),
                    icon: Icons.colorize,
                    title: 'Pick a colour',
                    note: 'Click a colour to make it see-through',
                    selected: wand,
                    onTap: () => _mode(CutoutMode.wand),
                  ),
                ],
              ),
              if (wand)
                _Question(
                  '2',
                  'How alike must the colours be?',
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Less',
                          style: TextStyle(fontSize: 12, color: kMuted),
                        ),
                        Expanded(
                          child: Slider(
                            key: const ValueKey('cut-match'),
                            value: c.wandTolerance,
                            min: 0.02,
                            max: 0.5,
                            onChanged: (v) {
                              c.wandTolerance = v;
                              c.notify();
                            },
                          ),
                        ),
                        const Text(
                          'More',
                          style: TextStyle(fontSize: 12, color: kMuted),
                        ),
                      ],
                    ),
                    SwitchRow(
                      key: const ValueKey('cut-touching'),
                      label: 'Only the part I click',
                      hint: 'Off clears that colour everywhere in the picture.',
                      value: c.wandContiguous,
                      onChanged: (v) {
                        c.wandContiguous = v;
                        c.notify();
                      },
                    ),
                  ],
                )
              else ...[
                _Question(
                  '2',
                  'What happens to the original?',
                  children: [
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _Choice(
                              key: const ValueKey('cut-copy'),
                              icon: Icons.content_copy,
                              title: 'Copy',
                              note: 'Leave the original as it is',
                              selected: !c.cutoutLeavesHole,
                              onTap: () => _hole(false),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _Choice(
                              key: const ValueKey('cut-cut'),
                              icon: Icons.content_cut,
                              title: 'Cut',
                              note: 'Take it out of the original',
                              selected: c.cutoutLeavesHole,
                              onTap: () => _hole(true),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (c.cutoutLeavesHole)
                  _Question(
                    '3',
                    'What should fill the gap?',
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _Choice(
                              key: const ValueKey('cut-fill-empty'),
                              compact: true,
                              icon: Icons.layers_clear_outlined,
                              title: 'Nothing',
                              selected: c.cutoutFill == HoleFill.empty,
                              onTap: () => _fill(HoleFill.empty),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _Choice(
                              key: const ValueKey('cut-fill-colour'),
                              compact: true,
                              icon: Icons.format_color_fill,
                              title: 'A colour',
                              selected: c.cutoutFill == HoleFill.color,
                              onTap: () => _fill(HoleFill.color),
                            ),
                          ),
                        ],
                      ),
                      if (c.cutoutFill == HoleFill.color)
                        ColorRow(
                          value: c.cutoutFillColor,
                          onChanged: (v) {
                            c.cutoutFillColor = v;
                            c.notify();
                          },
                        ),
                    ],
                  ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => c.setTool(Tool.select),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('cut-start'),
                      onPressed: _start,
                      child: const Text('Start   ⏎'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _mode(CutoutMode m) {
    c.cutoutMode = m;
    c.notify();
  }

  void _hole(bool v) {
    c.cutoutLeavesHole = v;
    c.notify();
  }

  void _fill(HoleFill f) {
    c.cutoutFill = f;
    c.notify();
  }
}

/// A numbered question with its answers under it.
class _Question extends StatelessWidget {
  const _Question(this.number, this.text, {required this.children});
  final String number, text;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Color(0xFFE6ECFF),
                shape: BoxShape.circle,
              ),
              child: Text(
                number,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: kAccent,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (int i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          children[i],
        ],
      ],
    ),
  );
}

/// One answer: an icon, a title, a line of explanation. Chosen ones are lit.
class _Choice extends StatelessWidget {
  const _Choice({
    super.key,
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
    this.note,
    this.compact = false,
  });
  final IconData icon;
  final String title;
  final String? note;
  final bool selected, compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(9),
    child: Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: compact ? 8 : 7),
      decoration: BoxDecoration(
        color: selected ? kAccent.withValues(alpha: 0.09) : null,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: selected ? kAccent : const Color(0xFFD0D4DD),
          width: selected ? 1.6 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: selected ? kAccent : kLabel),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (note != null)
                  Text(
                    note!,
                    style: const TextStyle(fontSize: 11.5, color: kMuted),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// What is left of the options once drawing starts: one line saying what to
/// do next, a way back to the options, and a way out.
class CutoutPill extends StatelessWidget {
  const CutoutPill({super.key, required this.c});
  final EditorController c;

  @override
  Widget build(BuildContext context) {
    final onImage = c.single is ImageObject;
    final text = c.cutoutMode == CutoutMode.wand
        ? 'Click a colour to remove it'
        : !onImage
        ? 'Drag across a picture'
        : c.cutoutMode == CutoutMode.box
        ? 'Drag a box over the part to ${c.cutoutLeavesHole ? 'cut' : 'copy'}'
        : 'Draw around the part to ${c.cutoutLeavesHole ? 'cut' : 'copy'}';
    return Material(
      key: const ValueKey('cutout-bar'),
      elevation: 3,
      borderRadius: BorderRadius.circular(20),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.content_cut, size: 16, color: kAccent),
            const SizedBox(width: 8),
            Text(text, style: const TextStyle(fontSize: 12.5)),
            const SizedBox(width: 10),
            TextButton(
              key: const ValueKey('cutout-options'),
              onPressed: () {
                c.cutoutOptionsOpen = true;
                c.notify();
              },
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: const Text('Options'),
            ),
            SmallIconButton(
              icon: Icons.close,
              tooltip: 'Done  Esc',
              onPressed: () => c.setTool(Tool.select),
            ),
          ],
        ),
      ),
    );
  }
}
