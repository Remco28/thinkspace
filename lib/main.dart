import 'package:flutter/material.dart';

import 'dev/inspector.dart';
import 'editor/canvas_painter.dart';
import 'ui/menus.dart';
import 'ui/shell.dart';

void main(List<String> args) => runApp(ThinkspaceApp(launchFiles: args));

class ThinkspaceApp extends StatelessWidget {
  const ThinkspaceApp({super.key, this.launchFiles = const []});
  final List<String> launchFiles;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: appShotKey,
      child: MaterialApp(
        title: 'Thinkspace',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: kAccent,
            brightness: Brightness.light,
          ),
          visualDensity: VisualDensity.compact,
          scaffoldBackgroundColor: Colors.white,
          dividerColor: const Color(0xFFD9DCE3),
          popupMenuTheme: menuTheme(),
          tooltipTheme: TooltipThemeData(
            constraints: const BoxConstraints(maxWidth: 280),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xE6222733),
              borderRadius: BorderRadius.circular(6),
            ),
            textStyle: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
        home: EditorShell(enableRecovery: true, launchFiles: launchFiles),
      ),
    );
  }
}
