import 'package:flutter/material.dart';

import 'widgets.dart' show fieldBorder;
import 'design.dart';

/// Colours picked with the picker this session, newest first, so a colour
/// that was just mixed can be used again without mixing it again.
final List<int> recentColours = [];

/// Asks the editor for a colour off the page (the eyedropper); null when
/// there is no page to pick from. Answers null if the pick is cancelled.
Future<int?> Function()? pickFromPage;

void _remember(int argb) {
  recentColours.remove(argb);
  recentColours.insert(0, argb);
  if (recentColours.length > 10) recentColours.removeLast();
}

/// Opens the colour picker as a small popover next to [anchor] (the swatch
/// that was clicked). [onChanged] is told when a colour is settled: when a
/// drag ends or a hex code is entered, not on every pixel of a drag, so one
/// pick is one undo step.
Future<void> showColorPopover(
  BuildContext context, {
  required Rect anchor,
  required int initial,
  required ValueChanged<int> onChanged,
}) {
  const w = 252.0, h = 330.0;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close the colour picker',
    barrierColor: Colors.transparent,
    transitionDuration: kQuick,
    transitionBuilder: (context, anim, _, child) =>
        FadeTransition(opacity: anim, child: child),
    pageBuilder: (context, _, _) {
      final screen = MediaQuery.sizeOf(context);
      final left = (anchor.right - w)
          .clamp(8.0, screen.width - w - 8)
          .toDouble();
      var top = anchor.bottom + 8;
      if (top + h > screen.height - 8) top = anchor.top - h - 8;
      top = top.clamp(8.0, screen.height - h - 8).toDouble();
      return Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            width: w,
            child: Material(
              key: const ValueKey('color-popover'),
              color: Colors.white,
              elevation: 10,
              shadowColor: kShadow,
              borderRadius: BorderRadius.circular(kRadiusLarge),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(kRadiusLarge),
                  border: Border.all(color: kBorder),
                ),
                padding: const EdgeInsets.all(kSpace12),
                child: ColorPicker(initial: initial, onChanged: onChanged),
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// A colour square (saturation across, brightness down), a hue strip, a hex
/// box and the recent colours.
class ColorPicker extends StatefulWidget {
  const ColorPicker({
    super.key,
    required this.initial,
    required this.onChanged,
  });
  final int initial;
  final ValueChanged<int> onChanged;

  @override
  State<ColorPicker> createState() => _ColorPickerState();
}

class _ColorPickerState extends State<ColorPicker> {
  late HSVColor _hsv;
  late final TextEditingController _hex;
  final FocusNode _hexFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(
      widget.initial == 0 ? Colors.white : Color(widget.initial | 0xFF000000),
    );
    _hex = TextEditingController(text: _hexOf(_hsv.toColor()));
    _hexFocus.addListener(() {
      if (!_hexFocus.hasFocus) _commitHex();
    });
  }

  @override
  void dispose() {
    _hex.dispose();
    _hexFocus.dispose();
    super.dispose();
  }

  static String _hexOf(Color c) =>
      (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

  int get _argb => _hsv.toColor().toARGB32();

  void _set(HSVColor v, {bool settle = false}) {
    setState(() => _hsv = v);
    _hex.text = _hexOf(v.toColor());
    if (settle) _settle();
  }

  void _settle() {
    _remember(_argb);
    widget.onChanged(_argb);
  }

  /// After typing a code, keyboard focus goes back to the editor so the
  /// one-key shortcuts work again (as with the number boxes).
  void _giveBackFocus() {
    if (!_hexFocus.hasFocus) return;
    // The picker is a popover on its own route; the editor is behind it, so
    // simply letting go of the box is the most that can be asked of it.
    _hexFocus.unfocus();
  }

  /// The popover gets out of the way so the page can be clicked; the colour
  /// taken there is used just as one mixed here would be.
  Future<void> _pickFromPage() async {
    final pick = pickFromPage, onChanged = widget.onChanged;
    if (pick == null) return;
    Navigator.of(context).pop();
    final argb = await pick();
    if (argb == null) return;
    _remember(argb);
    onChanged(argb);
  }

  void _commitHex() {
    var t = _hex.text.trim().replaceFirst('#', '');
    if (t.length == 3) t = t.split('').map((ch) => ch + ch).join();
    final v = int.tryParse(t, radix: 16);
    if (t.length != 6 || v == null) {
      _hex.text = _hexOf(_hsv.toColor());
      return;
    }
    final c = Color(0xFF000000 | v);
    if (c.toARGB32() == _argb) return;
    setState(() => _hsv = HSVColor.fromColor(c));
    _settle();
  }

  @override
  Widget build(BuildContext context) {
    final current = _hsv.toColor();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SvSquare(hsv: _hsv, onChanged: (v) => _set(v), onEnd: _settle),
        const SizedBox(height: kSpace12),
        _HueStrip(
          hue: _hsv.hue,
          onChanged: (h) => _set(_hsv.withHue(h)),
          onEnd: _settle,
        ),
        const SizedBox(height: kSpace12),
        Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: current,
                borderRadius: BorderRadius.circular(kRadius),
                border: Border.all(color: kOutline),
              ),
            ),
            const SizedBox(width: kSpace12),
            Expanded(
              child: SizedBox(
                height: kControlHeight,
                child: TextField(
                  key: const ValueKey('color-hex'),
                  controller: _hex,
                  focusNode: _hexFocus,
                  style: const TextStyle(
                    fontSize: kTextBody,
                    letterSpacing: 0.6,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixText: '#',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: kSpace8,
                      vertical: kSpace8,
                    ),
                    border: fieldBorder(),
                    enabledBorder: fieldBorder(),
                    focusedBorder: fieldBorder(focused: true),
                  ),
                  onSubmitted: (_) {
                    _commitHex();
                    _giveBackFocus();
                  },
                ),
              ),
            ),
            if (pickFromPage != null) ...[
              const SizedBox(width: kSpace8),
              Tooltip(
                message: 'Take a colour from the page',
                waitDuration: kTooltipWait,
                child: SizedBox(
                  width: kControlHeight,
                  height: kControlHeight,
                  child: OutlinedButton(
                    key: const ValueKey('color-eyedropper'),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      side: const BorderSide(color: kBorder),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(kRadius),
                      ),
                    ),
                    onPressed: _pickFromPage,
                    child: const Icon(
                      Icons.colorize,
                      size: kIcon,
                      color: kIconInk,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        if (recentColours.isNotEmpty) ...[
          const SizedBox(height: kSpace12),
          const Text(
            'Recent',
            style: TextStyle(fontSize: kTextCaption, color: kInkSoft),
          ),
          const SizedBox(height: kSpace8),
          Wrap(
            spacing: kSpace8,
            runSpacing: kSpace8,
            children: [
              for (final c in recentColours)
                GestureDetector(
                  key: ValueKey('recent-$c'),
                  onTap: () {
                    _set(HSVColor.fromColor(Color(c)));
                    _settle();
                  },
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Color(c),
                      borderRadius: BorderRadius.circular(kRadius),
                      border: Border.all(color: kOutline),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SvSquare extends StatelessWidget {
  const _SvSquare({
    required this.hsv,
    required this.onChanged,
    required this.onEnd,
  });
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final w = box.maxWidth;
      const h = 150.0;
      void pick(Offset p) => onChanged(
        hsv
            .withSaturation((p.dx / w).clamp(0.0, 1.0))
            .withValue((1 - p.dy / h).clamp(0.0, 1.0)),
      );
      return GestureDetector(
        key: const ValueKey('color-square'),
        onPanDown: (d) => pick(d.localPosition),
        onPanUpdate: (d) => pick(d.localPosition),
        onPanEnd: (_) => onEnd(),
        onTapUp: (_) => onEnd(),
        child: SizedBox(
          width: w,
          height: h,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(kRadiusLarge),
                    gradient: LinearGradient(
                      colors: [
                        Colors.white,
                        HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
                      ],
                    ),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(kRadiusLarge),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: hsv.saturation * w - 8,
                top: (1 - hsv.value) * h - 8,
                child: IgnorePointer(
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hsv.toColor(),
                      border: Border.all(color: Colors.white, width: 2.5),
                      boxShadow: const [
                        BoxShadow(color: kShadow, blurRadius: 3),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _HueStrip extends StatelessWidget {
  const _HueStrip({
    required this.hue,
    required this.onChanged,
    required this.onEnd,
  });
  final double hue;
  final ValueChanged<double> onChanged;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final w = box.maxWidth;
      void pick(Offset p) => onChanged((p.dx / w).clamp(0.0, 1.0) * 359.99);
      return GestureDetector(
        key: const ValueKey('color-hue'),
        onPanDown: (d) => pick(d.localPosition),
        onPanUpdate: (d) => pick(d.localPosition),
        onPanEnd: (_) => onEnd(),
        onTapUp: (_) => onEnd(),
        child: SizedBox(
          width: w,
          height: 16,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(kRadiusLarge),
                    gradient: LinearGradient(
                      colors: [
                        for (int i = 0; i <= 6; i++)
                          HSVColor.fromAHSV(1, i * 60.0 % 360, 1, 1).toColor(),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: hue / 360 * w - 8,
                top: -1,
                child: IgnorePointer(
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: HSVColor.fromAHSV(1, hue, 1, 1).toColor(),
                      border: Border.all(color: Colors.white, width: 2.5),
                      boxShadow: const [
                        BoxShadow(color: kShadow, blurRadius: 3),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
