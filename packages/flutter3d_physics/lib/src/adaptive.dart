/// The adaptive integrator the accurate profile steps with: an embedded
/// Runge–Kutta pair that chooses its own steps inside the loop's fixed one.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart' show Portable;

/// The derivative of a state [y] at time [t], written into [dy].
typedef Derivative = void Function(double t, Float64List y, Float64List dy);

/// Dormand and Prince's 5(4) pair (Hairer, Nørsett and Wanner, *Solving
/// Ordinary Differential Equations I*, 2nd ed., 1993, §II.5), with the
/// step-size control of §II.4: a step is kept when the difference between
/// the fifth- and the fourth-order answers, measured against [relative]
/// times the state plus [absolute], is under one, and the next step is
/// grown or shrunk by the fifth root of how far under or over it was.
///
/// **Behind the fixed step, never instead of it.** [integrate] goes from
/// one time to the next exactly, as many steps of its own between as the
/// tolerance asks: the loop still steps at its rate, saves at its steps and
/// publishes at its steps; what changes is what happens inside one.
///
/// Not part of the package's surface: the profile is chosen by its name
/// (`SimulationProfile.accurate`), and the tolerances are stated where the
/// profile is documented.
final class DormandPrince {
  /// An integrator holding the accurate profile's tolerances unless given,
  /// giving up after 100 000 steps of one [integrate].
  DormandPrince({
    this.relative = defaultRelative,
    this.absolute = defaultAbsolute,
    this.maxSteps = 100000,
  });

  /// The relative tolerance the accurate profile holds a state to, a
  /// fraction of the state.
  static const double defaultRelative = 1e-10;

  /// The absolute tolerance, in the state's own units (metres, metres per
  /// second).
  static const double defaultAbsolute = 1e-12;

  /// The relative tolerance of this integrator, a fraction of the state.
  final double relative;

  /// The absolute tolerance of this integrator, in the state's own units
  /// (metres, metres per second).
  final double absolute;

  /// How many steps one [integrate] may take before it gives up with a
  /// [StateError]: a state that needs more is stiffer than an explicit
  /// method can follow, and saying so beats hanging.
  final int maxSteps;

  /// The step the last [integrate] ended on, the next one's first guess;
  /// null before the first.
  double? lastStep;

  /// How many steps the last [integrate] kept, and how many it threw away.
  int accepted = 0, rejected = 0;

  Float64List _k1 = Float64List(0);
  Float64List _k2 = Float64List(0);
  Float64List _k3 = Float64List(0);
  Float64List _k4 = Float64List(0);
  Float64List _k5 = Float64List(0);
  Float64List _k6 = Float64List(0);
  Float64List _k7 = Float64List(0);
  Float64List _stage = Float64List(0);
  Float64List _next = Float64List(0);

  void _size(int n) {
    if (_k1.length == n) return;
    _k1 = Float64List(n);
    _k2 = Float64List(n);
    _k3 = Float64List(n);
    _k4 = Float64List(n);
    _k5 = Float64List(n);
    _k6 = Float64List(n);
    _k7 = Float64List(n);
    _stage = Float64List(n);
    _next = Float64List(n);
  }

