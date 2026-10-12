// Cross-check of lib/services/ocr_pipeline.dart against the real models,
// run by hand from the desktop (the models run in Python between steps):
//   OCR_XCHECK_DIR=<dir> OCR_XCHECK_STEP=1 flutter test test/ocr_pipeline_crosscheck_test.dart
// Skipped in normal runs.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledgiproof/services/ocr_pipeline.dart';

void main() {
  final dir = Platform.environment['OCR_XCHECK_DIR'];
  final step = Platform.environment['OCR_XCHECK_STEP'];
  test('ocr pipeline cross-check step $step', () {
    final d = Directory(dir!);
    Float32List readF(String n) => File('${d.path}/$n').readAsBytesSync().buffer.asFloat32List();
    void writeF(String n, Float32List t) => File('${d.path}/$n').writeAsBytesSync(t.buffer.asUint8List());

    if (step == '1') {
      final input = prepareDet(File('${d.path}/photo.png').readAsBytesSync());
      writeF('det_in.f32', input.tensor);
      File('${d.path}/rgb.u8').writeAsBytesSync(input.rgb);
      File('${d.path}/dims.txt').writeAsStringSync('${input.dw} ${input.dh} ${input.w} ${input.h}');
    } else if (step == '2') {
      final dims = File('${d.path}/dims.txt').readAsStringSync().split(' ').map(int.parse).toList();
      final prob = readF('det_out.f32').map((e) => e.toDouble()).toList();
      final boxes = dbBoxes(prob, dims[0], dims[1], dims[2], dims[3]);
      final rgb = File('${d.path}/rgb.u8').readAsBytesSync();
      final widths = <int>[];
      for (var i = 0; i < boxes.length; i++) {
        final r = prepareRec(rgb, dims[2], dims[3], boxes[i]);
        writeF('rec_in_$i.f32', r.tensor);
        widths.add(r.width);
      }
      File('${d.path}/boxes.txt').writeAsStringSync(
          [for (var i = 0; i < boxes.length; i++) '${widths[i]} ${boxes[i].corners}'].join('\n'));
    } else if (step == '3') {
      final chars = File('${d.path}/rec_dict.txt').readAsStringSync().split('\n')..removeLast();
      final meta = File('${d.path}/boxes.txt').readAsStringSync().split('\n');
      final out = StringBuffer();
      for (var i = 0; i < meta.length; i++) {
        final shape = File('${d.path}/rec_out_$i.shape').readAsStringSync().split(' ').map(int.parse).toList();
        final r = ctcDecode(readF('rec_out_$i.f32'), shape[1], shape[2], chars);
        out.writeln('${r.text}\t${r.score.toStringAsFixed(3)}\t${meta[i]}');
      }
      File('${d.path}/result.txt').writeAsStringSync(out.toString());
    }
  }, skip: dir == null ? 'manual cross-check (OCR_XCHECK_DIR not set)' : false);
}
