/// A frame capture an older build wrote, opened by this one.
///
///     dart test test/formats/frame_capture_fixture_test.dart
///
/// Version 1 is the shape before the format envelope
/// (`"format": "flutter3d.frameCapture"`); version 2 is the envelope.
library;

import 'dart:io';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';

String _fixture(int version) =>
    File('test/fixtures/v$version/frame.capture.json').readAsStringSync();

void main() {
  test('every version of the capture reads', () {
    for (var version = 1; version <= FrameCapture.fileVersion; version++) {
      final capture = FrameCapture.parse(_fixture(version));
      expect(capture.width, 4, reason: 'v$version');
      expect(capture.passes.single.images.single.resource, 'color');
    }
  });

  test('the texture format is read by its word, not the Dart name', () {
    expect(
      FrameCapture.parse(_fixture(2)).passes.single.images.single.format,
      TextureFormat.r16g16b16a16Float,
    );
  });

  test('a key this build does not read is written back', () {
    final capture = FrameCapture.parse(_fixture(2));
    expect(capture.unknown, contains('comment'));
    final written = capture.toJson();
    expect(written['format'], FrameCapture.fileFormat);
    expect(written['comment'], capture.unknown['comment']);
  });

  test('a newer capture is refused with the reason', () {
    // Mutation: answer null, as the reader did before 1.0, and this fails.
    expect(
      () => FrameCapture.fromJson(<String, Object?>{
        'format': FrameCapture.fileFormat,
        'version': FrameCapture.fileVersion + 1,
        'width': 1,
        'height': 1,
      }),
      throwsA(
        isA<FrameCaptureFormatException>().having(
          (FrameCaptureFormatException e) => e.message,
          'message',
          contains('newer'),
        ),
      ),
    );
  });
}
