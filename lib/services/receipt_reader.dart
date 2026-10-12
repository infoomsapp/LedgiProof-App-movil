import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'ocr_pipeline.dart';

/// One line of text found on the receipt, with its box in the photo.
class ReadLine {
  ReadLine(this.text, this.score, this.box);
  final String text;
  final double score;
  final List<List<int>> box;

  Map<String, dynamic> toJson() => {'text': text, 'score': score, 'box': box};
}

/// LedgiProof reads receipt photos on the phone (OCR plan N1): PaddleOCR
/// PP-OCRv5 mobile -- the same models the web reads with -- run by ONNX
/// Runtime inside the app. No external engine; the photo's text lines (not
/// the photo) go to the ocr-receipt function, where LedgiProof's parser
/// turns them into fields. Models ship in assets/ocr/ (~21 MB) and load on
/// the first receipt.
class ReceiptReader {
  ReceiptReader._();
  static final ReceiptReader instance = ReceiptReader._();

  /// Recorded with every reading, so the benchmark can compare readers.
  static const readerId = 'paddleocr-onnx-dart/PP-OCRv5_mobile';

  final _ort = OnnxRuntime();
  Future<({OrtSession det, OrtSession rec, List<String> chars})>? _loaded;

  Future<({OrtSession det, OrtSession rec, List<String> chars})> _load() =>
      _loaded ??= () async {
        final det = await _ort.createSessionFromAsset('assets/ocr/det.onnx');
        final rec = await _ort.createSessionFromAsset('assets/ocr/rec.onnx');
        final dict = await rootBundle.loadString('assets/ocr/rec_dict.txt');
        final chars = dict.replaceAll('\r\n', '\n').split('\n');
        if (chars.isNotEmpty && chars.last.isEmpty) chars.removeLast();
        return (det: det, rec: rec, chars: chars);
      }()
          .catchError((Object e) {
        _loaded = null;
        throw e;
      });

  /// The text lines on a receipt photo, top to bottom.
  Future<List<ReadLine>> read(Uint8List photo) async {
    final m = await _load();

    // 1. Upright photo + detector input (pixel work off the UI thread).
    final input = await Isolate.run(() => prepareDet(photo));

    // 2. Where the text is.
    final detIn = await OrtValue.fromList(input.tensor, [1, 3, input.dh, input.dw]);
    final detOut = await m.det.run({m.det.inputNames.first: detIn});
    final probValue = detOut[m.det.outputNames.first]!;
    final prob = (await probValue.asFlattenedList()).map((e) => (e as num).toDouble()).toList();
    await detIn.dispose();
    await probValue.dispose();
    final found = await Isolate.run(() => dbBoxes(prob, input.dw, input.dh, input.w, input.h));
    // Other papers in the photo are at another angle: skip reading them
    // (the parser would drop them anyway) -- it saves seconds per receipt.
    final boxes = sameAngleAsReceipt(found);

    // 3. What each box says.
    final lines = <ReadLine>[];
    for (final b in boxes) {
      final rgb = input.rgb, w = input.w, h = input.h;
      final rec = await Isolate.run(() => prepareRec(rgb, w, h, b));
      final recIn = await OrtValue.fromList(rec.tensor, [1, 3, 48, rec.width]);
      final recOut = await m.rec.run({m.rec.inputNames.first: recIn});
      final v = recOut[m.rec.outputNames.first]!;
      final shape = v.shape; // [1, steps, classes]
      final out = (await v.asFlattenedList()).cast<num>();
      await recIn.dispose();
      await v.dispose();
      final chars = m.chars;
      final decoded = await Isolate.run(() => ctcDecode(out, shape[1], shape[2], chars));
      if (decoded.text.trim().isNotEmpty) {
        lines.add(ReadLine(decoded.text, (decoded.score * 1000).round() / 1000, b.corners));
      }
    }
    return lines;
  }
}
