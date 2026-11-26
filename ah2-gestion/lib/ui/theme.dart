/// Charte visuelle de l'application (maquettes validées) : modes clair et sombre.
library;

import 'package:material_ui/material_ui.dart';

class Couleurs {
  // Charte sobre : vert institutionnel du logo, gris neutres.
  static const primaire = Color(0xFF1F4D36);
  static const primaireFonce = Color(0xFF153826);
  static const barreLaterale = Color(0xFF1C2622);
  static const fond = Color(0xFFF5F5F4);
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
    dynamicSchemeVariant: DynamicSchemeVariant.neutral,
    primary: sombre ? const Color(0xFF8CC7A4) : Couleurs.primaire,
    onPrimary: sombre ? const Color(0xFF0F1A14) : Colors.white,
    surface: sombre ? const Color(0xFF1A1D1C) : Colors.white,
  );
  final bordure = sombre ? const Color(0xFF2E3431) : const Color(0xFFE0E0DE);
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Arial',
    dividerColor: bordure,
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: schema.primary,
      foregroundColor: schema.onPrimary,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: schema.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: Border(bottom: BorderSide(color: bordure)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: schema.surface,
      indicatorColor: schema.primary.withValues(alpha: 0.12),
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    colorScheme: schema,
    scaffoldBackgroundColor: sombre ? const Color(0xFF121413) : Couleurs.fond,
    cardTheme: CardThemeData(
      elevation: 0,
      color: schema.surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: bordure)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: schema.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(fontFamily: 'Arial', fontSize: 15, fontWeight: FontWeight.bold),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(textStyle: const TextStyle(fontFamily: 'Arial', fontWeight: FontWeight.bold))),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        textStyle: const TextStyle(fontFamily: 'Arial', fontWeight: FontWeight.bold),
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    chipTheme: ChipThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}
