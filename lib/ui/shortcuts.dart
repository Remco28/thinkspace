import 'package:flutter/material.dart';

import 'widgets.dart';
import 'design.dart';

/// One line of the shortcuts sheet: one or more key combinations (any of which
/// does the job) and what they do.
typedef _Row = (List<List<String>>, String);

const _tools = <(String, String)>[
  ('V', 'Select'),
  ('A', 'Arrow'),
  ('L', 'Line'),
  ('R', 'Rectangle'),
  ('E', 'Ellipse'),
  ('T', 'Text'),
  ('N', 'Numbered marker'),
  ('P', 'Pen'),
  ('H', 'Highlighter'),
  ('X', 'Remove marks'),
  ('C', 'Cut out'),
];

const _sections = <(String, List<_Row>)>[
  (
    'Drawing and moving',
    [
      (
        [
          ['Shift'],
        ],
        'While drawing: straight angles, perfect squares',
      ),
      (
        [
          ['Ctrl'],
        ],
        'While moving: ignore snapping',
      ),
      (
        [
          ['Click'],
        ],
        'On the selected thing again: reach what is underneath',
      ),
      (
        [
          ['←', '↑', '↓', '→'],
        ],
        'Nudge the selection (hold Shift for 10 px)',
      ),
      (
        [
          ['Click'],
        ],
        'A Layers row, then ↑ ↓ walk the list; Shift extends it',
      ),
      (
        [
          ['['],
          [']'],
        ],
        'Send backward / bring forward (or move a selected collection item)',
      ),
      (
        [
          ['F2'],
        ],
        'Edit the selected text, or rename the selected collection item',
      ),
      (
        [
          ['Enter'],
          ['Delete'],
        ],
        'With a collection item selected: place it on the page / remove it',
      ),
      (
        [
          ['M'],
          ['U'],
        ],
        'Merge the selection into one image / take a merged image apart',
      ),
      (
        [
          ['Ctrl', 'L'],
        ],
        'Lock the selection in place, or unlock it',
      ),
      (
        [
          ['Esc'],
        ],
        'Back to Select, or clear the selection',
      ),
    ],
  ),
  (
    'Getting around',
    [
      (
        [
          ['Space', 'drag'],
        ],
        'Pan the page (middle or right mouse drag works too)',
      ),
      (
        [
          ['Scroll'],
        ],
        'Zoom at the pointer',
      ),
      (
        [
          ['Shift', 'Scroll'],
        ],
        'Pan sideways',
      ),
      (
        [
          ['Ctrl', '0'],
          ['F'],
        ],
        'Fit the page in the window',
      ),
      (
        [
          ['Ctrl', '1'],
        ],
        'Actual size',
      ),
      (
        [
          ['G'],
        ],
        'Show the grid',
      ),
      (
        [
          ['F11'],
        ],
        'Full screen, and back',
      ),
      (
        [
          ['Shift', 'G'],
        ],
        'Snap to the grid',
      ),
    ],
  ),
  (
    'Edit and share',
    [
      (
        [
          ['Ctrl', 'Z'],
          ['Ctrl', 'Shift', 'Z'],
        ],
        'Undo / redo',
      ),
      (
        [
          ['Ctrl', 'C'],
          ['Ctrl', 'X'],
          ['Ctrl', 'D'],
        ],
        'Copy, cut, duplicate',
      ),
      (
        [
          ['Ctrl', 'V'],
        ],
        'Paste an image (it asks where it goes)',
      ),
      (
        [
          ['Ctrl', 'Shift', 'V'],
        ],
        'Paste an image into the collection',
      ),
      (
        [
          ['Ctrl', 'Shift', 'C'],
        ],
        'Copy the whole page as an image',
      ),
      (
        [
          ['Ctrl', 'S'],
          ['Ctrl', 'O'],
          ['Ctrl', 'E'],
        ],
        'Save, open, export PNG',
      ),
      (
        [
          ['?'],
        ],
        'Show this sheet',
      ),
    ],
  ),
];

/// Mouse actions that appear inside a combination ("Space + drag"): shown as
/// words, since they are not keys.
const _mouseWords = {'drag', 'Scroll', 'Click'};

/// A key combination as keycaps joined by "+".
class KeyCombo extends StatelessWidget {
  const KeyCombo(this.keys, {super.key});
  final List<String> keys;

  // Four arrow keys are four alternatives, not a chord.
  bool get _chord => !keys.every((k) => '←↑↓→'.contains(k));

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (int i = 0; i < keys.length; i++) ...[
        if (i > 0 && !_chord) const SizedBox(width: kSpace4),
        if (i > 0 && _chord)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: kSpace8),
            child: Text(
              '+',
              style: TextStyle(fontSize: kTextCaption, color: kInkFaint),
            ),
          ),
        if (_mouseWords.contains(keys[i]))
          Text(
            keys[i],
            style: const TextStyle(
              fontSize: kTextBody,
              fontWeight: kWeightStrong,
              color: kInk,
            ),
          )
        else
          KeyCap(keys[i]),
      ],
    ],
  );
}

Future<void> showShortcuts(BuildContext context) => showDialog<void>(
  context: context,
  builder: (ctx) => AlertDialog(
    title: const Text('Keyboard shortcuts'),
    contentPadding: const EdgeInsets.fromLTRB(kSpace24, kSpace12, kSpace24, 0),
    content: SizedBox(
      width: 640,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Heading('Tools — press the letter'),
            Wrap(
              spacing: kSpace20,
              runSpacing: kSpace12,
              children: [
                for (final t in _tools)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      KeyCap(t.$1),
                      const SizedBox(width: kSpace8),
                      Text(t.$2, style: const TextStyle(fontSize: kTextBody)),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: kSpace8),
            const Text(
              'A tool is used once, then you are back on Select. '
              'Double-click a tool button to keep it active.',
              style: TextStyle(fontSize: kTextBody, color: kInkSoft),
            ),
            for (final s in _sections) ...[
              _Heading(s.$1),
              for (final r in s.$2) _ShortcutLine(r),
            ],
            const SizedBox(height: kSpace12),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(ctx),
        child: const Text('Close'),
      ),
    ],
  ),
);

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: kSpace20, bottom: kSpace8),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: kTextCaption,
        letterSpacing: 0.8,
        fontWeight: kWeightHeading,
        color: kInkSoft,
      ),
    ),
  );
}

class _ShortcutLine extends StatelessWidget {
  const _ShortcutLine(this.row);
  final _Row row;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: kSpace4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 290,
          child: Wrap(
            spacing: kSpace8,
            runSpacing: kSpace8,
            children: [
              for (int i = 0; i < row.$1.length; i++) ...[
                if (i > 0)
                  const Padding(
                    padding: EdgeInsets.only(top: kSpace4),
                    child: Text(
                      'or',
                      style: TextStyle(
                        fontSize: kTextCaption,
                        color: kInkFaint,
                      ),
                    ),
                  ),
                KeyCombo(row.$1[i]),
              ],
            ],
          ),
        ),
        Expanded(
          child: Text(row.$2, style: const TextStyle(fontSize: kTextBody)),
        ),
      ],
    ),
  );
}
