import 'package:flutter/material.dart';

import '../editor/canvas_painter.dart' show kAccent;
import 'widgets.dart' show kBorder;

/// One look for every menu in the app (the ☰ menu, the right-click menus):
/// compact rows, a small icon column so labels line up, shortcuts in muted
/// type on the right, quiet section labels and rounded, softly shadowed
/// surfaces. The surface itself is set in the app theme ([menuTheme]).
PopupMenuThemeData menuTheme() => PopupMenuThemeData(
  color: Colors.white,
  surfaceTintColor: Colors.transparent,
  elevation: 10,
  shadowColor: const Color(0x44000000),
  menuPadding: const EdgeInsets.symmetric(vertical: 6),
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(10),
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
      ? const Color(0xFFB4B8C2)
      : danger
      ? const Color(0xFFC62828)
      : const Color(0xFF222733);
  return PopupMenuItem<T>(
    value: value,
    enabled: enabled,
    height: kMenuRowHeight,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: SizedBox(
      width: width,
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: checked != null
                ? (checked
                      ? const Icon(Icons.check, size: 16, color: kAccent)
                      : null)
                : icon != null
                ? Icon(
                    icon,
                    size: 16,
                    color: danger ? color : const Color(0xFF5B6272),
                  )
                : null,
          ),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: color),
            ),
          ),
          if (shortcut != null && shortcut.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                shortcut,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF8A90A0),
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
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(
        width: width,
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.7,
            color: Color(0xFF8A90A0),
          ),
        ),
      ),
    );

PopupMenuEntry<T> menuDivider<T>() => const PopupMenuDivider(height: 9);
