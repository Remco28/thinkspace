import 'package:flutter/material.dart';
import 'design.dart';

/// One look for every menu in the app (the ☰ menu, the right-click menus):
/// compact rows, a small icon column so labels line up, shortcuts in muted
/// type on the right, quiet section labels and rounded, softly shadowed
/// surfaces. The surface itself is set in the app theme ([menuTheme]).
PopupMenuThemeData menuTheme() => PopupMenuThemeData(
  color: Colors.white,
  surfaceTintColor: Colors.transparent,
  elevation: 10,
  shadowColor: kShadow,
  menuPadding: const EdgeInsets.symmetric(vertical: kSpace8),
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(kRadiusLarge),
    side: const BorderSide(color: kBorder),
  ),
);

const double kMenuRowHeight = 32;

/// A row in a menu. [checked] puts a tick in the icon column (and leaves an
/// empty one when false, so choices stay aligned).
PopupMenuEntry<T> menuItem<T>({
  required T value,
  required String label,
  IconData? icon,
  String? shortcut,
  bool? checked,
  bool danger = false,
  bool enabled = true,
  double width = 210,
}) {
  final color = !enabled
      ? kInkDisabled
      : danger
      ? kDanger
      : kInk;
  return PopupMenuItem<T>(
    value: value,
    enabled: enabled,
    height: kMenuRowHeight,
    padding: const EdgeInsets.symmetric(horizontal: kSpace12),
    child: SizedBox(
      width: width,
      child: Row(
        children: [
          SizedBox(
            width: kSpace24,
            child: checked != null
                ? (checked
                      ? const Icon(Icons.check, size: kIcon, color: kAccent)
                      : null)
                : icon != null
                ? Icon(icon, size: kIcon, color: danger ? color : kInkSoft)
                : null,
          ),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: kTextBody, color: color),
            ),
          ),
          if (shortcut != null && shortcut.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: kSpace12),
              child: Text(
                shortcut,
                style: const TextStyle(
                  fontSize: kTextCaption,
                  color: kInkFaint,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// A small, quiet heading inside a menu.
PopupMenuEntry<T> menuLabel<T>(String text, {double width = 210}) =>
    PopupMenuItem<T>(
      enabled: false,
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: kSpace12),
      child: SizedBox(
        width: width,
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: kTextCaption,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.7,
            color: kInkFaint,
          ),
        ),
      ),
    );

PopupMenuEntry<T> menuDivider<T>() => const PopupMenuDivider(height: 9);
