/// The best picture that fits the frame budget, chosen every frame from a
/// measured table — `N2`.
///
/// **What `AdaptiveScale` could not do.** That controller had one lever and a
/// timer: slow, go smaller; fast for a while, go bigger. It could not know
/// that on this device the fog's steps cost more than a tenth of the
/// resolution and take less out of the picture, because nothing told it what
/// anything costs or what it looks like. A [QualityTable] does: per row, a
/// cost relative to full quality and a perceptual difference against it. The
/// controller's whole job is then to keep an estimate of what each row costs
/// *here, now*, and take the best-looking row whose estimate fits.
///
/// **The estimate is the table scaled by what was measured.** A row's time is
/// `load × cost × correction`:
///
///   * `load` is microseconds per unit of the table's cost — this scene, on
///     this device, at this temperature. It rises to a slow frame at once,
///     because a frame that is late is costing somebody now, and falls back
///     by an exponential average, because coming back up can only be wrong.
///     Heat and background load are seen here, for every row at once.
///   * `correction` is per row, an exponential average of how far the rows
///     actually visited missed their prediction: the table was measured on
///     one device of the class and this is another.
///
/// **Two margins, and a hold before climbing**, for the reason
/// `AdaptiveScale` has asymmetric thresholds: a row is kept while its
/// estimate is under [AdaptiveQualitySettings.headroom] of the budget and
/// only climbed to when it is under [AdaptiveQualitySettings.climbHeadroom]
/// for [AdaptiveQualitySettings.climbFrames] frames in a row. With one
/// margin the quality would flip between two rows at the rate the scene sits
/// between them.
///
/// **In motion the input resolution drops** (R1's camera velocity, passed as
/// [AdaptiveQuality.recordFrame]'s `motion`): a picture moving faster than
/// the eye can follow does not show the resolution it is drawn at, and with
/// the temporal resolve on the output stays full size. Above
/// [AdaptiveQualitySettings.motionThreshold] only rows at or below
/// [AdaptiveQualitySettings.motionScale] are candidates.
///
/// Driven by whatever frame time the caller measures: `FrameResult.cpuMicros`,
/// or the sum of `FramePass.gpuMicros` where the device reports them (H2).
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

import 'quality_table.dart';
import 'render_settings.dart';

/// What the controller aims at, and how cautiously.
final class AdaptiveQualitySettings {
  const AdaptiveQualitySettings({
    this.enabled = false,
    this.budgetMicros = 16667,
    this.headroom = 0.9,
    this.climbHeadroom = 0.75,
    this.climbFrames = 30,
    this.smoothing = 0.1,
    this.correctionSmoothing = 0.02,
    this.motionThreshold = 0.0,
    this.motionScale = 0.7,
  }) : assert(budgetMicros > 0),
       assert(
         climbHeadroom < headroom && headroom <= 1.0,
         'climbing has to want more room than staying, or the quality '
         'oscillates across the one margin where they meet',
       ),
       assert(climbFrames >= 1),
       assert(smoothing > 0.0 && smoothing <= 1.0),
       assert(correctionSmoothing >= 0.0 && correctionSmoothing <= 1.0);

  /// Off by default: an application that has not asked for its settings to
  /// move should not find them moving.
  final bool enabled;

  /// The frame time aimed at, in microseconds. 16667 is sixty a second.
  final int budgetMicros;

  /// A row is kept while its estimate is under this share of the budget.
  /// The tenth left over is what a row's time can grow in one frame without
  /// the frame being late — heat does not arrive faster than that.
  final double headroom;

  /// A better row is climbed to only when its estimate is under this share.
  final double climbHeadroom;

  /// Frames in a row a better row has to fit before it is climbed to.
  final int climbFrames;

  /// How fast `load` comes back down after a slow frame, per frame.
  final double smoothing;

  /// How fast a row's correction follows its measurements, per frame it is
  /// visited. Slow: it is a property of the device, not of the moment.
  final double correctionSmoothing;

  /// Screen motion, as [screenMotion] measures it, above which the picture
  /// is taken to be moving too fast to resolve. Nought is never.
  final double motionThreshold;

  /// The largest render scale a row may have while in motion.
  final double motionScale;
}

/// Chooses a [QualityRow] of [table] each frame.
///
/// Holds its own state: feed it every frame's time and read [row], or pass
/// the application's settings through [apply].
final class AdaptiveQuality {
  AdaptiveQuality(this.table, [this.settings = const AdaptiveQualitySettings()])
    : _correction = List<double>.filled(table.rows.length, 1.0);

  final QualityTable table;
  final AdaptiveQualitySettings settings;

  /// Microseconds per unit of cost, or null before the first frame.
  double? _load;
  final List<double> _correction;
  int _index = 0;
  int _climbCount = 0;
  int _climbTarget = -1;

