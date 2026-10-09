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

  /// How loud, a fraction from nought to one.
  final double loudness;

  /// How fast its sound plays, a multiplier on the recording's own speed.
  final double rate;
}

/// How loud a kind of thing the physics does is heard, set by the game:
/// what power — W for a fire or a fall, J for a splash — is silent, what is
/// as loud as the game plays anything, and what plays at the recording's
/// own speed.
///
/// Loudness follows the logarithm of the power, as hearing does: a source
/// ten times stronger is a step louder, not ten times louder. A bigger
/// source sounds lower: its speed falls by [pitch] in the exponent with
/// each tenfold past [reference], within [slowest] and [fastest].
final class HearingScale {
  const HearingScale({
    required this.quiet,
    required this.loud,
    required this.reference,
    this.pitch = 0.06,
    this.slowest = 0.7,
    this.fastest = 1.4,
  });

  /// The power that is silent, and the power at full loudness.
  final double quiet, loud;

  /// The power that plays at the recording's own speed.
  final double reference;

  /// How a sound's speed goes with its power: (power / reference)^−pitch,
  /// within [slowest] and [fastest].
  final double pitch, slowest, fastest;

  /// [power] heard, nought to one.
  double loudness(double power) => power <= quiet
      ? 0.0
      : (math.log(power / quiet) / math.log(loud / quiet)).clamp(0.0, 1.0);

  /// How fast a source of [power] plays.
  double rate(double power) =>
      math
              .pow(math.max(power, 1e-9) / reference, -pitch)
              .clamp(slowest, fastest)
          as double;
}

/// The physics, heard. No sound is made here — this package has no audio —
/// only what a game's mixer is to play: a looping crackle for every fire, as
/// loud as its watts; a looping roar for falling water, as loud as the power
/// the water gives up as it falls; and a splash, once, where a body goes
/// into a liquid, as loud as the energy it goes in with. Each is heard on
/// the game's own [HearingScale].
final class PhysicsHearing {
  PhysicsHearing(
    this._world, {
    required this.fireScale,
    required this.fallScale,
    required this.splashScale,
  });

  /// How fires, falls of water and splashes are heard.
  final HearingScale fireScale, fallScale, splashScale;

  final NativeWorld _world;
  final List<(NativeShallowLiquid, double)> _liquids =
      <(NativeShallowLiquid, double)>[];

  /// The fires burning now, one each.
  final List<Audible> fires = <Audible>[];

  /// The water falling now, gathered by where it falls: one to each
  /// [fallCell]-metre square of ground it falls over.
  final List<Audible> falls = <Audible>[];

  /// The splashes since the last [update], each to be played once.
  final List<Audible> splashes = <Audible>[];

  /// How wide a square of falling water is heard as one, in metres.
  static const double fallCell = 6.0;

  /// Falling water of [liquid], [density] kg/m³, heard: the liquid's, from
  /// its preset — [NativeLiquidProperties.water]'s when none is given.
  void listen(NativeShallowLiquid liquid, {double? density}) =>
      _liquids.add((liquid, density ?? NativeLiquidProperties.water.density));

  /// Falling water of [liquid] no longer heard, for a water taken out.
  void unlisten(NativeShallowLiquid liquid) =>
      _liquids.removeWhere((l) => l.$1.id == liquid.id);

  /// How often the fires and the falls are heard again, s: a fire's roar
  /// changes over seconds, and reading every drop in flight each frame
  /// costs more than an ear can tell.
  static const double every = 0.1;
  double _since = every;

  /// Everything heard this frame, [dt] seconds after the last, and the
  /// splashes of the bodies the step's [events] say came into a liquid.
  void update(double dt, {List<NativeEvent> events = const <NativeEvent>[]}) {
    _since += dt;
    if (_since >= every) {
      _since = 0.0;
      _hearFires();
      _hearFalls();
    }
    _hearSplashes(events);
  }

  void _hearFires() {
    fires.clear();
    final read = _world.readFires();
    final seen = <int, int>{};
    for (var i = 0; i < read.bodies.length; i++) {
      final o = i * nativeFireFloats;
      final watts = read.fires[o + 3].toDouble();
      final loudness = fireScale.loudness(watts);
      if (loudness <= 0.0) continue;
      // A compound burns part by part; each part its own crackle.
      final body = read.bodies[i];
      final part = seen[body.raw] = (seen[body.raw] ?? -1) + 1;
      fires.add(
        Audible(
          body.raw * 64 + part,
          Vector3(read.fires[o], read.fires[o + 1], read.fires[o + 2]),
          loudness,
          fireScale.rate(watts),
        ),
      );
    }
  }

  void _hearFalls() {
    falls.clear();
    // The world's pull: what the water's weight is, and so what it gives up.
    final g = _world.gravityMagnitude;
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
        final watts = density * spray[o + 6] * g * down;
        final x = spray[o], y = spray[o + 1], z = spray[o + 2];
        final key = (x / fallCell).floor() * 100003 + (z / fallCell).floor();
        final (sum, at) = cells[key] ?? (0.0, Vector3.zero());
        cells[key] = (sum + watts, at..add(Vector3(x, y, z) * watts));
      }
    }
    for (final MapEntry(:key, value: (watts, at)) in cells.entries) {
      final loudness = fallScale.loudness(watts);
      if (loudness <= 0.0) continue;
      falls.add(Audible(key, at / watts, loudness, fallScale.rate(watts)));
    }
  }

  /// A body come into a liquid splashes as loud as the energy it came
  /// down with, ½mv², v its speed downwards.
  void _hearSplashes(List<NativeEvent> events) {
    splashes.clear();
    for (final e in events) {
      if (e.kind != NativeEventKind.wetted || !_world.contains(e.body)) {
        continue;
      }
      final down = -_world.velocityOf(e.body).y;
      if (down <= 0.0) continue;
      final joules = 0.5 * _world.massOf(e.body) * down * down;
      final loudness = splashScale.loudness(joules);
      if (loudness <= 0.0) continue;
      splashes.add(
        Audible(
          e.body.raw,
          _world.localPositionOf(e.body),
          loudness,
          splashScale.rate(joules),
        ),
      );
    }
  }
}
