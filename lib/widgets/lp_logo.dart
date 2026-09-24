import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The LedgiProof lockup, picking the variant that is legible on the palette
/// currently in use.
///
/// The source file (assets/brand/logo_full.png, copied from the web app) is
/// black ink printed on a white plate. Dropping that straight onto the dark
/// theme would show a white card; dropping the inverted one onto the light
/// theme would show white-on-white. Hence two pre-processed variants, chosen
/// here rather than at every call site.
class LpLogo extends StatelessWidget {
  final double height;

  const LpLogo({super.key, this.height = 96});

  @override
  Widget build(BuildContext context) {
    final onDark = AppColors.palette.brightness == Brightness.dark;
    return Image.asset(
      onDark
          ? 'assets/brand/logo_full_ondark.png'
          : 'assets/brand/logo_full_onlight.png',
      height: height,
      fit: BoxFit.contain,
      semanticLabel: 'LedgiProof',
      // A missing asset should not take the sign-in screen down with it.
      errorBuilder: (context, error, stack) => Text(
        'LedgiProof',
        style: TextStyle(
          fontSize: height * 0.3,
          fontWeight: FontWeight.w800,
          color: AppColors.ink,
        ),
      ),
    );
  }
}
