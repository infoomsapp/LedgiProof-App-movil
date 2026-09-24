// The scaffolded counter smoke test doesn't apply anymore (LedgiProofApp
// initializes Supabase in main() before runApp, so pumping it directly here
// would need a mocked Supabase client -- out of scope for this shell pass).
// This checks the theme builds without a live Supabase session instead.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgiproof/theme/app_theme.dart';

void main() {
  test('buildAppTheme returns a dark theme using the brand primary color', () {
    final theme = buildAppTheme();
    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.primary, AppColors.primary);
  });
}
