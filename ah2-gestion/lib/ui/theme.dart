/// Charte visuelle de l'application (maquettes validées) : modes clair et sombre.
library;

import 'package:material_ui/material_ui.dart';

class Couleurs {
  static const primaire = Color(0xFF0E6E5C);
  static const primaireFonce = Color(0xFF0A5446);
  static const barreLaterale = Color(0xFF0F2A24);
  static const fond = Color(0xFFF4F6F4);
  static const encre = Color(0xFF12201C);
  static const discret = Color(0xFF5B6B66);
  static const hausse = Color(0xFF15803D);
  static const stable = Color(0xFF9A3412);
  static const baisse = Color(0xFFB91C1C);
  static const alerteOrangeFond = Color(0xFFFDF4EC);
  static const alerteOrangeBord = Color(0xFFF3C9A8);
  static const alerteRougeFond = Color(0xFFFCEDED);
  static const alerteRougeBord = Color(0xFFF1B8B8);
}

ThemeData themeAh2(Brightness luminosite) {
  final sombre = luminosite == Brightness.dark;
  final schema = ColorScheme.fromSeed(
    seedColor: Couleurs.primaire,
    brightness: luminosite,
    primary: sombre ? const Color(0xFF5ED3B6) : Couleurs.primaire,
    surface: sombre ? const Color(0xFF14201D) : Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: schema,
    scaffoldBackgroundColor: sombre ? const Color(0xFF0C1513) : Couleurs.fond,
    cardTheme: CardThemeData(
      elevation: 0,
      color: schema.surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: schema.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    chipTheme: ChipThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999))),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}
