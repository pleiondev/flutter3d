/// A [Brain] that walks a straight line between two points and turns round
/// at each end — a sentry's beat, not a chase.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

/// The whole of "drift or patrol" a `flutter3d_demo_arcade` drone needs.
///
/// [ActorSystem.step] calls [act] once a step for every actor that carries
/// this brain, which is the only place a drone's movement is decided — the
/// same seam `ActorSystemComponent` steps through, so a drone genuinely
/// walks under the actor system rather than being pushed around by hand.
/// Nothing here reads the player's position: a drone that turned to chase
/// the ship would be a different, and more elaborate, game than this one.
final class PatrolBrain extends Brain {
  PatrolBrain(this.from, this.to);

  /// The two ends of the beat, in world space.
  final Vector3 from;
  final Vector3 to;

  /// Which end this drone is currently walking towards.
  bool _towardTo = true;

  @override
  void act(Mind it) {
    final position = it.actor.body?.position;
    if (position == null) return;

    if ((position - (_towardTo ? to : from)).length < 0.5) {
      _towardTo = !_towardTo;
    }
    it.steerTowards(_towardTo ? to : from);
  }
}
