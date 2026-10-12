import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// The math of LedgiProof's on-device receipt reader (OCR plan N1): the same
/// PaddleOCR PP-OCRv5 mobile pipeline the web runs (paddleocr-js), written
/// out so it runs on the phone with no external engine. Pure Dart -- no
/// plugins -- so it runs in an isolate and in `flutter test`.
///
///   prepareDet   photo -> upright, at most [maxSide] px, detector input
///                (long side 960, multiples of 32, ImageNet mean/std, BGR)
///   dbBoxes      detector probability map -> rotated text boxes (DB
///                post-process: threshold 0.3, region score 0.6, unclip 1.5)
///   prepareRec   one box, read straight along its tilt -> recognizer input
///                (height 48, BGR, (x/255-.5)/.5)
///   ctcDecode    recognizer output -> text + score (greedy CTC)
///
/// Checked against the Python reference (same models, same numbers) before
/// it shipped.

const int maxSide = 1600;

class DetInput {
  DetInput(this.tensor, this.dw, this.dh, this.rgb, this.w, this.h);
  final Float32List tensor; // 1 x 3 x dh x dw
  final int dw, dh;
  final Uint8List rgb; // the upright photo, w x h x 3
  final int w, h;
}

/// A text line as a rotated rectangle in photo pixels: its center, the
/// unit vectors along (u) and across (v) the text, and the half-lengths.
/// Receipts are rarely photographed straight; the line is read along its
/// own direction.
class TextBox {
  const TextBox(this.cx, this.cy, this.ux, this.uy, this.vx, this.vy, this.hu, this.hv);
  final double cx, cy, ux, uy, vx, vy, hu, hv;

  /// Top-left, top-right, bottom-right, bottom-left (reading direction).
  List<List<int>> get corners => [
        for (final (a, b) in const [(-1, -1), (1, -1), (1, 1), (-1, 1)])
          [(cx + a * hu * ux + b * hv * vx).round(), (cy + a * hu * uy + b * hv * vy).round()],
      ];
}

class RecInput {
  RecInput(this.tensor, this.width);
  final Float32List tensor; // 1 x 3 x 48 x width
  final int width;
}

/// Decodes the photo, applies its EXIF rotation, scales it down to
/// [maxSide] and builds the detector input.
DetInput prepareDet(Uint8List bytes) {
  var photo = img.decodeImage(bytes);
  if (photo == null) throw const FormatException('Not an image');
  photo = img.bakeOrientation(photo);
  final scale = maxSide / math.max(photo.width, photo.height);
  if (scale < 1) {
    photo = img.copyResize(photo,
        width: (photo.width * scale).round(),
        height: (photo.height * scale).round(),
        interpolation: img.Interpolation.linear);
  }
  final w = photo.width, h = photo.height;
  final rgb = Uint8List(w * h * 3);
  var i = 0;
  for (final p in photo) {
    rgb[i++] = p.r.toInt();
    rgb[i++] = p.g.toInt();
    rgb[i++] = p.b.toInt();
  }

  final r = 960 / math.max(w, h);
  final dh = math.max(32, (h * r / 32).round() * 32);
  final dw = math.max(32, (w * r / 32).round() * 32);
  final small = img.copyResize(img.Image.fromBytes(width: w, height: h, bytes: rgb.buffer, numChannels: 3),
      width: dw, height: dh, interpolation: img.Interpolation.linear);
  // BGR channel order, ImageNet mean/std in that order (as PaddleOCR does).
  const mean = [0.485, 0.456, 0.406], std = [0.229, 0.224, 0.225];
  final plane = dw * dh;
  final t = Float32List(3 * plane);
  for (var y = 0; y < dh; y++) {
    for (var x = 0; x < dw; x++) {
      final p = small.getPixel(x, y);
      final o = y * dw + x;
      t[o] = ((p.b / 255) - mean[0]) / std[0];
      t[plane + o] = ((p.g / 255) - mean[1]) / std[1];
      t[2 * plane + o] = ((p.r / 255) - mean[2]) / std[2];
    }
  }
  return DetInput(t, dw, dh, rgb, w, h);
}

