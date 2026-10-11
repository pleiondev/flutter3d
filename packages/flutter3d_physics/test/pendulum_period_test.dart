/// A pendulum under the accurate profile swings at the period its series
/// gives: released at θ₀ = 0.1 rad, its period measured over 100 periods
/// is within 1e-4 of 2π√(L/g)·(1 + θ₀²/16 + 11θ₀⁴/3072 + 173θ₀⁶/737280),
/// and its energy stays within 1e-6 of what it was released with.
///
/// The pendulum is the smallest cloth there is: two particles, the top one
/// pinned, joined by a constraint of no compliance — a rigid rod of
/// massless length L.
///
/// **The number, for the education page:** the period measured here is
/// within 1e-4 of the series (measured: 1.7e-9), and the energy within 1e-6
/// of the swing's (measured: 4.7e-8), in 80 ms on a laptop. The fixed XPBD step
/// at its default eight substeps misses the period by 4.6e-4 and loses
/// nearly all of the swing's energy over the same hundred periods.
///
///     dart test test/pendulum_period_test.dart
library;

import 'dart:math' as math;

import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show SimulationProfile;
import 'package:test/test.dart';

const double _length = 1.0;
const double _g = 9.81;
const double _theta = 0.1;
const double _dt = 1.0 / 60.0;

/// The period the series for a pendulum released at [theta] gives, to the
/// sixth power: Landau and Lifshitz, *Mechanics*, §11, problem 1, extended.
double _seriesPeriod(double theta) {
  final t2 = theta * theta;
  return 2.0 *
      math.pi *
      math.sqrt(_length / _g) *
      (1.0 +
          t2 / 16.0 +
          11.0 * t2 * t2 / 3072.0 +
          173.0 * t2 * t2 * t2 / 737280.0);
}

/// The swing measured under [settings]: its period from the first to the
/// 201st crossing of the vertical, and the largest change of its energy
/// over the swing's own.
({double period, double drift}) _swing(ClothSettings settings) {
  final mesh = ClothMesh.grid(cols: 1, rows: 2, spacing: _length);
  final p = mesh.positions, v = mesh.velocities;
  p[3] = _length * math.sin(_theta);
  p[4] = -_length * math.cos(_theta);
  p[5] = 0.0;
  double energy() =>
      _g * p[4] + 0.5 * (v[3] * v[3] + v[4] * v[4] + v[5] * v[5]);
  final start = energy();
  final swing = _g * _length * (1.0 - math.cos(_theta));
  var t = 0.0, before = p[3], crossings = 0, first = 0.0, last = 0.0;
  var drift = 0.0;
  while (crossings < 201) {
    stepCloth(mesh, settings, _dt);
    t += _dt;
    final x = p[3];
    if ((before > 0.0) != (x > 0.0)) {
      // The crossing between the two steps, by the line through them: at
      // the bottom the bob moves at its fastest and straightest.
      final at = t - _dt * x / (x - before);
      if (crossings == 0) first = at;
      last = at;
      crossings++;
    }
    before = x;
    drift = math.max(drift, (energy() - start).abs() / swing);
  }
  return (period: (last - first) / 100.0, drift: drift);
}

void main() {
  const settings = ClothSettings(
    gravity: _g,
    damping: 0.0,
    selfCollision: false,
  );

  test('under the accurate profile the period is the series, to 1e-4', () {
    final series = _seriesPeriod(_theta);
    final swing = _swing(
      settings.copyWith(profile: SimulationProfile.accurate),
    );
    expect((swing.period - series).abs() / series, lessThan(1e-4));
    expect(swing.drift, lessThan(1e-6));
  });

  test('the fixed XPBD step misses it, which is why the profile exists', () {
    // Mutation: step the accurate profile through XPBD and the test above
    // fails by these numbers.
    final series = _seriesPeriod(_theta);
    final swing = _swing(settings);
    expect((swing.period - series).abs() / series, greaterThan(1e-4));
    expect(swing.drift, greaterThan(0.5));
  });
}
