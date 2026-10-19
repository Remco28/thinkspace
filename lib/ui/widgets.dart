import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../editor/controller.dart';
import 'color_picker.dart';
import 'design.dart';

class PanelHeader extends StatelessWidget {
  const PanelHeader(this.title, {super.key, this.actions = const []});
  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Container(
    height: 36,
    padding: const EdgeInsets.only(left: kSpace12, right: kSpace4),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: kBorder)),
    ),
    child: Row(
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: kTextCaption,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: kInkSoft,
          ),
        ),
        const Spacer(),
        ...actions,
      ],
    ),
  );
}

class SmallIconButton extends StatelessWidget {
  const SmallIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.size = 18,
    this.color,
    this.glyph,
  });
  final IconData icon;

  /// A drawn icon for when no font icon says it (the straight line). Gets
  /// the colour and size the font icon would have had.
  final Widget Function(double size, Color color)? glyph;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    waitDuration: kTooltipWait,
    child: InkResponse(
      onTap: onPressed,
      radius: 16,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: active ? kAccent.withValues(alpha: 0.14) : null,
          borderRadius: BorderRadius.circular(kRadius),
        ),
        child: () {
          final c = onPressed == null
              ? kInkDisabled
              : active
              ? kAccent
              : color ?? kIconInk;
          return glyph != null
              ? Center(child: glyph!(size, c))
              : Icon(icon, size: size, color: c);
        }(),
      ),
    ),
  );
}

class LabeledRow extends StatelessWidget {
  const LabeledRow(this.label, this.child, {super.key});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: kSpace4),
    child: Row(
      children: [
        SizedBox(
          width: 62,
          child: Text(
            label,
            style: const TextStyle(fontSize: kTextBody, color: kInkSoft),
          ),
        ),
        Expanded(child: child),
      ],
    ),
  );
}

/// A slider that records one undo step per drag.
class LiveSlider extends StatefulWidget {
  const LiveSlider({
    super.key,
    required this.controller,
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    required this.apply,
    this.divisions,
  });
  final EditorController controller;
  final double value, min, max;
  final String label;
  final int? divisions;
  final void Function(double v) apply;

  @override
  State<LiveSlider> createState() => _LiveSliderState();
}

class _LiveSliderState extends State<LiveSlider> {
  EditToken? _token;

  @override
  Widget build(BuildContext context) => SliderTheme(
    data: SliderTheme.of(context).copyWith(
      trackHeight: 3,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      overlayShape: SliderComponentShape.noOverlay,
    ),
    child: Slider(
      value: widget.value.clamp(widget.min, widget.max),
      min: widget.min,
      max: widget.max,
      divisions: widget.divisions,
      onChangeStart: (_) => _token = widget.controller.beginEdit(widget.label),
      onChanged: widget.apply,
      onChangeEnd: (_) {
        if (_token != null) widget.controller.endEdit(_token!);
        _token = null;
      },
    ),
  );
}

class ColorRow extends StatelessWidget {
  const ColorRow({
    super.key,
    required this.value,
    required this.onChanged,
    this.allowNone = false,
    this.palette = kPalette,
  });
  final int value;
  final ValueChanged<int> onChanged;
  final bool allowNone;

  /// The fixed swatches; the rainbow one after them mixes any other colour.
  final List<int> palette;

