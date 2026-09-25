import 'package:flutter/material.dart';

/// The read-receipt mark for your own messages: a full circle outline while
/// sent-but-unread, with the check drawing itself inside the moment the
/// other side reads it. The circle never sweeps open/closed -- only its
/// color changes; what appears is the check. Matches the web app's own
/// AuditedStatusCheck.tsx exactly, including the deliberately-not-brand-
/// accent blue (see the color note below).
enum MessageReceiptState { sent, read }

// Deliberately its own color, not AppColors.primary -- this app's own
// accent visually reads as ControlMiles' brand blue (a separate product),
// and this mark shouldn't borrow that identity. Matches the web's own
// AuditedStatusCheck.tsx exactly.
const Color kAuditedCheckBlue = Color(0xFF007AFF);

class AuditedStatusCheck extends StatefulWidget {
  final MessageReceiptState state;
  final double size;
  final Color activeColor;
  final Color pendingColor;

  const AuditedStatusCheck({
    super.key,
    required this.state,
    this.size = 15.0,
    this.activeColor = kAuditedCheckBlue,
    this.pendingColor = const Color(0xFF9E9E9E),
  });

  @override
  State<AuditedStatusCheck> createState() => _AuditedStatusCheckState();
}

class _AuditedStatusCheckState extends State<AuditedStatusCheck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _checkProgress;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    // The circle is always full -- only the check animates in.
    _checkProgress = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );

    if (widget.state == MessageReceiptState.read) _controller.value = 1;
  }

  @override
  void didUpdateWidget(covariant AuditedStatusCheck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      if (widget.state == MessageReceiptState.read) {
        _controller.forward();
      } else {
        _controller.reset();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _CheckPainter(
            state: widget.state,
            checkProgress: _checkProgress.value,
            circleColor: widget.state == MessageReceiptState.read
                ? widget.activeColor
                : widget.pendingColor,
            checkColor: widget.activeColor,
          ),
        );
      },
    );
  }
}

class _CheckPainter extends CustomPainter {
  final MessageReceiptState state;
  final double checkProgress;
  final Color circleColor;
  final Color checkColor;

  _CheckPainter({
    required this.state,
    required this.checkProgress,
    required this.circleColor,
    required this.checkColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.width * 0.16;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Always a full circle -- only its color changes on read. What
    // appears/disappears is the check inside it.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = circleColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );

    if (checkProgress > 0.0) {
      final paint = Paint()
        ..color = checkColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final path = Path();
      final p1 = Offset(size.width * 0.28, size.height * 0.52);
      final p2 = Offset(size.width * 0.44, size.height * 0.70);
      final p3 = Offset(size.width * 0.86, size.height * 0.32);

      path.moveTo(p1.dx, p1.dy);

      if (checkProgress <= 0.4) {
        final t = checkProgress / 0.4;
        path.lineTo(
          p1.dx + (p2.dx - p1.dx) * t,
          p1.dy + (p2.dy - p1.dy) * t,
        );
      } else {
        path.lineTo(p2.dx, p2.dy);
        final t = (checkProgress - 0.4) / 0.6;
        path.lineTo(
          p2.dx + (p3.dx - p2.dx) * t,
          p2.dy + (p3.dy - p2.dy) * t,
        );
      }

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CheckPainter oldDelegate) {
    return oldDelegate.checkProgress != checkProgress ||
        oldDelegate.circleColor != circleColor ||
        oldDelegate.checkColor != checkColor ||
        oldDelegate.state != state;
  }
}
