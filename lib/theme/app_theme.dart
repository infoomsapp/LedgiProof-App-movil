import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Mirrors the web app's CSS tokens (src/index.css --lp-* / --sem-*), so the
// mobile shell reads as the same product instead of a reskin.
//
// Light mode was added on 2026-09-24. Screens keep reading their colours
// through `AppColors.<token>`, which used to be compile time constants and are
// now getters resolving against whichever palette is active, so no screen has
// to know a theme exists. main.dart swaps the palette in one place.

/// One complete set of colour tokens. Two instances exist: [dark] and [light].
@immutable
class LpPalette {
  final Brightness brightness;

  final Color primary;
  final Color primaryInk;
  final Color accent;

  final Color bg;
  final Color surface;
  final Color surface2;
  final Color border;

  final Color ink;
  final Color inkMuted;
  final Color inkSubtle;

  final Color green;
  final Color greenBg;
  final Color amber;
  final Color amberBg;
  final Color red;
  final Color redBg;
  final Color blueBg;
  final Color cyan;
  final Color cyanBg;

  const LpPalette({
    required this.brightness,
    required this.primary,
    required this.primaryInk,
    required this.accent,
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.border,
    required this.ink,
    required this.inkMuted,
    required this.inkSubtle,
    required this.green,
    required this.greenBg,
    required this.amber,
    required this.amberBg,
    required this.red,
    required this.redBg,
    required this.blueBg,
    required this.cyan,
    required this.cyanBg,
  });

  /// Dark palette. Three tokens were lightened from their original values
  /// because they did not separate from their own background on a phone:
  /// `border` (0xFF243147 read as no line at all against 0xFF0B1220),
  /// `inkSubtle` (0xFF6B7996) and `inkMuted` (0xFF9AA8C2).
  static const dark = LpPalette(
    brightness: Brightness.dark,
    primary: Color(0xFF3B82F6),
    primaryInk: Color(0xFF60A5FA),
    accent: Color(0xFF22B8CF),
    bg: Color(0xFF0B1220),
    surface: Color(0xFF121A2B),
    surface2: Color(0xFF0F1625),
    border: Color(0xFF33425C),
    ink: Color(0xFFEEF2F9),
    inkMuted: Color(0xFFB2BFD6),
    inkSubtle: Color(0xFF8E9BB8),
    green: Color(0xFF4ADE80),
    greenBg: Color(0xFF0F2418),
    amber: Color(0xFFFBBF24),
    amberBg: Color(0xFF2A2008),
    red: Color(0xFFF87171),
    redBg: Color(0xFF2A1212),
    blueBg: Color(0xFF0F1E35),
    cyan: Color(0xFF2DD4D4),
    cyanBg: Color(0xFF0A2323),
  );

  /// Light palette. The semantic colours are NOT the dark ones reused: a tone
  /// that reads correctly on navy is unreadable on white, so each one is the
  /// darker step of the same hue, paired with a pale background of that hue.
  static const light = LpPalette(
    brightness: Brightness.light,
    primary: Color(0xFF2563EB),
    primaryInk: Color(0xFF1D4ED8),
    accent: Color(0xFF0E7490),
    bg: Color(0xFFF5F7FB),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFEDF1F7),
    border: Color(0xFFC3CEDE),
    ink: Color(0xFF0B1220),
    inkMuted: Color(0xFF475569),
    inkSubtle: Color(0xFF64748B),
    green: Color(0xFF15803D),
    greenBg: Color(0xFFDCFCE7),
    amber: Color(0xFFB45309),
    amberBg: Color(0xFFFEF3C7),
    red: Color(0xFFDC2626),
    redBg: Color(0xFFFEE2E2),
    blueBg: Color(0xFFDBEAFE),
    cyan: Color(0xFF0E7490),
    cyanBg: Color(0xFFCFFAFE),
  );
}

/// Which palette the app is currently painting with.
///
/// Every screen keeps calling `AppColors.ink` and friends exactly as before;
/// these are getters now instead of constants, which is why expressions that
/// used to be `const` no longer are.
class AppColors {
  static LpPalette _active = LpPalette.dark;

  static LpPalette get palette => _active;
  static void use(LpPalette p) => _active = p;

  static Color get primary => _active.primary;
  static Color get primaryInk => _active.primaryInk;
  static Color get accent => _active.accent;

  static Color get bg => _active.bg;
  static Color get surface => _active.surface;
  static Color get surface2 => _active.surface2;
  static Color get border => _active.border;

