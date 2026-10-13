/// The pendulum laboratory's simulation: a pendulum on the accurate
/// profile, its angle and its measured period published by probes.
library;

import 'dart:math' as math;

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

/// Builds the laboratory where it runs: a loop of its own on
/// [SimulationProfile.accurate] with the pendulum in it.
///
/// **A top-level function**, because the view places the simulation with
/// `SimulationPlacement.isolate(pendulumSimulation)`, and a loop that runs
/// in an isolate is built there, on the profile it asks for; inline, the
/// view's own loop would take it from `LoopSettings.profile`. On the web the
/// same function runs in the page, stepped the same way.
SimulationSetup pendulumSimulation(Object? arguments) {
  final loop = EngineLoop(
    input: InputState(),
    profile: SimulationProfile.accurate,
  );
  PendulumLab.install(loop);
  return SimulationSetup(loop: loop, applyInput: (_) {});
}

/// A pendulum released at [releasedAt] from the vertical: a rod of
/// massless [length] with a point mass on its end, in a world of standard
/// gravity and still air.
///
/// **What the laboratory measures, it measures with probes.** The angle
/// from the vertical ([angleProbe]) is read every step, and the period
/// ([periodProbe]) from the times the bob crosses the vertical, averaged
/// over every crossing so far; the view reads both from what the simulation
/// published and never from the pendulum.
///
/// **The pendulum is the smallest cloth there is**: two particles, the top
/// one pinned, joined by a constraint of no compliance. Its settings take
/// the world's profile (`ClothSettings.inWorld`), so on the accurate profile
/// it is integrated with the rod held exactly, and the period it shows is
/// within 1e-4 of [seriesPeriod] over a hundred swings; on the fixed XPBD
/// step a game runs it would miss by 4.6e-4 and lose most of the swing.
final class PendulumLab {
  PendulumLab._(this._mesh, this._settings);

  /// The probe on the angle from the vertical, in radians.
  static const String angleProbe = 'pendulum.angle';

  /// The probe on the measured period, in seconds; no reading until the bob
  /// has crossed the vertical twice.
  static const String periodProbe = 'pendulum.period';

  /// The quantity [angleProbe] reads.
  static const String angleId = 'lab.pendulum.angle';

  /// The quantity [periodProbe] reads.
  static const String periodId = 'lab.pendulum.period';

  /// The rod, in metres.
  static const double length = 1.0;

  /// Where it is let go from, radians from the vertical.
  static const double releasedAt = 0.1;

  /// The period the series gives for a pendulum of [length] released at
  /// [releasedAt] in standard gravity, to the sixth power of the angle:
  /// 2π√(L/g)·(1 + θ²/16 + 11θ⁴/3072 + 173θ⁶/737280).
  static double seriesPeriod() {
    const t2 = releasedAt * releasedAt;
    return 2.0 *
        math.pi *
        math.sqrt(length / standardGravity) *
        (1.0 +
            t2 / 16.0 +
            11.0 * t2 * t2 / 3072.0 +
            173.0 * t2 * t2 * t2 / 737280.0);
  }

  /// Puts the pendulum into [loop]: the step that swings it, the samplers
  /// of its two quantities and an entity carrying the two probes.
  factory PendulumLab.install(EngineLoop loop) {
    final mesh = ClothMesh.grid(cols: 1, rows: 2, spacing: length);
    final p = mesh.positions;
    p[3] = length * math.sin(releasedAt);
    p[4] = -length * math.cos(releasedAt);
    p[5] = 0.0;
    final lab = PendulumLab._(
      mesh,
      const ClothSettings(
        damping: 0.0,
        selfCollision: false,
      ).inWorld(WorldProperties(profile: loop.profile)),
    );
    loop
      ..addSystem('lab.pendulum', LoopPhase.physics, lab._step)
      ..probeSamplers.add(
        angleId,
        ProbeSampler.of((_) => Quantity(lab.angle, Unit.radian)),
      )
      ..probeSamplers.add(
        periodId,
        ProbeSampler.of(
          (_) => switch (lab.period) {
            null => null,
            final period => Quantity(period, Unit.second),
          },
        ),
      );
    final bob = loop.world.spawn();
    loop.world
      ..set<Probe>(
        bob,
        Probe(id: angleProbe, quantity: angleId, unit: Unit.radian),
      )
      ..set<Probe>(
        loop.world.spawn(),
        Probe(id: periodProbe, quantity: periodId, unit: Unit.second),
      );
    return lab;
  }

  final ClothMesh _mesh;
  final ClothSettings _settings;

  double _time = 0.0;
  int _crossings = 0;
  double _first = 0.0;
  double _last = 0.0;

  /// The angle from the vertical now, radians: positive to +x.
  double get angle {
    final p = _mesh.positions;
    return math.atan2(p[3], -p[4]);
  }

  /// The period measured so far, seconds, or null before the second
  /// crossing of the vertical.
  double? get period =>
      _crossings < 2 ? null : 2.0 * (_last - _first) / (_crossings - 1);

  void _step(LoopContext context) {
    final before = _mesh.positions[3];
    stepCloth(_mesh, _settings, context.dt);
    _time += context.dt;
    final x = _mesh.positions[3];
    if ((before > 0.0) != (x > 0.0)) {
      // The crossing between the two steps, by the line through them: at
      // the bottom the bob moves at its fastest and straightest.
      final at = _time - context.dt * x / (x - before);
      if (_crossings == 0) _first = at;
      _last = at;
      _crossings++;
    }
  }
}
