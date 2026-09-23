/// Trading resolution for frame rate, on its own — `gfx-36n`.
///
/// **A hundred lines of policy, kept out of the renderer.** What
/// `RenderSettings.renderScale` gives an application is a lever; what nobody
/// wants to write twice is the judgement about when to pull it. The
/// non-obvious half is not "go smaller when slow": it is everything that
/// stops the frame rate and the resolution chasing each other.
///
/// Three decisions, and each one is a bug somebody has already shipped:
///
/// **Asymmetric thresholds.** Stepping down above 1.1x the target period and
/// back up only below 0.7x. With one threshold, a frame that lands a hair
/// over it shrinks, which makes it land a hair under, which grows it back —
/// a picture that pulses at whatever rate the scene happens to sit at.
///
/// **A window, not a frame.** One slow frame is a garbage collection, a
/// texture upload, a window being dragged. Deciding on a single sample means
/// the resolution moves for reasons that have nothing to do with the scene.
///
/// **A hold after stepping down, longer before stepping up.** The frame after
/// a change is not evidence about the change: it carries whatever the change
/// itself cost. And going back up is the risky direction — it can only be
/// wrong — so it waits for several clean windows where going down waits for
/// one.
///
/// Driven by `FrameResult.cpuMicros` rather than by a GPU timestamp, which
/// this engine cannot ask any backend for. What that measures is the time the
/// UI thread spent, which is the number a person feels.
library;

import 'dart:math' as math;

/// How far the resolution may be pulled, and how fast.
final class AdaptiveScaleSettings {
  const AdaptiveScaleSettings({
    this.enabled = false,
    this.targetMicros = 16667,
    this.minimum = 0.5,
    this.maximum = 1.0,
    this.step = 0.1,
    this.window = 30,
    this.holdWindows = 6,
    this.slowRatio = 1.1,
    this.fastRatio = 0.7,
  }) : assert(minimum > 0.0 && minimum <= maximum),
       assert(maximum <= 1.0, 'above one is a supersample, not a scale'),
       assert(window >= 1),
       assert(
         fastRatio < slowRatio,
         'the two thresholds have to leave a band between them, or the '
         'resolution oscillates across the single point where they meet',
       );

  /// Off by default: an application that has not asked for its resolution to
  /// move should not find it moving.
  final bool enabled;

  /// The frame period being aimed at, in microseconds. 16667 is sixty a
  /// second.
  final int targetMicros;

  /// The smallest and largest scale this will choose. The maximum is what an
  /// application considers "full", which need not be 1 on a display whose
  /// pixel ratio already costs it.
  final double minimum;
  final double maximum;

  /// How much the scale moves in one step. Whole steps rather than a
  /// continuous solve: a resolution that changes by a per cent every window
  /// is a resolution that is always changing, and the resampling is more
  /// visible than the step.
  final double step;

  /// How many frames are averaged before anything is decided.
  final int window;

  /// How many clean windows in a row before the scale goes back up.
  final int holdWindows;

  /// Above this multiple of [targetMicros], the frame is too slow.
  final double slowRatio;

  /// Below this multiple, there is room to give resolution back.
  final double fastRatio;
}

/// The scale to draw the next frame at, decided from the ones before it.
///
/// Holds its own state, so an application feeds it every frame and reads
/// [scale] — there is nothing to arrange and nothing to reset between scenes.
final class AdaptiveScale {
  AdaptiveScale(this.settings);

  final AdaptiveScaleSettings settings;

  /// How many steps below [AdaptiveScaleSettings.maximum] the scale sits.
  ///
  /// **A count rather than a running sum.** Adding and subtracting 0.1 walks
  /// off the grid in the last bits — five steps down from 1.0 land on
  /// 0.5000000000000001 rather than the floor, and five back up on
  /// 0.9999999999999999 rather than full — so each end cost one extra step,
  /// and one extra hold, before the scale was where it said it was.
  int _stepsDown = 0;
  final List<int> _window = <int>[];
  int _cleanWindows = 0;

  /// What the next frame should be drawn at.
  double get scale =>
      math.max(settings.minimum, settings.maximum - _stepsDown * settings.step);

  /// How many clean windows in a row have passed since the scale last moved
  /// or a window landed in the band between the thresholds — what
  /// [AdaptiveScaleSettings.holdWindows] is counted against.
  int get cleanWindows => _cleanWindows;

  /// Feeds one frame's own cost in, and returns the scale for the next.
  ///
  /// Disabled, this reports [AdaptiveScaleSettings.maximum] and forgets
  /// whatever it had gathered: an application that switches the controller
  /// off and on again should not find a window from before still deciding.
  double recordFrame(int cpuMicros) {
    if (!settings.enabled) {
      _window.clear();
      _cleanWindows = 0;
      _stepsDown = 0;
      return scale;
    }

    _window.add(cpuMicros);
    if (_window.length < settings.window) return scale;

    final mean = _window.reduce((int a, int b) => a + b) / _window.length;
    _window.clear();

    final slow = settings.targetMicros * settings.slowRatio;
    final fast = settings.targetMicros * settings.fastRatio;

    if (mean > slow) {
      // Down on the first bad window: a frame that is already late is
      // costing somebody something now, and the risk of shrinking once too
      // often is a picture slightly softer than it had to be.
      _cleanWindows = 0;
      if (scale > settings.minimum) _stepsDown++;
      return scale;
    }

    if (mean < fast) {
      _cleanWindows++;
      if (_cleanWindows >= settings.holdWindows) {
        _cleanWindows = 0;
        if (_stepsDown > 0) _stepsDown--;
      }
      return scale;
    }

    // Between the two: the band that exists so nothing moves. A window in
    // here is neither evidence to shrink nor evidence to grow, and counting
    // it as clean would walk the resolution up into the slow threshold one
    // step at a time.
    _cleanWindows = 0;
    return scale;
  }
}
