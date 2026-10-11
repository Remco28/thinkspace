import 'package:flutter/material.dart';

import '../editor/canvas_painter.dart' show kAccent;
import 'widgets.dart' show kBorder;

/// The few building blocks the side panels are made of, so spacing and
/// alignment come from one place: 14 px side margins, 8 px between a row's
/// parts, 6 px between rows, 16 px between sections.
const double kPanelPad = 14;
const double kRowGap = 6;
const double kSectionGap = 16;
const double kLabelWidth = 64;
const double kControlHeight = 30;

const Color kMuted = Color(0xFF6B7385);
const Color kLabel = Color(0xFF5B6272);
const Color kInk = Color(0xFF222733);

/// A titled group of rows. Sections are separated by a hairline and room, not
/// by boxes.
class Section extends StatelessWidget {
  const Section({
    super.key,
    this.title,
    this.trailing,
    required this.children,
    this.first = false,
  });
  final String? title;
  final Widget? trailing;
  final List<Widget> children;

  /// The first section has no hairline above it.
  final bool first;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (!first) ...[
        const SizedBox(height: kSectionGap - 4),
        const Divider(height: 1, color: kBorder),
        const SizedBox(height: kSectionGap - 4),
      ],
      if (title != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title!,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    color: kLabel,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      for (int i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(height: kRowGap),
        children[i],
      ],
    ],
  );
}

/// A label on the left and a control on the right, on a fixed label column so
/// every row in every panel lines up. [stacked] puts the label above the
/// control, for wide controls such as colour swatches.
class PropRow extends StatelessWidget {
  const PropRow(this.label, this.child, {super.key, this.stacked = false});
  final String label;
  final Widget child;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      style: const TextStyle(fontSize: 12, color: kLabel),
    );
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [text, const SizedBox(height: 6), child],
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: kControlHeight),
      child: Row(
        children: [
          SizedBox(width: kLabelWidth, child: text),
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: child),
          ),
        ],
      ),
    );
  }
}

/// Several icon buttons joined into one control. Used both for toggles
/// (bold, italic, alignment) and for plain action groups (align, arrange).
class IconGroup extends StatelessWidget {
  const IconGroup({super.key, required this.buttons});
  final List<GroupButton> buttons;

  @override
  Widget build(BuildContext context) => Container(
    height: 28,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: const Color(0xFFD0D4DD)),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < buttons.length; i++) ...[
            if (i > 0)
              Container(width: 1, height: 28, color: const Color(0xFFE3E6EC)),
            buttons[i],
          ],
        ],
      ),
    ),
  );
}

class GroupButton extends StatelessWidget {
  const GroupButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.danger = false,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final bool danger;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    waitDuration: const Duration(milliseconds: 500),
    child: InkWell(
      onTap: onPressed,
      child: Container(
        width: 30,
        height: 28,
        color: active ? kAccent.withValues(alpha: 0.14) : null,
        child: Icon(
          icon,
          size: 17,
          color: onPressed == null
              ? const Color(0xFFB4B8C2)
              : active
              ? kAccent
              : danger
              ? const Color(0xFFC62828)
              : const Color(0xFF444B5A),
        ),
      ),
    ),
  );
}

/// A full-width, compact button with an icon: the main actions of a section.
class ActionButton extends StatelessWidget {
  const ActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.tooltip,
    this.selected = false,
  });
  final String label;
  final IconData? icon;
  final String? tooltip;

  /// Drawn as "on", for buttons that behave like switches (Show grid).
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      width: double.infinity,
      height: kControlHeight,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 16),
        label: Text(label, overflow: TextOverflow.ellipsis),
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          textStyle: const TextStyle(fontSize: 12.5),
          side: BorderSide(color: selected ? kAccent : const Color(0xFFD0D4DD)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          backgroundColor: selected ? kAccent.withValues(alpha: 0.12) : null,
          foregroundColor: selected ? kAccent : kInk,
          iconColor: selected ? kAccent : const Color(0xFF5B6272),
        ),
      ),
    );
    return tooltip == null
        ? button
        : Tooltip(
            message: tooltip!,
            waitDuration: const Duration(milliseconds: 500),
            child: button,
          );
  }
}

/// Buttons of equal width in one row.
class ButtonRow extends StatelessWidget {
  const ButtonRow(this.children, {super.key});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (int i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(child: children[i]),
      ],
    ],
  );
}

/// A label, a switch, and, when asked, a line of explanation underneath.
class SwitchRow extends StatelessWidget {
  const SwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
  });
  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => onChanged(!value),
    borderRadius: BorderRadius.circular(6),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontSize: 12.5, color: kInk),
                  ),
                  if (hint != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        hint!,
                        style: const TextStyle(
                          fontSize: 11.5,
                          height: 1.3,
                          color: kMuted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Transform.scale(
            scale: 0.72,
            alignment: Alignment.centerRight,
            child: Switch(value: value, onChanged: onChanged),
          ),
        ],
      ),
    ),
  );
}

/// A line of quiet explanatory text.
class Hint extends StatelessWidget {
  const Hint(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontSize: 11.5, height: 1.35, color: kMuted),
  );
}
