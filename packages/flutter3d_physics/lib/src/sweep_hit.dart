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
typedef ContactFilter = bool Function(Collider other, Vector3 normal);

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
