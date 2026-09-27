/// A [Brain] for a drone of the yard: it walks a beat, and on the harder
/// levels it also chases the ship and sidesteps a ram.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

/// Everything a `flutter3d_demo_arcade` drone decides, once a step.
///
/// [ActorSystem.step] calls [act] for every actor that carries this brain,
/// which is the only place a drone's movement is decided, so a drone walks
/// under the actor system rather than being pushed around by hand. The ship
/// is the system's focus, so [Mind.toFocus] is the way to it.
///
/// Three behaviours, the first that applies wins:
///
/// * **Sidestep** within [dodgeRadius], when the ship is flying at this
///   drone: it steps across the ship's line, to whichever side it already
///   stands on. A ram is a head-on contact, so a drone that leaves the line
///   turns the ram into the ship being struck from the side.
/// * **Chase** within [chaseRadius]: it heads straight for the ship. A
///   straight line rather than [Mind.steerTowardsFocus], which follows a
///   flow field the yard does not bake.
/// * **Patrol** between [from] and [to], turning round at each end.
final class DroneBrain extends Brain {
  DroneBrain(
    this.from,
    this.to, {
    this.chaseRadius = 0.0,
    this.dodgeRadius = 0.0,
    this.shipHeading,
  });

  /// The two ends of the beat, in world space.
  final Vector3 from;
  final Vector3 to;

  /// How near the ship has to be for this drone to give chase. Zero never.
  final double chaseRadius;

  /// How near a ship flying at this drone has to be for it to sidestep.
  /// Zero never.
  final double dodgeRadius;

  /// Where the ship is flying this step, on the ground plane; its length is
  /// the ship's speed. Read fresh every step: a captured vector would freeze
  /// the heading the ship had when the level began.
  final Vector3 Function()? shipHeading;

  /// Which end this drone is currently walking towards.
  bool _towardTo = true;

  @override
  void act(Mind it) {
    final position = it.actor.body?.position;
    if (position == null) return;

    final toShip = Vector3(it.toFocus.x, 0.0, it.toFocus.z);
    final distance = toShip.length;

    final heading = shipHeading?.call();
    if (dodgeRadius > 0.0 &&
        heading != null &&
        heading.length2 > 0.01 &&
        distance > 1e-6 &&
        distance < dodgeRadius) {
      final along = heading.normalized();
      // From the ship to this drone: the ship is flying at it when that
      // points the way the ship is going.
      final fromShip = -toShip / distance;
      if (along.dot(fromShip) > 0.6) {
        final side = Vector3(-along.z, 0.0, along.x);
        it.steer(side.dot(fromShip) < 0.0 ? -side : side);
        return;
      }
    }

    if (chaseRadius > 0.0 && distance > 1e-6 && distance < chaseRadius) {
      it.steer(toShip / distance);
      return;
    }

    if ((position - (_towardTo ? to : from)).length < 0.5) {
      _towardTo = !_towardTo;
    }
    it.steerTowards(_towardTo ? to : from);
  }
}
