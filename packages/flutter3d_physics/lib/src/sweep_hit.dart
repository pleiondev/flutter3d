import 'package:vector_math/vector_math.dart';

import 'collider.dart';

/// Whether a contact counts, asked of the collider and the way it faces.
///
/// The mechanism behind a one-way platform, a phase state, a floor that only
/// some bodies fall through — and the engine knows none of those words. It
/// takes the *normal*, which is what separates this from [Layers]: a mask can
/// only skip a whole collider, and a platform you may pass upwards through but
/// must stand on is one collider whose top face counts and whose other five do
/// not.
///
/// [normal] points from the surface towards the body, is axis-aligned like
/// every normal here, and is **scratch**: read it, do not keep it.
///
/// Called from inside the sweep loop, which is the hottest loop in a game, so
/// the argument is a function rather than an object with a method and the
/// null case costs one comparison.
typedef ContactFilter = bool Function(SweptContact contact);

/// What a [ContactFilter] is told about the contact it is judging.
///
/// **One object rather than two parameters, so this can grow.** A function type
/// is frozen the day it is published: widening
/// `bool Function(Collider, Vector3)` to pass the contact point, or how far
/// along the sweep it happened, breaks every filter anybody has written.
/// Adding a field here does not.
///
/// **Reused between calls, never held**, which is the same rule [SweepHit]
/// keeps and for the same reason: this is judged from inside the sweep loop,
/// several times a step, sixty times a second, and a fresh object per contact
/// would be an allocation on the hottest path in a game. One instance per
/// world, its fields rewritten before each call. [normal] is scratch inside
/// scratch — read it, do not keep it. `tool/filter_cost.dart` is what says
/// this costs nothing, and it is run when this changes.
final class SweptContact {
  SweptContact();

  /// What was touched.
  ///
  /// Nullable behind a non-null getter rather than `late`, and that is a
  /// measurement rather than a style: a `late` field carries an
  /// is-it-initialised check on **every read**, and this is read once or twice
  /// per contact in the sweep loop. `tool/filter_cost.dart` put the two shapes
  /// a percent and a half apart.
  Collider get other => _other!;
  Collider? _other;

  /// Points from the surface towards the body, and is axis-aligned like every
  /// normal here. Scratch inside scratch: read it, do not keep it.
  final Vector3 normal = Vector3.zero();

  /// Points this at one contact. Called by the world, not by a filter.
  void set(Collider other, Vector3 normal) {
    _other = other;
    this.normal.setFrom(normal);
  }
}

/// Where a swept shape first touched something.
///
/// Reused between queries rather than returned fresh: the character controller
/// runs several sweeps per step, sixty times a second, and an allocation here
/// is an allocation on the hottest path in the game.
final class SweepHit {
  /// Fraction of the requested motion completed before contact, in `[0, 1]`.
  /// One means nothing was in the way.
  double fraction = 1.0;

  /// Surface normal at the contact: one of the faces the shape offered, and so
  /// axis-aligned for as long as every shape offers its bounding box.
  final Vector3 normal = Vector3.zero();

  Collider? collider;

  bool get hit => fraction < 1.0;

  void reset() {
    fraction = 1.0;
    normal.setZero();
    collider = null;
  }
}
