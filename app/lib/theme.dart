import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

class AppTheme {
  static ThemeData light([Color seed = const Color(0xFF4F46E5)]) => ThemeData(
    useMaterial3: true,
    colorSchemeSeed: seed,
    brightness: Brightness.light,
    cardTheme: const CardThemeData(
      elevation: 0,
      margin: EdgeInsets.symmetric(vertical: 6, horizontal: 0),
    ),
  );

  static ThemeData dark([Color seed = const Color(0xFF4F46E5)]) => ThemeData(
    useMaterial3: true,
    colorSchemeSeed: seed,
    brightness: Brightness.dark,
    cardTheme: const CardThemeData(
      elevation: 0,
      margin: EdgeInsets.symmetric(vertical: 6, horizontal: 0),
    ),
  );
}
