/// How a kinematic walker shoves the bodies it walks into.
///
/// One rule for every [RigidDynamics]: a crate a character pushes moves the
/// same whichever backend steps it, and only the step after differs.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'collider.dart';
import 'collision_shape.dart';
import 'contact.dart';
import 'rigid_dynamics.dart';
import 'tolerances.dart';

final class Pusher {
  Pusher(this.dynamics);

  final RigidDynamics dynamics;

  final List<Collider> _nearby = <Collider>[];
  final Contact _contact = Contact();
  final Vector3 _scratch = Vector3.zero();

  /// Shoves whatever [by] is walking into, horizontally, at most at the speed
  /// it walks into it, the contact found with [margin] of slack.
  ///
  /// ## Why a character does not push a crate on its own
  ///
  /// A `CharacterController` is kinematic: it sweeps, it slides, and it is
  /// never moved by anything. That is what makes a first-person game feel
  /// solid, and it also means walking into a crate does exactly nothing to the
  /// crate — the sweep stops the player and no momentum goes the other way.
  ///
  /// So the transfer is explicit, and it is a *speed* rather than a force. A
  /// crate is given just enough velocity to move away at the speed the walker
  /// is approaching it, and no more: that is what makes pushing feel like
  /// pushing rather than like a bat. A force proportional to mass would let a
  /// player launch a light crate across the room by brushing it.
  ///
  /// Horizontal only. Walking into a crate must not press it into the floor,
  /// and standing on one must not drive it downwards.
  void push(
    Collider by,
    Vector3 velocity, {
    double strength = 1.0,
    double margin = 0.02,
  }) {
    final speed = math.sqrt(velocity.x * velocity.x + velocity.z * velocity.z);
    if (speed < Nearly.moving) return;

    dynamics.world.overlap(
      _inflated(by.shape, margin),
      by.position,
      _nearby,
      ignore: by,
      includeTriggers: false,
    );
    for (final other in _nearby) {
      final body = dynamics.bodyOf(other);
      if (body == null || !body.isMovable) continue;

      contactBetween(
        body.collider.shape,
        body.position,
        by.shape,
        by.position,
        _contact,
        margin: margin,
      );
      if (!_contact.touching) continue;

      // Which way the crate would go, flattened: the normal points out of the
      // walker, which is exactly the direction to shove.
      _scratch.setValues(_contact.normal.x, 0.0, _contact.normal.z);
      final flat = _scratch.length;
      if (flat < Nearly.moving) continue;
      _scratch.scale(1.0 / flat);

      // Only if the walker is actually heading into it.
      final into = velocity.x * _scratch.x + velocity.z * _scratch.z;
      if (into <= 0.0) continue;

      final already = body.velocity.dot(_scratch);
      final wanted = into * strength;
      if (already >= wanted) continue;
      body.applyImpulse(_scratch * ((wanted - already) / body.inverseMass));
    }
  }

  /// The walker's bounds grown by the margin, for the broadphase.
  CollisionShape _inflated(CollisionShape shape, double margin) {
    final half = shape.boundsHalfExtents;
    return CollisionBox(
      Vector3(half.x + margin, half.y + margin, half.z + margin),
    );
  }
}
