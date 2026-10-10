import 'package:flutter/material.dart';

import 'widgets.dart';

/// One line of the shortcuts sheet: one or more key combinations (any of which
/// does the job) and what they do.
typedef _Row = (List<List<String>>, String);

const _tools = <(String, String)>[
  ('V', 'Select'),
  ('L', 'Line'),
  ('A', 'Arrow'),
  ('R', 'Rectangle'),
  ('E', 'Ellipse'),
  ('T', 'Text'),
  ('P', 'Pen'),
  ('N', 'Numbered marker'),
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
        'Send backward / bring forward',
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
        if (i > 0 && !_chord) const SizedBox(width: 4),
        if (i > 0 && _chord)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '+',
              style: TextStyle(fontSize: 11, color: Color(0xFF8A90A0)),
            ),
          ),
        if (_mouseWords.contains(keys[i]))
          Text(
            keys[i],
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2B3140),
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
    contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
    content: SizedBox(
      width: 640,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Heading('Tools — press the letter'),
            Wrap(
              spacing: 18,
              runSpacing: 10,
              children: [
                for (final t in _tools)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      KeyCap(t.$1),
                      const SizedBox(width: 7),
                      Text(t.$2, style: const TextStyle(fontSize: 13)),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'A tool is used once, then you are back on Select. '
              'Double-click a tool button to keep it active.',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7385)),
            ),
            for (final s in _sections) ...[
              _Heading(s.$1),
              for (final r in s.$2) _ShortcutLine(r),
            ],
            const SizedBox(height: 12),
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
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w700,
        color: Color(0xFF6B7385),
      ),
    ),
  );
}

class _ShortcutLine extends StatelessWidget {
  const _ShortcutLine(this.row);
  final _Row row;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 290,
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (int i = 0; i < row.$1.length; i++) ...[
                if (i > 0)
                  const Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: Text(
                      'or',
                      style: TextStyle(fontSize: 11, color: Color(0xFF8A90A0)),
                    ),
                  ),
                KeyCombo(row.$1[i]),
              ],
            ],
          ),
        ),
        Expanded(child: Text(row.$2, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );
}
