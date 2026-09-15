/// `mat-09n`'s own acceptance line: `decodePng`/`decodeJpeg`
/// (`flutter3d_model_core`, no `dart:ui`) against `dart:ui`'s own decode,
/// on real files — the cross-check `png_decoder_test.dart`'s own doc
/// comment says belongs here rather than in that plain-Dart package, since
/// only an app has `dart:ui` to compare against at all.
///
///     flutter test test/image_decoder_parity_test.dart
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter3d_core/formats.dart';
import 'package:flutter_test/flutter_test.dart';

/// [path] decoded through `dart:ui`, straight (non-premultiplied) RGBA —
/// the same convention `texture_upload.dart`'s own engine-side decode
/// already uses, and the one this package's own decoders produce.
Future<({int width, int height, Uint8List rgba})> _decodeWithDartUi(
  String path,
) async {
  final bytes = File(path).readAsBytesSync();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final data = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  return (
    width: image.width,
    height: image.height,
    rgba: data!.buffer.asUint8List(),
  );
}

/// The largest single-channel difference between [a] and [b], which must be
/// the same length — the whole point of comparing this way rather than with
/// a blanket `expect(a, b)` is a clear number in a failure message instead
/// of "these two 150 000-byte lists differ somewhere".
int _maxDelta(Uint8List a, Uint8List b) {
  var max = 0;
  for (var i = 0; i < a.length; i++) {
    final delta = (a[i] - b[i]).abs();
    if (delta > max) max = delta;
  }
  return max;
}

void main() {
  group('PNG — decodePng against dart:ui, byte for byte', () {
    // Reuses this app's own golden PNGs (RGBA8, real content already
    // checked into the repo for the rendering tests) rather than building
    // synthetic fixtures — the acceptance asks for real files, and these
    // already are some.
    for (final name in <String>['mesh-extrude.png', 'lod-uv.png']) {
      test(name, () async {
        final path = 'test/goldens/$name';
        final fromDartUi = await _decodeWithDartUi(path);
        final ours = decodePng(File(path).readAsBytesSync());
        expect(ours, isNotNull);
        expect(ours!.width, fromDartUi.width);
        expect(ours.height, fromDartUi.height);
        expect(ours.rgba, orderedEquals(fromDartUi.rgba));
      });
    }
  });

  group('JPEG — decodeJpeg against dart:ui, within a documented tolerance', () {
    // 4:4:4 (no chroma subsampling) — the only source of difference left
    // between two independent baseline decoders is IDCT rounding. Measured
    // on this fixture: a max single-channel delta of 2; the bound below
    // gives it room without hiding a real regression.
    test('gradient_444.jpg', () async {
      final path =
          '../../packages/flutter3d_core/test/formats/fixtures/gradient_444.jpg';
      final fromDartUi = await _decodeWithDartUi(path);
      final ours = decodeJpeg(File(path).readAsBytesSync());
      expect(ours, isNotNull);
      expect(ours!.width, fromDartUi.width);
      expect(ours.height, fromDartUi.height);
      expect(_maxDelta(ours.rgba, fromDartUi.rgba), lessThanOrEqualTo(4));
    });

    test('solid_8x8.jpg — one exact MCU, no rounding to hide behind', () async {
      final path =
          '../../packages/flutter3d_core/test/formats/fixtures/solid_8x8.jpg';
      final fromDartUi = await _decodeWithDartUi(path);
      final ours = decodeJpeg(File(path).readAsBytesSync());
      expect(ours, isNotNull);
      expect(_maxDelta(ours!.rgba, fromDartUi.rgba), lessThanOrEqualTo(4));
    });

    test('gray_16x16.jpg — single component, no chroma at all', () async {
      final path =
          '../../packages/flutter3d_core/test/formats/fixtures/gray_16x16.jpg';
      final fromDartUi = await _decodeWithDartUi(path);
      final ours = decodeJpeg(File(path).readAsBytesSync());
      expect(ours, isNotNull);
      expect(_maxDelta(ours!.rgba, fromDartUi.rgba), lessThanOrEqualTo(4));
    });

    // 4:2:0 — chroma is subsampled, so this decoder's own nearest-neighbour
    // upsampling and dart:ui's own (libjpeg-turbo's default "fancy"
    // triangle-filter) upsampling disagree at every subsampled edge, on top
    // of the same IDCT rounding the 4:4:4 case already has. Measured on
    // this fixture: a max single-channel delta of 13 — the documented,
    // expected difference the library comment above explains, not slack
    // added after the fact to make a failing test pass.
    test(
      'gradient_420.jpg — subsampled chroma, wider documented tolerance',
      () async {
        final path =
            '../../packages/flutter3d_core/test/formats/fixtures/gradient_420.jpg';
        final fromDartUi = await _decodeWithDartUi(path);
        final ours = decodeJpeg(File(path).readAsBytesSync());
        expect(ours, isNotNull);
        expect(ours!.width, fromDartUi.width);
        expect(ours.height, fromDartUi.height);
        expect(_maxDelta(ours.rgba, fromDartUi.rgba), lessThanOrEqualTo(20));
      },
    );
  });

  group('truncated files refuse by value, not by throwing', () {
    test('a JPEG cut off mid-scan', () {
      final path =
          '../../packages/flutter3d_core/test/formats/fixtures/gradient_444.jpg';
      final bytes = File(path).readAsBytesSync();
      final truncated = Uint8List.sublistView(bytes, 0, bytes.length ~/ 2);
      expect(decodeJpeg(truncated), isNull);
    });

    test('a JPEG cut off before any scan at all', () {
      final path =
          '../../packages/flutter3d_core/test/formats/fixtures/gradient_444.jpg';
      final bytes = File(path).readAsBytesSync();
      final truncated = Uint8List.sublistView(bytes, 0, 4);
      expect(decodeJpeg(truncated), isNull);
    });
  });
}
