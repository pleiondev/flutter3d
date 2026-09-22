import 'package:vector_math/vector_math.dart';

import 'particle_system.dart';

/// One burst, where it happens, and which way it goes.
///
/// **A decision, not an emission.** What a step of a game ought to show is a
/// fact about the simulation and can be asserted without a device; bursting it
/// needs a system, a device and a frame. Two applications wrote this class
/// identically, and both wrote it for the same reason: their particles lived in
/// private methods of a widget nothing could mount, so no test in either had
/// ever mentioned a particle — a monster dying with no sparks and a rocket
/// landing with no fire were each something somebody had to happen to notice.
///
/// What stays with each game is what it decides to show. This is the shape of
/// the answer.
final class Shown {
  const Shown(this.effect, this.at, {this.direction});

  final ParticleEffect effect;

  final Vector3 at;

  /// A surface normal, a barrel's line, the up somebody was thrown along —
  /// whatever the effect should lean along. Null is the effect's own shape.
  final Vector3? direction;

  @override
  String toString() => 'Shown(at $at)';
}
