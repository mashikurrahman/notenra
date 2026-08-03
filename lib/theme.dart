import 'package:flutter/material.dart';

/// The Notenra design system.
///
/// Colours come straight off the brand mark: an electric clinical blue for
/// structure and action, and the green pulse that runs through the "N" for
/// anything live, healthy, or complete. Everything else is a neutral ink ramp
/// so patient data stays the loudest thing on screen.
class Nx {
  // --- Brand ---
  /// Logo blue. Primary actions, selection, focus.
  static const primary = Color(0xFF2563EB);
  static const primaryDark = Color(0xFF1D4ED8);
  static const primarySoft = Color(0xFFDCE7FD);

  /// The green pulse in the mark. Live capture, success, "ready for you".
  static const accent = Color(0xFF2F9E68);
  static const accentBright = Color(0xFF5BC98C);
  static const accentSoft = Color(0xFFE2F4EA);

  // --- Ink ramp ---
  /// Headings and anything that must read first.
  static const ink = Color(0xFF0B1B33);

  /// Body copy.
  static const secondary = Color(0xFF334155);

  /// Captions, metadata, disabled.
  static const muted = Color(0xFF64748B);

  // --- Surfaces ---
  /// App background — a barely-there blue so white cards lift off it.
  static const canvas = Color(0xFFF6F8FC);

  /// Tinted surface for inset panels and chips.
  static const surface = Color(0xFFEDF2FC);
  static const card = Color(0xFFFFFFFF);
  static const border = Color(0xFFE4EAF3);
  static const outline = Color(0xFFCBD5E1);

  // --- Semantic status ---
  static const danger = Color(0xFFDC2626);
  static const warning = Color(0xFFD97706);
  static const success = accent;
  static const info = primary;

  // --- Shape scale ---
  /// Notenra rounds generously; these are the only radii in the app.
  static const rSm = 12.0;
  static const rMd = 16.0;
  static const rLg = 22.0;
  static const rXl = 28.0;
  static const rPill = 100.0;

  // --- Spacing scale (4pt base) ---
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 20.0;
  static const s6 = 24.0;
  static const s8 = 32.0;