  static Color get ink => _active.ink;
  static Color get inkMuted => _active.inkMuted;
  static Color get inkSubtle => _active.inkSubtle;

  static Color get green => _active.green;
  static Color get greenBg => _active.greenBg;
  static Color get amber => _active.amber;
  static Color get amberBg => _active.amberBg;
  static Color get red => _active.red;
  static Color get redBg => _active.redBg;
  static Color get blueBg => _active.blueBg;
  static Color get cyan => _active.cyan;
  static Color get cyanBg => _active.cyanBg;
}

Map<String, Color> get semaphoreColors => <String, Color>{
      'blue': AppColors.cyan,
      'green': AppColors.green,
      'amber': AppColors.amber,
      'red': AppColors.red,
    };

/// What the user picked in Settings. `system` follows the phone.
enum LpThemeMode { system, light, dark }

/// Owns the choice, persists it, and tells the app to rebuild.
class LpThemeController extends ChangeNotifier {
  static const _prefsKey = 'ledgiproof_theme_mode';

  LpThemeMode _mode = LpThemeMode.system;
  LpThemeMode get mode => _mode;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      _mode = LpThemeMode.values.firstWhere(
        (m) => m.name == saved,
        orElse: () => LpThemeMode.system,
      );
    } catch (_) {
      // A device that cannot read preferences still gets a usable app.
      _mode = LpThemeMode.system;
    }
    notifyListeners();
  }

  Future<void> setMode(LpThemeMode next) async {
    if (next == _mode) return;
    _mode = next;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, next.name);
    } catch (_) {
      // Persisting is a convenience; the choice still applies this session.
    }
  }

  /// Resolves the chosen mode against the phone's own setting.
  LpPalette resolve(Brightness platformBrightness) {
    switch (_mode) {
      case LpThemeMode.light:
        return LpPalette.light;
      case LpThemeMode.dark:
        return LpPalette.dark;
      case LpThemeMode.system:
        return platformBrightness == Brightness.light
            ? LpPalette.light
            : LpPalette.dark;
    }
  }
}

/// Keeps the Android status and navigation bars in step with the palette, so
/// the system icons stay readable instead of white on white.
void applySystemChrome(LpPalette p) {
  final isDark = p.brightness == Brightness.dark;
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: p.surface,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
    ),
  );
}

ThemeData buildAppTheme(LpPalette p) {
  final isDark = p.brightness == Brightness.dark;

  return ThemeData(
    useMaterial3: true,
    brightness: p.brightness,
    scaffoldBackgroundColor: p.bg,
    colorScheme: ColorScheme(
      brightness: p.brightness,
      primary: p.primary,
      onPrimary: Colors.white,
      secondary: p.accent,
      onSecondary: Colors.white,
      error: p.red,
      onError: isDark ? const Color(0xFF2A1212) : Colors.white,
      surface: p.surface,
      onSurface: p.ink,
    ),
    canvasColor: p.bg,
    cardColor: p.surface,
    dividerColor: p.border,
    dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      foregroundColor: p.ink,
      elevation: 0,
      centerTitle: false,
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: p.surface,
      // Was `primaryInk` for both palettes, which in dark mode painted the
      // SELECTED tab in a blue darker than the bar behind it, making the
      // active tab the hardest one to see. Each palette now names a tone that
      // lifts off its own surface.
      selectedItemColor: isDark ? p.primaryInk : p.primary,
      unselectedItemColor: p.inkSubtle,
      type: BottomNavigationBarType.fixed,
      showUnselectedLabels: true,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      labelStyle: TextStyle(color: p.inkMuted),
      hintStyle: TextStyle(color: p.inkSubtle),
      enabledBorder:
          OutlineInputBorder(borderSide: BorderSide(color: p.border)),
      focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: p.primary, width: 1.6)),
      border: const OutlineInputBorder(),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: isDark ? p.surface2 : const Color(0xFF1F2937),
      contentTextStyle: const TextStyle(color: Color(0xFFEEF2F9)),
      behavior: SnackBarBehavior.floating,
    ),
    listTileTheme: ListTileThemeData(iconColor: p.inkMuted, textColor: p.ink),
    iconTheme: IconThemeData(color: p.inkMuted),
    textTheme: TextTheme(
      titleLarge: TextStyle(color: p.ink),
      titleMedium: TextStyle(color: p.ink),
      bodyLarge: TextStyle(color: p.ink),
      bodyMedium: TextStyle(color: p.ink),
      bodySmall: TextStyle(color: p.inkMuted),
      labelLarge: TextStyle(color: p.ink),
    ),
  );
}
