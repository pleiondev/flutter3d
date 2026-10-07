/// What the physics sounds like: each fire, each fall of water and each
/// splash as a source with a place and a loudness, read off the core every
/// frame, for whatever plays sound to turn into voices.
library;

import 'dart:math' as math;

import 'package:flutter3d_physics_native/flutter3d_physics_native.dart';
import 'package:vector_math/vector_math.dart';

/// One thing heard: where, how loud from nought to one, and how fast its
/// sound plays, one being the recording's own speed. [key] stays the same
/// while the same thing goes on sounding — a fire, a fall — so a looping
/// voice can be held to it.
final class Audible {
  const Audible(this.key, this.at, this.loudness, this.rate);

  final int key;
  final Vector3 at;
  final double loudness;
  final double rate;
}

/// The physics, heard. No sound is made here — this package has no audio —
/// only what a game's mixer is to play: a looping crackle for every fire, as
/// loud as its watts; a looping roar for falling water, as loud as the power
/// the water gives up as it falls; and a splash, once, where a watched body
/// goes into a liquid, as loud as the energy it goes in with.
///
/// Loudness follows the logarithm of the power, as hearing does: a fire ten
/// times hotter is a step louder, not ten times louder.
final class PhysicsHearing {
  PhysicsHearing(this._world);

  final NativeWorld _world;
  final List<(NativeShallowLiquid, double)> _liquids =
      <(NativeShallowLiquid, double)>[];
  final Map<NativeBody, (NativeShallowLiquid, bool)> _watched =
      <NativeBody, (NativeShallowLiquid, bool)>{};

  /// The fires burning now, one each.
  final List<Audible> fires = <Audible>[];

  /// The water falling now, gathered by where it falls: one to each
  /// [fallCell]-metre square of ground it falls over.
  final List<Audible> falls = <Audible>[];

  /// The splashes since the last [update], each to be played once.
  final List<Audible> splashes = <Audible>[];

  /// How wide a square of falling water is heard as one, m.
  static const double fallCell = 6.0;

  /// Falling water of [liquid], [density] kg/m³, heard.
  void listen(NativeShallowLiquid liquid, {double density = 1000.0}) =>
      _liquids.add((liquid, density));

  /// [body] splashes when it goes into [liquid].
  void watch(NativeBody body, NativeShallowLiquid liquid) =>
      _watched.putIfAbsent(body, () => (liquid, false));

  /// [body] no longer watched, for a game taking it out of the world.
  void forget(NativeBody body) => _watched.remove(body);

  /// A fire of [watts] heard: silent at half a kilowatt — a candle, a
  /// smouldering ember — and at its loudest at half a megawatt, a house.
  static double fireLoudness(double watts) => _scale(watts, 500.0, 5e5);

  /// Falling water giving up [watts] heard: silent at fifty, a trickle off a
  /// step, loudest at a hundred kilowatts, a river over a cliff.
  static double fallLoudness(double watts) => _scale(watts, 50.0, 1e5);

  /// A splash of [joules] heard: silent at twenty, a stone dropped from a
  /// hand, loudest at twenty kilojoules, a log off a waterfall.
  static double splashLoudness(double joules) => _scale(joules, 20.0, 2e4);

  /// A bigger source sounds lower: its speed falls a little with each
  /// tenfold of [power] past [reference].
  static double rateFor(double power, double reference) =>
      math.pow(math.max(power, 1e-9) / reference, -0.06).clamp(0.7, 1.4)
          as double;

  static double _scale(double value, double quiet, double loud) =>
      value <= quiet
      ? 0.0
      : (math.log(value / quiet) / math.log(loud / quiet)).clamp(0.0, 1.0);

  /// Everything heard this frame.
  void update() {
    _hearFires();
    _hearFalls();
    _hearSplashes();
  }

  void _hearFires() {
    fires.clear();
    final read = _world.readFires();
    final seen = <int, int>{};
    for (var i = 0; i < read.bodies.length; i++) {
      final o = i * nativeFireFloats;
      final watts = read.fires[o + 3].toDouble();
      final loudness = fireLoudness(watts);
      if (loudness <= 0.0) continue;
      // A compound burns part by part; each part its own crackle.
      final body = read.bodies[i];
      final part = seen[body.raw] = (seen[body.raw] ?? -1) + 1;
      fires.add(
        Audible(
          body.raw * 64 + part,
          Vector3(read.fires[o], read.fires[o + 1], read.fires[o + 2]),
          loudness,
          rateFor(watts, 2e4),
        ),
      );
    }
  }

  void _hearFalls() {
    falls.clear();
    // The power falling water gives up is its weight times how fast it
    // falls: m g |v_y|, summed over a square, heard from where it is
    // weighted most.
    final cells = <int, (double, Vector3)>{};
    for (final (liquid, density) in _liquids) {
      final spray = _world.readSpray(of: liquid);
      for (
        var o = 0;
        o + nativeSprayFloats <= spray.length;
        o += nativeSprayFloats
      ) {
        final down = -spray[o + 4];
        if (down <= 0.0) continue;
        final watts = density * spray[o + 6] * 9.81 * down;
        final x = spray[o], y = spray[o + 1], z = spray[o + 2];
        final key = (x / fallCell).floor() * 100003 + (z / fallCell).floor();
        final (sum, at) = cells[key] ?? (0.0, Vector3.zero());
        cells[key] = (sum + watts, at..add(Vector3(x, y, z) * watts));
      }
    }
    for (final MapEntry(:key, value: (watts, at)) in cells.entries) {
      final loudness = fallLoudness(watts);
      if (loudness <= 0.0) continue;
      falls.add(Audible(key, at / watts, loudness, rateFor(watts, 5e3)));
    }
  }

  void _hearSplashes() {
    splashes.clear();
    for (final MapEntry(key: body, value: (liquid, wasIn))
        in _watched.entries.toList()) {
      final p = _world.positionOf(body);
      final here = _world.sampleShallow(liquid, p.x, p.z);
      final isIn = here != null && here.depth > 0.0 && p.y < here.surface;
      _watched[body] = (liquid, isIn);
      if (!isIn || wasIn) continue;
      final down = -_world.velocityOf(body).y;
      final joules = 0.5 * _world.massOf(body) * down * down;
      final loudness = down > 0.0 ? splashLoudness(joules) : 0.0;
      if (loudness <= 0.0) continue;
      splashes.add(
        Audible(
          body.raw,
          Vector3(p.x, here.surface, p.z),
          loudness,
          rateFor(joules, 2e3),
        ),
      );
    }
  }
}
