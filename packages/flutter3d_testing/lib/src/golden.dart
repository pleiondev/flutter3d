import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';

import 'render_frame.dart';

/// Fails unless [frame] matches the image at [path], within [tolerance].
///
/// [frame] is what [renderFrame] returns, pixels and size together. [tolerance]
/// is the share of pixels allowed to differ at all, as a percentage.
///
/// **Writes the reference and passes when there is none.** A first run records
/// what the game draws today rather than failing for want of a file nobody could
/// have written by hand. It says so on the console, because a recorded golden
/// nobody looked at is a test that will pass forever whatever it draws — the
/// image is meant to be opened and the commit is meant to say it was.
///
/// **Zero tolerance by default, and that is on purpose.** The frame comes from a
/// software rasteriser: the same scene drawn twice is the same bytes twice,
/// because nothing here depends on a driver, a clock or a thread. A test that
/// allows a few pixels of drift is a test that stops watching the drift, and
/// when it is not needed it should not be there. Raise it only when something is
/// measured to move — an animation sampled on a real clock, a scene with a
/// deliberate random in it — and say in the call why.
Future<void> expectMatchesGolden(
  RenderedFrame frame,
  String path, {
  double tolerance = 0.0,
  String? reason,
}) async {
  final file = File(path);
  if (!file.existsSync()) {
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(
        encodePng(frame.pixels, frame.width, frame.height));
    // Deliberately not a failure. A first run has nothing to compare against,
    // and refusing to record would mean every new test starts red for a reason
    // that is not about the code.
    printOnFailure('recorded a new golden at $path — open it before committing');
    // ignore: avoid_print
    print('flutter3d_testing: recorded a new golden at $path');
    return;
  }

  final expected = await _readPng(file);
  expect(
    frame.pixels.length,
    expected.length,
    reason: 'the frame and $path are different sizes — the golden was recorded '
        'at another resolution, so re-record it rather than reading anything '
        'into the pixels',
  );

  final difference = compareFrames(frame.pixels, expected);
  expect(
    difference.percent,
    lessThanOrEqualTo(tolerance),
    reason: <String>[
      '$path: $difference',
      ?reason,
      'If this change is meant, delete the file and run again to re-record it.',
    ].join('\n'),
  );
}

/// The reference image as RGBA bytes.
Future<Uint8List> _readPng(File file) async {
  final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
  final image = (await codec.getNextFrame()).image;
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) {
    throw StateError('${file.path} could not be read as RGBA');
  }
  return data.buffer.asUint8List();
}