/// DB post-process: connected regions above 0.3, kept when the mean
/// probability of their own pixels is at least 0.6; each region's long
/// axis (principal component) gives the line's direction, the rectangle is
/// grown by the unclip ratio and mapped back to the photo. Top to bottom.
List<TextBox> dbBoxes(List<double> prob, int dw, int dh, int w, int h,
    {double thresh = 0.3, double boxThresh = 0.6, double unclip = 1.5}) {
  final seen = Uint8List(dw * dh);
  final boxes = <TextBox>[];
  final stack = <int>[];
  final sx = w / dw, sy = h / dh;
  for (var start = 0; start < dw * dh; start++) {
    if (seen[start] == 1 || prob[start] <= thresh) continue;
    final px = <int>[], py = <int>[];
    var probSum = 0.0;
    seen[start] = 1;
    stack.add(start);
    while (stack.isNotEmpty) {
      final k = stack.removeLast();
      final x = k % dw, y = k ~/ dw;
      px.add(x);
      py.add(y);
      probSum += prob[k];
      for (final n in [if (y + 1 < dh) k + dw, if (y > 0) k - dw, if (x + 1 < dw) k + 1, if (x > 0) k - 1]) {
        if (seen[n] == 0 && prob[n] > thresh) {
          seen[n] = 1;
          stack.add(n);
        }
      }
    }
    final n = px.length;
    if (n < 10 || probSum / n < boxThresh) continue;

    var mx = 0.0, my = 0.0;
    for (var i = 0; i < n; i++) {
      mx += px[i];
      my += py[i];
    }
    mx /= n;
    my /= n;
    var cxx = 0.0, cyy = 0.0, cxy = 0.0;
    for (var i = 0; i < n; i++) {
      final dx = px[i] - mx, dy = py[i] - my;
      cxx += dx * dx;
      cyy += dy * dy;
      cxy += dx * dy;
    }
    final ang = 0.5 * math.atan2(2 * cxy, cxx - cyy); // long axis
    final ux = math.cos(ang), uy = math.sin(ang), vx = -uy, vy = ux;
    var umin = double.infinity, umax = -double.infinity, vmin = double.infinity, vmax = -double.infinity;
    for (var i = 0; i < n; i++) {
      final dx = px[i] - mx, dy = py[i] - my;
      final pu = dx * ux + dy * uy, pv = dx * vx + dy * vy;
      if (pu < umin) umin = pu;
      if (pu > umax) umax = pu;
      if (pv < vmin) vmin = pv;
      if (pv > vmax) vmax = pv;
    }
    final lu = umax - umin + 1, lv = vmax - vmin + 1;
    if (math.min(lu, lv) < 3) continue;
    final d = lu * lv * unclip / (2 * (lu + lv));
    final cu = (umax + umin) / 2, cv = (vmax + vmin) / 2;
    final ccx = mx + cu * ux + cv * vx, ccy = my + cu * uy + cv * vy;

    // Back to photo pixels (the detector saw a resized photo).
    var tux = ux * sx, tuy = uy * sy, tvx = vx * sx, tvy = vy * sy;
    final nu = math.sqrt(tux * tux + tuy * tuy), nv = math.sqrt(tvx * tvx + tvy * tvy);
    final hu = (lu / 2 + d) * nu, hv = (lv / 2 + d) * nv;
    tux /= nu;
    tuy /= nu;
    tvx /= nv;
    tvy /= nv;
    if (tux < 0) {
      tux = -tux;
      tuy = -tuy;
      tvx = -tvx;
      tvy = -tvy;
    }
    boxes.add(TextBox((ccx + 0.5) * sx, (ccy + 0.5) * sy, tux, tuy, tvx, tvy, hu, hv));
  }
  boxes.sort((a, b) {
    final ka = a.cy - a.hv, kb = b.cy - b.hv;
    return ka != kb ? ka.compareTo(kb) : a.cx.compareTo(b.cx);
  });
  return boxes;
}

/// One text box -> recognizer input: the line sampled straight along its
/// own direction (bilinear), 48 px high, at least 320 wide (zero padded on
/// the right), BGR, (x/255 - 0.5) / 0.5.
RecInput prepareRec(Uint8List rgb, int w, int h, TextBox b) {
  final ratio = b.hu / math.max(b.hv, 1e-6);
  final rw = math.max(1, (48 * ratio).ceil());
  final width = math.max(320, rw);
  final plane = 48 * width;
  final t = Float32List(3 * plane); // padding stays 0
  double px(int x, int y, int c) => rgb[(y * w + x) * 3 + c].toDouble();
  for (var j = 0; j < 48; j++) {
    final fj = (j + 0.5) / 48 * 2 - 1;
    for (var i = 0; i < rw; i++) {
      final fi = (i + 0.5) / rw * 2 - 1;
      var x = b.cx + fi * b.hu * b.ux + fj * b.hv * b.vx;
      var y = b.cy + fi * b.hu * b.uy + fj * b.hv * b.vy;
      x = x.clamp(0, w - 1.001);
      y = y.clamp(0, h - 1.001);
      final x0 = x.floor(), y0 = y.floor();
      final fx = x - x0, fy = y - y0;
      final o = j * width + i;
      for (var c = 0; c < 3; c++) {
        final top = px(x0, y0, c) * (1 - fx) + px(x0 + 1, y0, c) * fx;
        final bot = px(x0, y0 + 1, c) * (1 - fx) + px(x0 + 1, y0 + 1, c) * fx;
        final v = (top * (1 - fy) + bot * fy) / 255;
        // channel order BGR: r -> plane 2, g -> 1, b -> 0
        t[(2 - c) * plane + o] = (v - 0.5) / 0.5;
      }
    }
  }
  return RecInput(t, width);
}

/// Greedy CTC: best class per step, drop blanks (0) and repeats. [chars]
/// is the model's dictionary; index i+1 is chars[i], the last index a space.
({String text, double score}) ctcDecode(List<num> out, int steps, int classes, List<String> chars) {
  final sb = StringBuffer();
  var sum = 0.0, n = 0, prev = -1;
  for (var t = 0; t < steps; t++) {
    var best = 0;
    var bestP = out[t * classes].toDouble();
    for (var c = 1; c < classes; c++) {
      final p = out[t * classes + c].toDouble();
      if (p > bestP) {
        bestP = p;
        best = c;
      }
    }
    if (best != 0 && best != prev) {
      sb.write(best - 1 < chars.length ? chars[best - 1] : ' ');
      sum += bestP;
      n++;
    }
    prev = best;
  }
  return (text: sb.toString(), score: n == 0 ? 0.0 : sum / n);
}

/// The receipt's lines share one angle; long lines at another angle (more
/// than 15 degrees off the median) belong to another paper in the photo.
/// Short boxes have no reliable angle and are kept.
List<TextBox> sameAngleAsReceipt(List<TextBox> boxes) {
  double angle(TextBox b) => math.atan2(b.uy, b.ux);
  final long = boxes.where((b) => b.hu >= 1.5 * b.hv).toList();
  if (long.length < 3) return boxes;
  final angles = long.map(angle).toList()..sort();
  final median = angles[angles.length ~/ 2];
  const max = 15 * math.pi / 180;
  return boxes.where((b) => b.hu < 1.5 * b.hv || (angle(b) - median).abs() <= max).toList();
}
