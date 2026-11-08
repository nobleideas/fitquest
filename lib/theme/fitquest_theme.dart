import 'package:flutter/material.dart';

/// FitQuest's reusable premium-dark visual foundation.
/// Apply to the app's MaterialApp later, or wrap one screen in Theme as a safe rollout.
abstract final class FitQuestTheme {
  static const background = Color(0xFF0B0E15);
  static const surface = Color(0xFF151A25);
  static const raisedSurface = Color(0xFF1C2331);
  static const accent = Color(0xFFAB8BFF);
  static const mint = Color(0xFF6BE3C3);
  static const muted = Color(0xFF9BA6BA);
  static const outline = Color(0xFF30394B);

  static final ThemeData dark = _buildDark();

  static ThemeData _buildDark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
      surface: surface,
    ).copyWith(
      primary: accent,
      onPrimary: background,
      secondary: mint,
      surface: surface,
      onSurface: const Color(0xFFF4F6FB),
      outline: outline,
      primaryContainer: const Color(0xFF2B2248),
      onPrimaryContainer: const Color(0xFFE6DCFF),
    );
    final base = ThemeData(useMaterial3: true, brightness: Brightness.dark);
    return base.copyWith(
      scaffoldBackgroundColor: background,
      colorScheme: scheme,
      dividerColor: outline,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: Color(0xFFF4F6FB),
        centerTitle: false,
        elevation: 0,
        titleTextStyle: TextStyle(fontSize: 21, fontWeight: FontWeight.w800,
            letterSpacing: -0.5, color: Color(0xFFF4F6FB)),
      ),
      textTheme: base.textTheme.copyWith(
        headlineSmall: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800,
            letterSpacing: -0.7, color: Color(0xFFF4F6FB)),
        titleMedium: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
            letterSpacing: -0.25, color: Color(0xFFF4F6FB)),
        titleSmall: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
            color: Color(0xFFF4F6FB)),
        bodyMedium: const TextStyle(fontSize: 14, color: Color(0xFFE4E9F2)),
        bodySmall: const TextStyle(fontSize: 12, color: muted),
        labelMedium: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        labelSmall: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: outline),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: raisedSurface,
        labelStyle: const TextStyle(color: muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 17, vertical: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: outline)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: outline)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: accent, width: 1.6)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent, foregroundColor: background,
          elevation: 0,
          minimumSize: const Size(0, 54),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFE6DCFF),
          minimumSize: const Size(0, 48),
          side: const BorderSide(color: outline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accent),
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        iconColor: accent, collapsedIconColor: muted,
        textColor: Color(0xFFF4F6FB), collapsedTextColor: Color(0xFFF4F6FB),
        tilePadding: EdgeInsets.symmetric(horizontal: 17, vertical: 7),
        childrenPadding: EdgeInsets.only(bottom: 6),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? accent : Colors.transparent),
        checkColor: const WidgetStatePropertyAll(background),
        side: const BorderSide(color: muted),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: raisedSurface,
        contentTextStyle: const TextStyle(color: Color(0xFFF4F6FB)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}

/// Shared section heading used across FitQuest screens.
class FitQuestSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  const FitQuestSectionHeader({super.key, required this.title, this.subtitle, this.icon});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        if (icon != null) ...[
          Icon(icon, color: FitQuestTheme.accent, size: 20),
          const SizedBox(width: 9),
        ],
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
      ]),
      if (subtitle != null) ...[
        const SizedBox(height: 5),
        Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
      ],
    ]),
  );
}

/// Reusable small metric card, for sets, rounds, volume, and future dashboard KPIs.
class FitQuestMetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? accentColor;
  const FitQuestMetricTile({super.key, required this.label,
      required this.value, required this.icon, this.accentColor});

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? FitQuestTheme.accent;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: FitQuestTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: FitQuestTheme.outline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 19),
        const SizedBox(height: 12),
        Text(value, style: const TextStyle(fontSize: 25,
            fontWeight: FontWeight.w800, letterSpacing: -0.7)),
        const SizedBox(height: 3),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}
