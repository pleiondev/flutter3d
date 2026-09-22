/// An object's own transform, composed out through every ancestor —
/// `anim-29`'s own missing piece for `SetRestPose`/`MirrorJoints`, and
/// anything else in this package that ends up needing a joint's actual
/// position rather than its transform relative to whatever it happens to
/// be parented under.
library;

import 'package:vector_math/vector_math.dart';

import 'project.dart';

/// The world transform of the object [id] names — its own
/// [ModelObject.transform], composed with its parent's, and so on out to
/// whichever ancestor has none.
///
/// Identity for an object that does not exist, the same answer an object
/// with no parent at all gives: there is nothing further out to compose
/// with either way.
///
/// **Cycle-protected, not cycle-free.** `SetParent`'s own check refuses a
/// parent assignment that would ring the hierarchy, so a real project
/// never has one — but this reads whatever [project] actually holds, and a
/// caller that built one by hand (a test, a fixture) is not bound by that
/// check. A visited set stops the walk rather than looping forever; the
/// answer past that point is whatever had been composed so far, not a
/// claim about what the cycle "really" means, since a ring has no root to
/// measure from.
///
/// **[rotationOverrides], for a caller that has a rotation `anim-15`'s own
/// `IkConstraint` needs but [project] does not carry.** A joint's animated
/// rotation lives in a clip, not in [ModelObject.transform], so a solve run
/// at a particular time needs this hierarchy walk without needing a live
/// scene to ask for it: the override replaces one ancestor's own rotation
/// component for this call only, keeping its translation and scale exactly
/// as [project] has them.
Matrix4 worldTransformOf(
  ModelProject project,
  int id, {
  Map<int, Quaternion>? rotationOverrides,
}) {
  final chain = <Matrix4>[];
  final visited = <int>{};
  var current = project[id];
  while (current != null && visited.add(current.id)) {
    final override = rotationOverrides?[current.id];
    chain.add(
      override == null
          ? current.transform
          : _withRotation(current.transform, override),
    );
    current = current.parent == null ? null : project[current.parent!];
  }
  // Steps, not `Matrix4 * Matrix4`: that operator is declared to return
  // `dynamic` in vector_math, and a chain of them is a chain of dynamic
  // calls — see `command.dart`'s own `_sandwiched` for the same reasoning.
  final world = Matrix4.identity();
  for (final transform in chain.reversed) {
    world.multiply(transform);
  }
  return world;
}

/// [base], with its own rotation component replaced by [rotation] — its
/// translation and scale survive the round trip through [Matrix4.decompose]
/// untouched.
Matrix4 _withRotation(Matrix4 base, Quaternion rotation) {
  final translation = Vector3.zero();
  final currentRotation = Quaternion.identity();
  final scale = Vector3.zero();
  base.decompose(translation, currentRotation, scale);
  return Matrix4.compose(translation, rotation, scale);
}