  @override
  Widget build(BuildContext context) {
    Widget swatch(int argb) {
      final selected = value == argb;
      return GestureDetector(
        onTap: () => onChanged(argb),
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: argb == 0 ? Colors.white : Color(argb),
            borderRadius: BorderRadius.circular(kRadius),
            border: Border.all(
              color: selected ? kAccent : kOutline,
              width: selected ? 2 : 1,
            ),
          ),
          child: argb == 0
              ? const Icon(Icons.block, size: kIconSmall, color: kDanger)
              : null,
        ),
      );
    }

    final custom = !palette.contains(value) && value != 0;
    return Wrap(
      spacing: kSpace8,
      runSpacing: kSpace8,
      children: [
        if (allowNone) swatch(0),
        for (final c in palette) swatch(c),
        // The last swatch opens the colour picker; it shows the colour in use
        // when that is not one of the fixed ones.
        Builder(
          builder: (context) => Tooltip(
            message: 'Mix any colour',
            waitDuration: kTooltipWait,
            child: GestureDetector(
              key: const ValueKey('custom-colour'),
              onTap: () {
                final box = context.findRenderObject() as RenderBox;
                final at = box.localToGlobal(Offset.zero) & box.size;
                showColorPopover(
                  context,
                  anchor: at,
                  initial: value,
                  onChanged: onChanged,
                );
              },
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: custom ? Color(value) : null,
                  gradient: custom
                      ? null
                      : const SweepGradient(
                          colors: [
                            Colors.red,
                            Colors.yellow,
                            Colors.green,
                            Colors.blue,
                            Colors.purple,
                            Colors.red,
                          ],
                        ),
                  borderRadius: BorderRadius.circular(kRadius),
                  border: Border.all(
                    color: custom ? kAccent : kOutline,
                    width: custom ? 2 : 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The outline every text and number box in the panels shares.
OutlineInputBorder fieldBorder({bool focused = false}) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(kRadius),
  borderSide: BorderSide(
    color: focused ? kAccent : kControlBorder,
    width: focused ? 1.6 : 1,
  ),
);

class NumberField extends StatefulWidget {
  const NumberField({
    super.key,
    required this.value,
    required this.onSubmitted,
    this.suffix,
    this.width = 64,
  });
  final double value;
  final ValueChanged<double> onSubmitted;
  final String? suffix;
  final double width;

  @override
  State<NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<NumberField> {
  late final TextEditingController _ctl = TextEditingController(
    text: _fmt(widget.value),
  );
  final FocusNode _focus = FocusNode();

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _submit();
    });
  }

  @override
  void didUpdateWidget(NumberField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && old.value != widget.value) {
      _ctl.text = _fmt(widget.value);
    }
  }

  void _submit() {
    final v = double.tryParse(_ctl.text.trim());
    if (v != null && v != widget.value) widget.onSubmitted(v);
    _ctl.text = _fmt(v ?? widget.value);
  }

  @override
  void dispose() {
    _focus.dispose();
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.width,
    height: 30,
    child: TextField(
      controller: _ctl,
      focusNode: _focus,
      style: const TextStyle(fontSize: kTextBody),
      decoration: InputDecoration(
        isDense: true,
        suffixText: widget.suffix,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: kSpace8,
          vertical: kSpace8,
        ),
        border: fieldBorder(),
        enabledBorder: fieldBorder(),
        focusedBorder: fieldBorder(focused: true),
      ),
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      onSubmitted: (_) {
        _submit();
        _giveBackFocus();
      },
      // Clicking anywhere else ends the edit, so the one-key shortcuts work
      // again without having to click the page first.
      onTapOutside: (_) => _giveBackFocus(),
    ),
  );

  /// Hand keyboard focus back to the editor around us (the shortcut handler).
  void _giveBackFocus() {
    if (!_focus.hasFocus) return;
    final editor = Focus.maybeOf(context);
    if (editor != null) {
      editor.requestFocus();
    } else {
      _focus.unfocus();
    }
  }
}

/// Taps respond instantly; a second tap within a moment counts as a double
/// tap. (GestureDetector.onDoubleTap would delay every single tap.)
class QuickTap extends StatefulWidget {
  const QuickTap({
    super.key,
    required this.onTap,
    this.onDoubleTap,
    required this.child,
    this.onSecondaryTapDown,
  });
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final void Function(TapDownDetails)? onSecondaryTapDown;
  final Widget child;

  @override
  State<QuickTap> createState() => _QuickTapState();
}

class _QuickTapState extends State<QuickTap> {
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onSecondaryTapDown: widget.onSecondaryTapDown,
    onTap: () {
      final now = DateTime.now();
      final again = now.difference(_last).inMilliseconds < 380;
      _last = again ? DateTime.fromMillisecondsSinceEpoch(0) : now;
      if (again && widget.onDoubleTap != null) {
        widget.onDoubleTap!();
      } else {
        widget.onTap();
      }
    },
    child: widget.child,
  );
}

