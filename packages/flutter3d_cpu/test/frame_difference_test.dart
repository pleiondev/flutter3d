/// What two frames disagree about.
///
///     flutter test test/frame_difference_test.dart
///
/// Four places had counted this by hand, with three different thresholds. The
/// thresholds were all defensible; having three of them and no written
/// question was not.
library;

import 'dart:typed_data';

import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';

/// One pixel, repeated.
Uint8List _frame(int r, int g, int b, {int pixels = 4, int alpha = 255}) =>
    Uint8List.fromList(<int>[
      for (var i = 0; i < pixels; i++) ...<int>[r, g, b, alpha],
    ]);

void main() {
  test('two identical frames differ nowhere', () {
    final it = compareFrames(_frame(10, 20, 30), _frame(10, 20, 30));

    expect(it.differing, 0);
    expect(it.worstChannel, 0);
    expect(it.percent, 0.0);
    expect(it.pixels, 4);
  });

  test('and the threshold is exclusive, at the default the goldens use', () {
    // Eight, because `tool/golden.sh` says eight: a comparison that names no
    // threshold has to mean what the recorded pictures mean.
    expect(differingPixels(_frame(0, 0, 0), _frame(8, 0, 0)), 0,
        reason: 'exactly the threshold counted as a difference');
    expect(differingPixels(_frame(0, 0, 0), _frame(9, 0, 0)), 4);
  });

  test('and a caller can ask a different question', () {
    // The editor asks two, because nothing in its scene is animated; the games
    // ask twelve, because this backend's dithering moves a channel by a few
    // steps between frames that are meant to be identical.
    final a = _frame(100, 100, 100);
    final b = _frame(104, 100, 100);

    expect(differingPixels(a, b, channel: 2), 4);
    expect(differingPixels(a, b, channel: 12), 0);
  });

  test('alpha is not a picture', () {
    // A backend that writes a different alpha into an opaque frame has not
    // drawn anything a person would see.
    expect(
      differingPixels(_frame(10, 10, 10), _frame(10, 10, 10, alpha: 0)),
      0,
    );
  });

  test('the worst channel is the largest single step anywhere', () {
    // The number that says whether a comparison passed comfortably or only
    // just: a per cent of pixels one step apart and a per cent two hundred
    // apart are not the same picture, and the share alone cannot tell them
    // apart.
    final a = Uint8List.fromList(<int>[0, 0, 0, 255, 0, 0, 0, 255]);
    final b = Uint8List.fromList(<int>[9, 0, 0, 255, 0, 200, 0, 255]);

    final it = compareFrames(a, b);

    expect(it.differing, 2);
    expect(it.worstChannel, 200);
    expect(it.percent, 100.0);
  });

  test('and two frames of different sizes is a broken test, not a failing one',
      () {
    expect(
      () => compareFrames(_frame(0, 0, 0, pixels: 2), _frame(0, 0, 0)),
      throwsArgumentError,
    );
  });
}
