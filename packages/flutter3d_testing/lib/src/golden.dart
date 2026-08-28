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
  bool? recordMissing,
}) async {
  // **Recording is for a person authoring a test, not for a machine running
  // one.** A missing file used to be recorded and *passed*, which is right
  // locally and wrong in CI: a mistyped path, a gitignored directory or a
  // fresh worktree then turns every golden into a test that writes its own
  // answer and agrees with it. `CI` is what every runner sets, and a caller
  // that knows better can say so.
  final record =
      recordMissing ?? !const bool.fromEnvironment('CI', defaultValue: false);
  final file = File(path);
  if (!file.existsSync()) {
    if (!record) {
      fail(
        'no golden at $path, and this is a CI run — recording one here would '
        'be the test writing its own answer. Record it locally and commit it.',
      );
    }
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(encodePng(frame.pixels, frame.width, frame.height));
    // Deliberately not a failure. A first run has nothing to compare against,
    // and refusing to record would mean every new test starts red for a reason
    // that is not about the code.
    printOnFailure(
      'recorded a new golden at $path — open it before committing',
    );
    // ignore: avoid_print
    print('flutter3d_testing: recorded a new golden at $path');
    return;
  }

  final expected = await _readPng(file);
  expect(
    <int>[frame.width, frame.height],
    <int>[expected.width, expected.height],
    reason:
        'the frame and $path are different sizes — the golden was recorded '
        'at another resolution, so re-record it rather than reading anything '
        'into the pixels. Compared as width and height rather than as a byte '
        'count, which a transposed frame passes.',
  );

  final difference = compareFrames(frame.pixels, expected.pixels);
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

/// The reference image as RGBA bytes, with the size it was recorded at.
///
/// The size comes back because comparing byte counts is not comparing sizes: a
/// 480 × 360 golden and a 360 × 480 frame hold the same number of bytes, pass
/// that check, and then diff as though every row were shifted.
Future<({Uint8List pixels, int width, int height})> _readPng(File file) async {
  final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
  final image = (await codec.getNextFrame()).image;
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) {
      throw StateError('${file.path} could not be read as RGBA');
    }
    return (
      pixels: data.buffer.asUint8List(),
      width: image.width,
      height: image.height,
    );
  } finally {
    // A `ui.Image` holds bytes outside the Dart heap, and a suite comparing
    // thirty goldens leaked thirty of them. `texture_upload.dart` is careful
    // about exactly this one call.
    image.dispose();
  }
}