  /// Where in [QualityTable.rows] the controller sits.
  int get index => _index;

  /// The row the next frame should be drawn at.
  QualityRow get row => table.rows[_index];

  /// [full] at [row], or [full] itself while disabled.
  RenderSettings apply(RenderSettings full) =>
      settings.enabled ? row.setting.apply(full) : full;

  /// What row [i] is expected to cost now, in microseconds, or null before
  /// anything has been measured.
  double? estimateMicros(int i) {
    final load = _load;
    return load == null ? null : load * table.rows[i].cost * _correction[i];
  }

  /// Feeds in the time the last frame took at [row] and returns the row for
  /// the next. [motion] is how fast the picture moves, see [screenMotion].
  ///
  /// Disabled, this sits at full quality and forgets what it measured.
  QualityRow recordFrame(int micros, {double motion = 0.0}) {
    if (!settings.enabled) {
      _load = null;
      _correction.fillRange(0, _correction.length, 1.0);
      _index = 0;
      _climbCount = 0;
      _climbTarget = -1;
      return row;
    }

    final current = table.rows[_index];
    final unit = current.cost * _correction[_index];
    final implied = micros / unit;
    final load = _load;
    if (load == null) {
      _load = implied;
    } else {
      // How far this row missed its prediction, split between the moment
      // (load) and the row (correction). The row takes a small share, so a
      // spike moves the load and a steady miss moves the row.
      final surprise = implied / load;
      _correction[_index] *=
          1.0 + settings.correctionSmoothing * (surprise - 1.0);
      final corrected = micros / (current.cost * _correction[_index]);
      _load = corrected > load
          ? corrected
          : load + settings.smoothing * (corrected - load);
    }

    final budget = settings.budgetMicros.toDouble();
    final moving =
        settings.motionThreshold > 0.0 && motion > settings.motionThreshold;
    // Never below the table's own smallest scale, or nothing would be left.
    final motionScale = math.max(
      settings.motionScale,
      table.rows.map((QualityRow r) => r.setting.renderScale).reduce(math.min),
    );
    bool allowed(int i) =>
        !moving || table.rows[i].setting.renderScale <= motionScale;
    bool fits(int i, double share) => estimateMicros(i)! <= budget * share;

    // The best row that fits with the staying margin; the cheapest allowed
    // when none does.
    int bestFitting(double share) {
      for (var i = 0; i < table.rows.length; i++) {
        if (allowed(i) && fits(i, share)) return i;
      }
      var cheapest = -1;
      for (var i = 0; i < table.rows.length; i++) {
        if (!allowed(i)) continue;
        if (cheapest < 0 || estimateMicros(i)! < estimateMicros(cheapest)!) {
          cheapest = i;
        }
      }
      return cheapest;
    }

    if (!allowed(_index) || !fits(_index, settings.headroom)) {
      // Down at once, to the best row that fits.
      _index = bestFitting(settings.headroom);
      _climbCount = 0;
      _climbTarget = -1;
      return row;
    }

    // Up only after the better row has fitted with room to spare for
    // [climbFrames] frames running.
    final target = bestFitting(settings.climbHeadroom);
    if (target >= 0 &&
        target < _index &&
        fits(target, settings.climbHeadroom)) {
      _climbCount = target == _climbTarget ? _climbCount + 1 : 1;
      _climbTarget = target;
      if (_climbCount >= settings.climbFrames) {
        _index = target;
        _climbCount = 0;
        _climbTarget = -1;
      }
    } else {
      _climbCount = 0;
      _climbTarget = -1;
    }
    return row;
  }
}

/// How far the picture moved between two frames, as a fraction of the
/// screen's width: the mean distance five points spread over the view moved
/// between [previous] and [current], two unjittered view-projections
/// (`FrameHistory.viewProjection` and `CameraNode.viewProjection`).
///
/// The points sit halfway into the clip-space depth range, so a turn counts
/// in full and a step forward counts as much as it moves something at that
/// depth. Nought for a still camera.
double screenMotion(vm.Matrix4 previous, vm.Matrix4 current) {
  final inverse = vm.Matrix4.inverted(current);
  const points = <(double, double)>[
    (0.0, 0.0),
    (-0.5, -0.5),
    (0.5, -0.5),
    (-0.5, 0.5),
    (0.5, 0.5),
  ];
  var sum = 0.0;
  for (final (x, y) in points) {
    final world = inverse.transform(vm.Vector4(x, y, 0.5, 1.0));
    final then = previous.transform(world);
    final dx = then.x / then.w - x;
    final dy = then.y / then.w - y;
    // Clip space is two wide.
    sum += math.sqrt(dx * dx + dy * dy) * 0.5;
  }
  return sum / points.length;
}
