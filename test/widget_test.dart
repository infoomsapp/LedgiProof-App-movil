// The scaffolded counter smoke test doesn't apply anymore (LedgiProofApp
// initializes Supabase in main() before runApp, so pumping it directly here
// would need a mocked Supabase client -- out of scope for this shell pass).
// These cover the two-palette theme instead, including the contrast rules the
// dark palette was adjusted for on 2026-09-24: the old border and muted-ink
// tokens did not separate from their own background on a phone, and both
// palettes shared a selected-tab colour that was darker than the bar under it.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgiproof/theme/app_theme.dart';

/// WCAG 2.1 relative luminance. Color.r/.g/.b are 0..1 doubles on Flutter 3.44.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// WCAG contrast ratio, 1:1 (identical) to 21:1 (black on white).
double contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('dark palette builds a dark theme using the brand primary colour', () {
    final theme = buildAppTheme(LpPalette.dark);
    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.primary, LpPalette.dark.primary);
  });

  test('light palette builds a light theme', () {
    final theme = buildAppTheme(LpPalette.light);
    expect(theme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, LpPalette.light.bg);
  });

  test('body text clears WCAG AA against its own surface in both palettes', () {
    for (final p in <LpPalette>[LpPalette.dark, LpPalette.light]) {
      expect(contrast(p.ink, p.surface), greaterThan(4.5),
          reason: 'ink on surface (${p.brightness})');
      expect(contrast(p.inkMuted, p.surface), greaterThan(4.5),
          reason: 'inkMuted on surface (${p.brightness})');
      expect(contrast(p.inkSubtle, p.surface), greaterThan(3.0),
          reason: 'inkSubtle on surface (${p.brightness})');
    }
  });

  test('borders are actually visible against their surface', () {
    // The original dark border (0xFF243147) sat near 1.3:1 against the
    // background, which is why dividers read as absent rather than faint.
    for (final p in <LpPalette>[LpPalette.dark, LpPalette.light]) {
      expect(contrast(p.border, p.surface), greaterThan(1.5),
          reason: 'border on surface (${p.brightness})');
    }
  });

  test('the selected bottom-nav colour lifts off the bar it sits on', () {
    for (final p in <LpPalette>[LpPalette.dark, LpPalette.light]) {
      final theme = buildAppTheme(p);
      final selected = theme.bottomNavigationBarTheme.selectedItemColor!;
      expect(contrast(selected, p.surface), greaterThan(3.0),
          reason: 'selected tab on nav bar (${p.brightness})');
    }
  });

  test('AppColors follows whichever palette is active', () {
    AppColors.use(LpPalette.light);
    expect(AppColors.ink, LpPalette.light.ink);
    AppColors.use(LpPalette.dark);
    expect(AppColors.ink, LpPalette.dark.ink);
  });

  test('theme controller defaults to system and resolves from the platform',
      () {
    final c = LpThemeController();
    expect(c.mode, LpThemeMode.system);
    expect(c.resolve(Brightness.light), LpPalette.light);
    expect(c.resolve(Brightness.dark), LpPalette.dark);
  });
}
