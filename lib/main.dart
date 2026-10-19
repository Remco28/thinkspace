import 'package:flutter/material.dart';

import 'dev/inspector.dart';
import 'ui/menus.dart';
import 'ui/shell.dart';
import 'ui/design.dart';

void main(List<String> args) => runApp(ThinkspaceApp(launchFiles: args));

const TextStyle _flat = TextStyle(letterSpacing: 0);

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
          fontFamily: kUiFont,
          // Material spaces some text styles out (fields by 0.5 px); a
          // compact desktop interface sets every text the same way.
          textTheme: const TextTheme(
            displayLarge: _flat,
            displayMedium: _flat,
            displaySmall: _flat,
            headlineLarge: _flat,
            headlineMedium: _flat,
            headlineSmall: _flat,
            titleLarge: _flat,
            titleMedium: _flat,
            titleSmall: _flat,
            bodyLarge: _flat,
            bodyMedium: _flat,
            bodySmall: _flat,
            labelLarge: _flat,
            labelMedium: _flat,
            labelSmall: _flat,
          ),
          colorScheme: ColorScheme.fromSeed(
            seedColor: kAccent,
            brightness: Brightness.light,
          ),
          visualDensity: VisualDensity.compact,
          scaffoldBackgroundColor: Colors.white,
          dividerColor: kBorder,
          popupMenuTheme: menuTheme(),
          tooltipTheme: TooltipThemeData(
            constraints: const BoxConstraints(maxWidth: 280),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: kOverlay,
              borderRadius: BorderRadius.circular(kRadius),
            ),
            textStyle: const TextStyle(
              fontFamily: kUiFont,
              color: Colors.white,
              fontSize: kTextBody,
            ),
          ),
        ),
        home: EditorShell(enableRecovery: true, launchFiles: launchFiles),
      ),
    );
  }
}
