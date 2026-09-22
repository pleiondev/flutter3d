/// `gfx-36n`: the controller that pulls `renderScale` on its own.
///
///     flutter test test/adaptive_scale_test.dart
///
/// **Driven by a synthetic series of frame times, not by frames.** What is
/// under test is a policy — when to move and when to hold — and feeding it
/// real frames would make the test a measurement of this machine. Every
/// number below is a decision the controller makes, held exactly.
///
/// The three that matter are the three that are bugs if they are wrong: the
/// band between the thresholds, the window, and the hold before going back
/// up. Each has a test that fails if the guard is removed.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter_test/flutter_test.dart';

/// Feeds [count] frames of [micros] and answers the scale afterwards.
double _after(AdaptiveScale controller, int micros, int count) {
  var scale = controller.scale;
  for (var i = 0; i < count; i++) {
    scale = controller.recordFrame(micros);
  }
  return scale;
}

void main() {
  const target = 16667;

  AdaptiveScale controllerWith({
    bool enabled = true,
    int window = 30,
    int holdWindows = 6,
    double step = 0.1,
    double minimum = 0.5,
  }) => AdaptiveScale(
    AdaptiveScaleSettings(
      enabled: enabled,
      window: window,
      holdWindows: holdWindows,
      step: step,
      minimum: minimum,
    ),
  );

  test('off, it reports full and decides nothing', () {
    // An application that has not asked for its resolution to move should not
    // find it moving, and should not find a window kept for it either.
    expect(const AdaptiveScaleSettings().enabled, isFalse);
    final controller = controllerWith(enabled: false);
    expect(_after(controller, target * 10, 100), 1.0);
  });

  test('a sustained slow period steps down within one window', () {
    final controller = controllerWith();
    // Twenty-nine frames decide nothing: a window is the unit, and one slow
    // frame is a garbage collection rather than a scene.
    expect(_after(controller, (target * 1.2).round(), 29), 1.0);
    expect(_after(controller, (target * 1.2).round(), 1), closeTo(0.9, 1e-9));
  });

  test('it never steps below the floor, however slow the frames', () {
    final controller = controllerWith(minimum: 0.5);
    expect(_after(controller, target * 20, 30 * 20), 0.5);
  });

  test('going back up waits for several clean windows', () {
    final controller = controllerWith();
    _after(controller, (target * 1.2).round(), 30);
    expect(controller.scale, closeTo(0.9, 1e-9));

    // Five clean windows are not enough; the sixth is.
    expect(
      _after(controller, (target * 0.5).round(), 30 * 5),
      closeTo(0.9, 1e-9),
      reason:
          'up is the direction that can only be wrong, so it is the one '
          'that waits',
    );
    expect(_after(controller, (target * 0.5).round(), 30), closeTo(1.0, 1e-9));
  });

  test('a frame between the thresholds moves nothing, and is not clean', () {
    // **The band, which is the whole of why this is not one threshold.** With
    // a single point, a frame landing a hair over it shrinks, which makes it
    // land a hair under, which grows it back — a picture that pulses at
    // whatever rate the scene happens to sit at.
    final controller = controllerWith();
    _after(controller, (target * 1.2).round(), 30);
    expect(controller.scale, closeTo(0.9, 1e-9));

    // Comfortably inside the band: not slow, not fast.
    expect(
      _after(controller, (target * 0.9).round(), 30 * 20),
      closeTo(0.9, 1e-9),
    );
    expect(
      controller.cleanWindows,
      0,
      reason:
          'a window in the band is not evidence to grow; counting it as '
          'clean would walk the resolution back up into the slow threshold '
          'one step at a time',
    );
  });

  test('a single slow frame in a fast window does not step down', () {
    // The hitch case: a window is averaged, so one frame that took ten times
    // as long is absorbed rather than obeyed.
    final controller = controllerWith();
    for (var i = 0; i < 29; i++) {
      controller.recordFrame((target * 0.5).round());
    }
    final scale = controller.recordFrame(target * 5);
    expect(
      scale,
      1.0,
      reason:
          'the mean of that window is still under the slow threshold, and '
          'the mean is what the controller is for',
    );
  });

  test('switching it off forgets what it had gathered', () {
    // Half a window from before should not decide the first window after.
    final settings = AdaptiveScaleSettings(enabled: false);
    final controller = AdaptiveScale(settings);
    expect(_after(controller, target * 10, 15), 1.0);
    expect(controller.cleanWindows, 0);
  });
}