const _imageExts = ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'];

bool isImagePath(String p) =>
    _imageExts.contains(p.split('.').last.toLowerCase());

/// Accepts files dragged in from the desktop.
class FileDropZone extends StatefulWidget {
  const FileDropZone({super.key, required this.child, required this.onFiles});
  final Widget child;
  final void Function(List<String> paths, Offset local) onFiles;

  @override
  State<FileDropZone> createState() => _FileDropZoneState();
}

class _FileDropZoneState extends State<FileDropZone> {
  bool _over = false;

  @override
  Widget build(BuildContext context) => DropTarget(
    onDragEntered: (_) => setState(() => _over = true),
    onDragExited: (_) => setState(() => _over = false),
    onDragDone: (d) {
      setState(() => _over = false);
      widget.onFiles([for (final f in d.files) f.path], d.localPosition);
    },
    child: Stack(
      children: [
        Positioned.fill(child: widget.child),
        if (_over)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  color: kAccent.withValues(alpha: 0.08),
                  border: Border.all(color: kAccent, width: 2),
                ),
                child: const Center(
                  child: Text(
                    'Drop to add',
                    style: TextStyle(
                      color: kAccent,
                      fontWeight: FontWeight.w700,
                      fontSize: kTextTitle,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// A little keyboard key. Used wherever the app says "press this", so a
/// keystroke always looks like one.
class KeyCap extends StatelessWidget {
  const KeyCap(this.label, {super.key, this.compact = false});
  final String label;

  /// Smaller, for the toolbar.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final h = compact ? 12.0 : 19.0;
    // No alignment on the Container: it would stretch to fill whatever room
    // the parent offers, which is what made the toolbar key look so roomy.
    return Container(
      constraints: BoxConstraints(minWidth: h, minHeight: h),
      padding: EdgeInsets.symmetric(horizontal: compact ? kSpace4 : kSpace8),
      decoration: BoxDecoration(
        color: kPanel,
        borderRadius: BorderRadius.circular(compact ? 3 : 4.5),
        border: Border.all(color: kOutline, width: 0.8),
        // The flat shadow under the key is what makes it read as a key.
        boxShadow: [
          BoxShadow(color: kInkFaint, offset: Offset(0, compact ? 1 : 2)),
        ],
      ),
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: Text(
          label,
          style: TextStyle(
            fontSize: compact ? 8.5 : 11.5,
            height: 1.1,
            fontWeight: FontWeight.w700,
            color: kInk,
          ),
        ),
      ),
    );
  }
}

/// A straight diagonal line with a dot at each end: the "straight line" tool.
class LineGlyph extends StatelessWidget {
  const LineGlyph(this.size, this.color, {super.key});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _LinePainter(color));
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    final a = Offset(s.width * 0.16, s.height * 0.84);
    final b = Offset(s.width * 0.84, s.height * 0.16);
    canvas.drawLine(a, b, p);
    final dot = Paint()..color = color;
    canvas.drawCircle(a, 2.1, dot);
    canvas.drawCircle(b, 2.1, dot);
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.color != color;
}

/// A chisel-tip marker lying over a bar of colour: the highlighter tool.
class HighlighterGlyph extends StatelessWidget {
  const HighlighterGlyph(this.size, this.color, {super.key});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _HighlighterPainter(color));
}

class _HighlighterPainter extends CustomPainter {
  _HighlighterPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final u = s.width / 18; // drawn on an 18-unit grid
    // The stripe the marker has just laid down.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(1.5 * u, 14 * u, 15 * u, 3 * u),
        Radius.circular(1.2 * u),
      ),
      Paint()..color = color.withValues(alpha: 0.45),
    );
    // The marker: a slanted body with a flat tip.
    final body = Path()
      ..moveTo(5.2 * u, 12.2 * u)
      ..lineTo(11.6 * u, 3.0 * u)
      ..lineTo(14.6 * u, 5.2 * u)
      ..lineTo(8.2 * u, 14.2 * u)
      ..close();
    canvas.drawPath(
      body,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * u
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawLine(
      Offset(7.2 * u, 8.4 * u),
      Offset(10.6 * u, 10.8 * u),
      Paint()
        ..color = color
        ..strokeWidth = 1.2 * u,
    );
    // The tip, resting on the stripe.
    canvas.drawLine(
      Offset(5.0 * u, 12.6 * u),
      Offset(8.4 * u, 14.6 * u),
      Paint()
        ..color = color
        ..strokeWidth = 1.8 * u
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_HighlighterPainter old) => old.color != color;
}

/// A pen squiggle with a small cross badge at its corner: Remove marks. The
/// cross is a badge, not the whole icon, so it doesn't read as "close".
class RemoveMarksGlyph extends StatelessWidget {
  const RemoveMarksGlyph(this.size, this.color, {super.key});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _RemoveMarksPainter(color));
}