  // --- Gradients ---
  /// Brand panel behind headers and hero surfaces. Runs blue → deep blue with a
  /// hint of ink so the curved bottom edge reads as depth, not a flat block.
  static const headerGradient = LinearGradient(
    colors: [Color(0xFF3B82F6), primary, Color(0xFF15307A)],
    stops: [0.0, 0.42, 1.0],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const buttonGradient = LinearGradient(
    colors: [primary, primaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Used on live-capture affordances so recording always reads green, like the
  /// pulse in the logo.
  static const accentGradient = LinearGradient(
    colors: [accentBright, accent],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // --- Elevation ---
  /// Soft, diffuse elevation for prominent cards (recorder, info panels): a
  /// tight contact shadow plus a wide bloom, which reads premium rather than
  /// like a single hard drop.
  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: ink.withValues(alpha: 0.04),
          blurRadius: 3,
          offset: const Offset(0, 1),
        ),
        BoxShadow(
          color: ink.withValues(alpha: 0.06),
          blurRadius: 28,
          offset: const Offset(0, 12),
        ),
      ];

  /// Whisper-soft elevation for list rows / smaller cards.
  static List<BoxShadow> get rowShadow => [
        BoxShadow(
          color: ink.withValues(alpha: 0.035),
          blurRadius: 14,
          offset: const Offset(0, 5),
        ),
      ];

  /// Coloured glow under primary buttons for a lifted feel.
  static List<BoxShadow> get buttonGlow => [
        BoxShadow(
          color: primary.withValues(alpha: 0.28),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ];

  /// Green counterpart to [buttonGlow], for record / approve actions.
  static List<BoxShadow> get accentGlow => [
        BoxShadow(
          color: accent.withValues(alpha: 0.32),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ];

  // --- Type helpers ---
  /// The all-caps micro-label that sits above every section in the app.
  static const sectionLabel = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.1,
    color: muted,
  );

  /// Tabular digits for clocks, timers and counts, so they don't jitter.
  static const numeric = TextStyle(
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

ThemeData buildNotenraTheme() {
  final base = ColorScheme.fromSeed(
    seedColor: Nx.primary,
    primary: Nx.primary,
    secondary: Nx.accent,
    surface: Nx.card,
  );

  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: Nx.canvas,
    colorScheme: base.copyWith(
      surfaceContainerHighest: Nx.surface,
      outlineVariant: Nx.border,
      tertiary: Nx.accent,
      error: Nx.danger,
    ),
    fontFamily: 'Roboto',
    splashFactory: InkSparkle.splashFactory,

    appBarTheme: const AppBarTheme(
      backgroundColor: Nx.canvas,
      foregroundColor: Nx.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: Nx.ink,
        fontSize: 19,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
      ),
    ),

    // Tight, confident headings over comfortable body copy.
    textTheme: const TextTheme(
      headlineSmall: TextStyle(
          color: Nx.ink, fontWeight: FontWeight.w800, letterSpacing: -0.6),
      titleLarge: TextStyle(
          color: Nx.ink, fontWeight: FontWeight.w800, letterSpacing: -0.4),
      titleMedium: TextStyle(color: Nx.ink, fontWeight: FontWeight.w700),
      titleSmall: TextStyle(color: Nx.ink, fontWeight: FontWeight.w700),
      bodyMedium: TextStyle(color: Nx.secondary, height: 1.45),
      bodySmall: TextStyle(color: Nx.muted, height: 1.4),
      labelLarge: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.2),
    ),

    // Soft, filled inputs with a clean focus ring — used app-wide.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Nx.card,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: Nx.s4, vertical: Nx.s4),
      hintStyle: TextStyle(color: Nx.muted.withValues(alpha: 0.8)),
      labelStyle: const TextStyle(color: Nx.muted),
      floatingLabelStyle: const TextStyle(color: Nx.primary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Nx.rMd),
        borderSide: const BorderSide(color: Nx.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Nx.rMd),
        borderSide: const BorderSide(color: Nx.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Nx.rMd),
        borderSide: const BorderSide(color: Nx.primary, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Nx.rMd),
        borderSide: const BorderSide(color: Nx.danger),
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Nx.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 50),
        elevation: 0,
        textStyle: const TextStyle(
            fontWeight: FontWeight.w700, fontSize: 14.5, letterSpacing: 0.2),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Nx.rPill)),
      ).copyWith(
        // Sleeker, quicker press feedback than the default Material overlay.
        overlayColor:
            WidgetStateProperty.all(Colors.white.withValues(alpha: 0.12)),
      ),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Nx.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 52),
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Nx.rPill)),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Nx.primary,
        minimumSize: const Size(0, 50),
        side: const BorderSide(color: Nx.primary),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Nx.rPill)),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Nx.primary,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),

    cardTheme: CardThemeData(
      color: Nx.card,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Nx.rLg)),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: Nx.surface,
      side: const BorderSide(color: Nx.border),
      labelStyle: const TextStyle(
          color: Nx.ink, fontSize: 12, fontWeight: FontWeight.w700),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Nx.rPill)),
    ),

    dividerTheme: const DividerThemeData(
      color: Nx.border,
      thickness: 1,
      space: 1,
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Nx.ink,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Nx.rSm)),
    ),

    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Nx.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Nx.rXl)),
      ),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: Nx.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Nx.rLg)),
    ),

    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Nx.primary,
      linearTrackColor: Nx.surface,
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Nx.card,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Nx.primary.withValues(alpha: 0.12),
      elevation: 0,
      height: 68,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: states.contains(WidgetState.selected) ? Nx.primary : Nx.muted,
          )),
    ),
  );
}
