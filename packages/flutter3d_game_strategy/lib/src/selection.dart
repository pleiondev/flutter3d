/// Which units a player meant, given where they pointed.
///
/// **The ray arrives, it is not made here.** Turning a pointer into a world ray
/// is camera arithmetic, and the engine already does it —
/// `Raycaster.setFromNdc` unprojects the near and far points of an NDC column,
/// which is the construction that works for an orthographic camera too. That
/// lives in `flutter3d`, which this package deliberately does not depend on, so
/// the application does the unprojecting and hands the result down as an origin
/// and a direction. The same seam every genre uses for input, and it is what
/// keeps a selection testable with no camera and no device.
///
/// **Units are spheres to a ray, not colliders.** They are records of numbers
/// rather than bodies — there is nothing in the collision world to hit — so the
/// test here is the ray against each unit's radius. That is also the only test
/// that can be right: an instanced batch is picked as one box by the engine's
/// own account, so the picking pass can say *that a crowd was clicked* and
/// never *which member of it*.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'unit.dart';

/// Finds units by where a player pointed.
final class Selection {
  /// Reads from [units], which stays the caller's list.
  const Selection(this.units);

  /// The crowd to search, in the order the simulation steps it.
  final List<Unit> units;

  /// The unit a ray hits first, or null for a ray that hits none.
  ///
  /// Nearest along the ray rather than nearest to the camera, which is the same
  /// thing for a ray that starts at the eye and the right thing for one that
  /// does not — an orthographic camera's rays all start on a plane in front of
  /// it.
  ///
  /// [reach] bounds the search so that a click on empty ground stops at the far
  /// edge of the map rather than walking the crowd twice.
  Unit? unitAt(Vector3 origin, Vector3 direction, {double reach = 1000.0}) {
    Unit? nearest;
    var nearestAt = reach;

    for (final Unit unit in units) {
      // The classic ray-sphere test, written out: the vector to the centre,
      // its projection along the ray, and what is left over across it.
      final double ox = unit.position.x - origin.x;
      final double oy = unit.position.y + unit.radius - origin.y;
      final double oz = unit.position.z - origin.z;
      final double along =
          ox * direction.x + oy * direction.y + oz * direction.z;
      if (along < 0.0 || along > nearestAt) continue;

      final double acrossSquared = ox * ox + oy * oy + oz * oz - along * along;
      final double radius = unit.radius;
      if (acrossSquared > radius * radius) continue;

      // Where the ray enters the sphere, which is nearer than its centre and is
      // what "first" has to mean when two units overlap.
      final double half = math.sqrt(radius * radius - acrossSquared);
      final double entry = along - half;
      if (entry < 0.0 || entry > nearestAt) continue;

      nearest = unit;
      nearestAt = entry;
    }
    return nearest;
  }

  /// Every unit standing inside a rectangle on the ground.
  ///
  /// **A rectangle in the world, not on the screen.** A drag select is a
  /// frustum, and testing against one would put the camera's projection inside
  /// the simulation — where it would decide who is selected and thereby make a
  /// run depend on where somebody was looking. The application projects its
  /// rectangle onto the ground and passes the corners; for a camera that looks
  /// down at a map the two agree, and where they do not, the one that replays
  /// is this one.
  ///
  /// The corners may arrive in any order, because a drag that started at the
  /// bottom right is still a rectangle.
  List<Unit> unitsWithin(Vector3 corner, Vector3 opposite) {
    final double minX = math.min(corner.x, opposite.x);
    final double maxX = math.max(corner.x, opposite.x);
    final double minZ = math.min(corner.z, opposite.z);
    final double maxZ = math.max(corner.z, opposite.z);

    return <Unit>[
      for (final Unit unit in units)
        if (unit.position.x >= minX &&
            unit.position.x <= maxX &&
            unit.position.z >= minZ &&
            unit.position.z <= maxZ)
          unit,
    ];
  }
}