class _RemoveMarksPainter extends CustomPainter {
  _RemoveMarksPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final u = s.width / 18; // drawn on an 18-unit grid
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 * u
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // The mark: a loose squiggle across the lower left.
    final squiggle = Path()
      ..moveTo(1.8 * u, 13.2 * u)
      ..cubicTo(3.5 * u, 6.5 * u, 6.5 * u, 6.0 * u, 6.8 * u, 10.2 * u)
      ..cubicTo(7.1 * u, 14.6 * u, 10.2 * u, 14.8 * u, 11.2 * u, 9.6 * u);
    canvas.drawPath(squiggle, line);
    // The badge: a cross in a filled circle, top right.
    final centre = Offset(13.4 * u, 4.6 * u);
    canvas.drawCircle(centre, 4.2 * u, Paint()..color = color);
    final cross = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.3 * u
      ..strokeCap = StrokeCap.round;
    const k = 1.7;
    canvas.drawLine(
      centre + Offset(-k * u, -k * u),
      centre + Offset(k * u, k * u),
      cross,
    );
    canvas.drawLine(
      centre + Offset(-k * u, k * u),
      centre + Offset(k * u, -k * u),
      cross,
    );
  }

  @override
  bool shouldRepaint(_RemoveMarksPainter old) => old.color != color;
}

/// Hide details: a little mosaic, which is what the tool leaves behind.
class HideDetailsGlyph extends StatelessWidget {
  const HideDetailsGlyph(this.size, this.color, {super.key});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _HideDetailsPainter(color));
}

class _HideDetailsPainter extends CustomPainter {
  _HideDetailsPainter(this.color);
  final Color color;

  // How strongly each tile of the 3 × 3 mosaic is inked, row by row.
  static const _shades = [1.0, 0.35, 0.7, 0.5, 1.0, 0.3, 0.8, 0.45, 1.0];

  @override
  void paint(Canvas canvas, Size s) {
    final u = s.width / 18; // drawn on an 18-unit grid
    const tile = 4.4, gap = 0.7, start = 2.3;
    for (var i = 0; i < 9; i++) {
      final x = start + (i % 3) * (tile + gap),
          y = start + (i ~/ 3) * (tile + gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x * u, y * u, tile * u, tile * u),
          Radius.circular(0.8 * u),
        ),
        Paint()..color = color.withValues(alpha: color.a * _shades[i]),
      );
    }
  }

  @override
  bool shouldRepaint(_HideDetailsPainter old) => old.color != color;
}
