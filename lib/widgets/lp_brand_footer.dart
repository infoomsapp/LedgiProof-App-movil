import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// "LedgiProof by Olimsys" -- at the bottom of the sign-in screen and of More.
class LpBrandFooter extends StatelessWidget {
  const LpBrandFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Text(
        'LedgiProof by Olimsys',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11.5, color: AppColors.inkSubtle, letterSpacing: 0.2),
      ),
    );
  }
}
