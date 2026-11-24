import 'package:flutter/material.dart';

/// Colours for the bookshelf scene (wall, wood, plaque text).
@immutable
class ShelfPalette extends ThemeExtension<ShelfPalette> {
  const ShelfPalette({
    required this.wallTop,
    required this.wallBottom,
    required this.woodLight,
    required this.woodDark,
    required this.plaqueText,
    required this.accent,
  });

  final Color wallTop, wallBottom, woodLight, woodDark, plaqueText, accent;

  static ShelfPalette of(BuildContext context) =>
      Theme.of(context).extension<ShelfPalette>()!;

  static const light = ShelfPalette(
    wallTop: Color(0xFFF1E6D3),
    wallBottom: Color(0xFFDCC7A6),
    woodLight: Color(0xFFA9743F),
    woodDark: Color(0xFF6B4423),
    plaqueText: Color(0xFFFBF1DC),
    accent: Color(0xFFC9962B),
  );

  static const dark = ShelfPalette(
    wallTop: Color(0xFF2A2320),
    wallBottom: Color(0xFF17120F),
    woodLight: Color(0xFF5C3B22),
    woodDark: Color(0xFF35200F),
    plaqueText: Color(0xFFE9D9B8),
    accent: Color(0xFFE0B04F),
  );

  @override
  ShelfPalette copyWith({
    Color? wallTop,
    Color? wallBottom,
    Color? woodLight,
    Color? woodDark,
    Color? plaqueText,
    Color? accent,
  }) =>
      ShelfPalette(
        wallTop: wallTop ?? this.wallTop,
        wallBottom: wallBottom ?? this.wallBottom,
        woodLight: woodLight ?? this.woodLight,
        woodDark: woodDark ?? this.woodDark,
        plaqueText: plaqueText ?? this.plaqueText,
        accent: accent ?? this.accent,
      );

  @override
  ShelfPalette lerp(ThemeExtension<ShelfPalette>? other, double t) {
    if (other is! ShelfPalette) return this;
    return ShelfPalette(
      wallTop: Color.lerp(wallTop, other.wallTop, t)!,
      wallBottom: Color.lerp(wallBottom, other.wallBottom, t)!,
      woodLight: Color.lerp(woodLight, other.woodLight, t)!,
      woodDark: Color.lerp(woodDark, other.woodDark, t)!,
      plaqueText: Color.lerp(plaqueText, other.plaqueText, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
    );
  }
}

class AppTheme {
  AppTheme._();

  /// Serif stack used for covers and headings (falls back per platform).
  static const serifFallback = [
    'Georgia',
    'Cambria',
    'Times New Roman',
    'serif',
  ];

  static ThemeData light() => _build(Brightness.light, ShelfPalette.light);
  static ThemeData dark() => _build(Brightness.dark, ShelfPalette.dark);

  static ThemeData _build(Brightness b, ShelfPalette p) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF8B5A2B),
      brightness: b,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: b,
      scaffoldBackgroundColor: p.wallTop,
      extensions: [p],
      appBarTheme: AppBarTheme(
        backgroundColor: p.woodDark,
        foregroundColor: p.plaqueText,
        elevation: 4,
        titleTextStyle: TextStyle(
          fontFamilyFallback: serifFallback,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: p.plaqueText,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: b == Brightness.light
            ? Colors.white.withValues(alpha: 0.7)
            : Colors.black.withValues(alpha: 0.35),
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
