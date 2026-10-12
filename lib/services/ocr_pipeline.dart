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
///   dbBoxes      detector probability map -> text boxes (DB post-process:
///                threshold 0.3, box score 0.6, unclip 1.5)
///   prepareRec   one box -> recognizer input (height 48, BGR, (x/255-.5)/.5)
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

class TextBox {
  const TextBox(this.x1, this.y1, this.x2, this.y2);
  final double x1, y1, x2, y2;
  List<List<int>> get corners => [
        [x1.round(), y1.round()],
        [x2.round(), y1.round()],
        [x2.round(), y2.round()],
        [x1.round(), y2.round()],
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

/// DB post-process: connected regions above 0.3, kept when their mean
/// probability is at least 0.6, grown by the unclip ratio, mapped back to
/// the photo. Top to bottom, then left to right.
List<TextBox> dbBoxes(List<double> prob, int dw, int dh, int w, int h,
    {double thresh = 0.3, double boxThresh = 0.6, double unclip = 1.5}) {
  final seen = Uint8List(dw * dh);
  final boxes = <TextBox>[];
  final stack = <int>[];
  for (var start = 0; start < dw * dh; start++) {
    if (seen[start] == 1 || prob[start] <= thresh) continue;
    var x1 = dw, y1 = dh, x2 = 0, y2 = 0;
    seen[start] = 1;
    stack.add(start);
    while (stack.isNotEmpty) {
      final k = stack.removeLast();
      final x = k % dw, y = k ~/ dw;
      if (x < x1) x1 = x;
      if (x > x2) x2 = x;
      if (y < y1) y1 = y;
      if (y > y2) y2 = y;
      for (final n in [if (x + 1 < dw) k + 1, if (x > 0) k - 1, if (y + 1 < dh) k + dw, if (y > 0) k - dw]) {
        if (seen[n] == 0 && prob[n] > thresh) {
          seen[n] = 1;
          stack.add(n);
        }
      }
    }
    x2 += 1;
    y2 += 1;
    if (math.min(x2 - x1, y2 - y1) < 3) continue;
    var sum = 0.0;
    for (var y = y1; y < y2; y++) {
      for (var x = x1; x < x2; x++) {
        sum += prob[y * dw + x];
      }
    }
    if (sum / ((x2 - x1) * (y2 - y1)) < boxThresh) continue;
    final bw = (x2 - x1).toDouble(), bh = (y2 - y1).toDouble();
    final d = bw * bh * unclip / (2 * (bw + bh));
    final sx = w / dw, sy = h / dh;
    boxes.add(TextBox(
      math.max(0, (x1 - d) * sx),
      math.max(0, (y1 - d) * sy),
      math.min(w.toDouble(), (x2 + d) * sx),
      math.min(h.toDouble(), (y2 + d) * sy),
    ));
  }
  boxes.sort((a, b) => a.y1 != b.y1 ? a.y1.compareTo(b.y1) : a.x1.compareTo(b.x1));
  return boxes;
}

/// One text box -> recognizer input: 48 px high, at least 320 wide (zero
/// padded on the right), BGR, (x/255 - 0.5) / 0.5.
RecInput prepareRec(Uint8List rgb, int w, int h, TextBox b) {
  final x1 = b.x1.round().clamp(0, w - 1), y1 = b.y1.round().clamp(0, h - 1);
  final x2 = b.x2.round().clamp(x1 + 1, w), y2 = b.y2.round().clamp(y1 + 1, h);
  final cw = x2 - x1, ch = y2 - y1;
  final crop = img.Image(width: cw, height: ch, numChannels: 3);
  for (var y = 0; y < ch; y++) {
    for (var x = 0; x < cw; x++) {
      final o = ((y1 + y) * w + (x1 + x)) * 3;
      crop.setPixelRgb(x, y, rgb[o], rgb[o + 1], rgb[o + 2]);
    }
  }
  final ratio = cw / math.max(ch, 1);
  final rw = (48 * ratio).ceil();
  final width = math.max(320, rw);
  final line = img.copyResize(crop, width: rw, height: 48, interpolation: img.Interpolation.linear);
  final plane = 48 * width;
  final t = Float32List(3 * plane); // padding stays 0
  for (var y = 0; y < 48; y++) {
    for (var x = 0; x < rw; x++) {
      final p = line.getPixel(x, y);
      final o = y * width + x;
      t[o] = (p.b / 255 - 0.5) / 0.5;
      t[plane + o] = (p.g / 255 - 0.5) / 0.5;
      t[2 * plane + o] = (p.r / 255 - 0.5) / 0.5;
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
