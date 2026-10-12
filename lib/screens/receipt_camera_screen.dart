import 'dart:io';
import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../theme/app_theme.dart';

/// LedgiProof's own camera for receipts: a sharp photo is what lets the
/// on-device reader (ReceiptReader) read every line. Continuous autofocus,
/// tap anywhere to focus (and expose) on that spot, flash off / auto /
/// light, and a frame to fill with the receipt. Returns the photo's path,
/// or null when the person backs out.
class ReceiptCameraScreen extends StatefulWidget {
  const ReceiptCameraScreen({super.key});

  @override
  State<ReceiptCameraScreen> createState() => _ReceiptCameraScreenState();
}

class _ReceiptCameraScreenState extends State<ReceiptCameraScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  String? _error;
  bool _taking = false;
  FlashMode _flash = FlashMode.off;
  Offset? _focusAt; // where the person tapped, in preview pixels
  int _focusTick = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _controller = null;
      c.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _start();
    }
  }

  Future<void> _start() async {
    try {
      final cameras = await availableCameras();
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final c = CameraController(back, ResolutionPreset.max,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      await c.initialize();
      await c.setFocusMode(FocusMode.auto);
      await c.setExposureMode(ExposureMode.auto);
      await c.setFlashMode(_flash);
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _controller = c;
        _error = null;
      });
    } on CameraException catch (e) {
      setState(() => _error = e.code == 'CameraAccessDenied' || e.code == 'CameraAccessDeniedWithoutPrompt'
          ? 'LedgiProof needs camera access to scan receipts. Turn it on in Settings.'
          : "Couldn't open the camera.");
    } catch (_) {
      setState(() => _error = "Couldn't open the camera.");
    }
  }

  /// Tap to focus: autofocus and exposure on that spot of the receipt.
  Future<void> _focus(TapUpDetails d, BoxConstraints size) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final p = Offset(
      (d.localPosition.dx / size.maxWidth).clamp(0.0, 1.0),
      (d.localPosition.dy / size.maxHeight).clamp(0.0, 1.0),
    );
    setState(() {
      _focusAt = d.localPosition;
      _focusTick++;
    });
    final tick = _focusTick;
    try {
      await c.setFocusMode(FocusMode.auto);
      if (c.value.focusPointSupported) await c.setFocusPoint(p);
      if (c.value.exposurePointSupported) await c.setExposurePoint(p);
    } on CameraException {
      // Some lenses have no focus point; continuous autofocus still runs.
    }
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (mounted && tick == _focusTick) setState(() => _focusAt = null);
  }

  Future<void> _cycleFlash() async {
    final next = switch (_flash) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.torch,
      _ => FlashMode.off,
    };
    try {
      await _controller?.setFlashMode(next);
      setState(() => _flash = next);
    } on CameraException {
      // No flash on this camera.
    }
  }

  Future<void> _take() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _taking) return;
    setState(() => _taking = true);
    try {
      final shot = await c.takePicture();
      final dir = (await getTemporaryDirectory()).path;
      final out = '$dir/receipt_${DateTime.now().millisecondsSinceEpoch}.jpg';
      // Upright, at most 2400 px, JPEG 88 -- sharp enough to read, small
      // enough to upload.
      await Isolate.run(() => _shrink(shot.path, out));
      if (mounted) Navigator.of(context).pop(out);
    } catch (_) {
      if (mounted) {
        setState(() => _taking = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't take the photo. Try again.")));
      }
    }
  }

  static void _shrink(String from, String to) {
    var photo = img.decodeImage(File(from).readAsBytesSync());
    if (photo == null) throw const FormatException('Not an image');
    photo = img.bakeOrientation(photo);
    const maxSide = 2400;
    final longSide = photo.width > photo.height ? photo.width : photo.height;
    if (longSide > maxSide) {
      final s = maxSide / longSide;
      photo = img.copyResize(photo,
          width: (photo.width * s).round(), height: (photo.height * s).round(), interpolation: img.Interpolation.average);
    }
    File(to).writeAsBytesSync(img.encodeJpg(photo, quality: 88));
    try {
      File(from).deleteSync();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan receipt', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        actions: [
          if (c != null)
            IconButton(
              tooltip: 'Flash',
              onPressed: _cycleFlash,
              icon: Icon(switch (_flash) {
                FlashMode.auto => Icons.flash_auto,
                FlashMode.torch => Icons.flashlight_on,
                _ => Icons.flash_off,
              }),
            ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
              ),
            )
          : c == null || !c.value.isInitialized
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: AspectRatio(
                          // The preview's ratio is landscape; the phone is held upright.
                          aspectRatio: 1 / c.value.aspectRatio,
                          child: LayoutBuilder(
                            builder: (context, size) => GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapUp: (d) => _focus(d, size),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  CameraPreview(c),
                                  const IgnorePointer(child: _ReceiptFrame()),
                                  if (_focusAt != null)
                                    Positioned(
                                      left: _focusAt!.dx - 32,
                                      top: _focusAt!.dy - 32,
                                      child: const IgnorePointer(child: _FocusRing()),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                      child: Text('Fill the frame with the receipt · tap the text to focus',
                          textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12.5)),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 18, top: 6),
                        child: GestureDetector(
                          onTap: _take,
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
                            ),
                            padding: const EdgeInsets.all(5),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _taking ? Colors.white38 : Colors.white,
                              ),
                              child: _taking
                                  ? Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary),
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

/// Corner marks of the area to fill with the receipt.
class _ReceiptFrame extends StatelessWidget {
  const _ReceiptFrame();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: CustomPaint(painter: _FramePainter()),
    );
  }
}

class _FramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const l = 28.0;
    for (final (x, y, dx, dy) in [(0.0, 0.0, 1.0, 1.0), (s.width, 0.0, -1.0, 1.0), (0.0, s.height, 1.0, -1.0), (s.width, s.height, -1.0, -1.0)]) {
      canvas.drawLine(Offset(x, y), Offset(x + dx * l, y), p);
      canvas.drawLine(Offset(x, y), Offset(x, y + dy * l), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Shown where the person tapped to focus.
class _FocusRing extends StatelessWidget {
  const _FocusRing();

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1.4, end: 1),
      duration: const Duration(milliseconds: 220),
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.amberAccent, width: 2),
        ),
      ),
    );
  }
}