  /// Carries [y] from [from] to [to] under [derivative], in place.
  ///
  /// [after] runs after every kept step with the time reached and the
  /// state, which it may change — a constraint's projection back onto
  /// itself, a contact's push — before the next step starts from it.
  void integrate(
    Float64List y,
    double from,
    double to,
    Derivative derivative, {
    void Function(double t, Float64List y)? after,
  }) {
    final span = to - from;
    accepted = 0;
    rejected = 0;
    if (span <= 0.0) return;
    final n = y.length;
    _size(n);
    var t = from;
    var h = math.min(lastStep ?? span, span);
    var steps = 0;
    while (t < to) {
      if (++steps > maxSteps) {
        throw StateError(
          'the accurate profile took $maxSteps steps inside one of '
          '${span}s and did not reach its end: the state is stiffer than '
          'its explicit integrator can follow',
        );
      }
      final last = t + h >= to;
      if (last) h = to - t;
      derivative(t, y, _k1);
      _stageOf(y, h, const [_a21], [_k1]);
      derivative(t + _c2 * h, _stage, _k2);
      _stageOf(y, h, const [_a31, _a32], [_k1, _k2]);
      derivative(t + _c3 * h, _stage, _k3);
      _stageOf(y, h, const [_a41, _a42, _a43], [_k1, _k2, _k3]);
      derivative(t + _c4 * h, _stage, _k4);
      _stageOf(y, h, const [_a51, _a52, _a53, _a54], [_k1, _k2, _k3, _k4]);
      derivative(t + _c5 * h, _stage, _k5);
      _stageOf(
        y,
        h,
        const [_a61, _a62, _a63, _a64, _a65],
        [_k1, _k2, _k3, _k4, _k5],
      );
      derivative(t + h, _stage, _k6);
      for (var i = 0; i < n; i++) {
        _next[i] =
            y[i] +
            h *
                (_b1 * _k1[i] +
                    _b3 * _k3[i] +
                    _b4 * _k4[i] +
                    _b5 * _k5[i] +
                    _b6 * _k6[i]);
      }
      derivative(t + h, _next, _k7);
      var sum = 0.0;
      for (var i = 0; i < n; i++) {
        final e =
            h *
            (_e1 * _k1[i] +
                _e3 * _k3[i] +
                _e4 * _k4[i] +
                _e5 * _k5[i] +
                _e6 * _k6[i] +
                _e7 * _k7[i]);
        final scale =
            absolute + relative * math.max(y[i].abs(), _next[i].abs());
        final r = e / scale;
        sum += r * r;
      }
      final error = n == 0 ? 0.0 : math.sqrt(sum / n);
      final grow = error == 0.0
          ? 5.0
          : math.min(5.0, math.max(0.2, 0.9 * Portable.pow(error, -0.2)));
      if (error <= 1.0) {
        t = last ? to : t + h;
        y.setAll(0, _next);
        after?.call(t, y);
        accepted++;
        // The step that reached the end was cut to fit; the one before it is
        // the better guess for the next call.
        if (!last) lastStep = h * grow;
        lastStep ??= h * grow;
        h *= grow;
      } else {
        rejected++;
        h *= grow;
        if (h <= span * 1e-14) {
          throw StateError(
            'the accurate profile could not hold its tolerance with a step '
            'of ${h}s: the state is not smooth there',
          );
        }
      }
    }
  }

  void _stageOf(Float64List y, double h, List<double> a, List<Float64List> k) {
    for (var i = 0; i < y.length; i++) {
      var s = 0.0;
      for (var j = 0; j < a.length; j++) {
        s += a[j] * k[j][i];
      }
      _stage[i] = y[i] + h * s;
    }
  }

  static const double _c2 = 1 / 5, _c3 = 3 / 10, _c4 = 4 / 5, _c5 = 8 / 9;
  static const double _a21 = 1 / 5;
  static const double _a31 = 3 / 40, _a32 = 9 / 40;
  static const double _a41 = 44 / 45, _a42 = -56 / 15, _a43 = 32 / 9;
  static const double _a51 = 19372 / 6561,
      _a52 = -25360 / 2187,
      _a53 = 64448 / 6561,
      _a54 = -212 / 729;
  static const double _a61 = 9017 / 3168,
      _a62 = -355 / 33,
      _a63 = 46732 / 5247,
      _a64 = 49 / 176,
      _a65 = -5103 / 18656;
  static const double _b1 = 35 / 384,
      _b3 = 500 / 1113,
      _b4 = 125 / 192,
      _b5 = -2187 / 6784,
      _b6 = 11 / 84;
  // The fifth-order weights less the fourth-order ones.
  static const double _e1 = 71 / 57600,
      _e3 = -71 / 16695,
      _e4 = 71 / 1920,
      _e5 = -17253 / 339200,
      _e6 = 22 / 525,
      _e7 = -1 / 40;
}
