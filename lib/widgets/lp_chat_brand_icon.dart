import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The chat feature's own mark, drawn to match the web's ChatBrandIcon.tsx
/// exactly (same viewBox proportions, same colors) so the feature reads as
/// one product across platforms: a light-blue circle, a white speech bubble,
/// four dots in LedgiProof's OWN semaphore palette (the same tokens the
/// transaction semaphore and the chat bubble's own priority ring already
/// use, read live off AppColors so this follows the active light/dark
/// theme) -- not a generic four-color scheme. Pure CustomPainter -- no SVG
/// package needed for one small vector mark.
class LpChatBrandIcon extends StatelessWidget {
  final double size;
  const LpChatBrandIcon({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _ChatBrandPainter()),
    );
  }
}

class _ChatBrandPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Drawn in a 48x48 design space, then scaled to fit.
    const design = 48.0;
    final scale = size.width / design;
    canvas.save();
    canvas.scale(scale, scale);

    final bgPaint = Paint()..color = const Color(0xFF5FC6EA);
    canvas.drawCircle(const Offset(24, 24), 24, bgPaint);

    final whitePaint = Paint()..color = Colors.white;

    final tail = Path()
      ..moveTo(18, 30)
      ..lineTo(14, 36)
      ..lineTo(23, 30)
      ..close();
    canvas.drawPath(tail, whitePaint);

    final bubble = RRect.fromRectAndRadius(
      const Rect.fromLTWH(10, 14, 28, 16),
      const Radius.circular(8),
    );
    canvas.drawRRect(bubble, whitePaint);

    // Same four keys semaphoreColors (app_theme.dart) maps for every other
    // semaphore dot in the app -- 'blue' is AppColors.cyan there, not a
    // literal blue, so read it the same way rather than re-guessing a hex.
    final dotColors = [
      semaphoreColors['blue']!,
      semaphoreColors['green']!,
      semaphoreColors['amber']!,
      semaphoreColors['red']!,
    ];
    const dotXs = [15.0, 21.0, 27.0, 33.0];
    for (var i = 0; i < 4; i++) {
      canvas.drawCircle(Offset(dotXs[i], 22), 2.3, Paint()..color = dotColors[i]);
    }

    canvas.restore();
  }

  // AppColors is a mutable static palette (light/dark toggles at runtime),
  // not a value captured on this delegate -- always repaint so a theme
  // switch is never left showing the previous palette's dots.
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
