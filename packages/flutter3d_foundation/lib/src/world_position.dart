/// A place in the world, in double precision.
///
/// See `docs/CONTRACTS.md` for the frame every flutter3d coordinate is in.
library;

import 'dart:math' as math;

/// A point in world space: metres, Y up, a right-handed frame, in double
/// precision.
///
/// **Why a type of our own, and why doubles.** `vector_math`'s `Vector3` is
/// float32, which keeps about seven significant digits: a millimetre at ten
/// kilometres from the origin is already lost. A world position is the one
/// quantity that grows with the level, so it is held as three doubles, and
/// everything that does not grow — a mesh's local vertices, a direction, a
/// velocity, what goes into a GPU buffer — stays float32. The crossing is
/// explicit: [relativeTo] gives the offset from an origin (the camera, a
/// chunk's corner) in doubles, and `toVector3Relative` beside it turns that into a
/// `Vector3` and back, so the precision is spent where it is needed and a
/// caller can see where it is dropped.
///
/// Immutable, so a position can be published by the simulation and read by
/// the view without either copying it.
final class WorldPosition {
  /// The point [x], [y], [z] metres from the world origin.
  const WorldPosition(this.x, this.y, this.z);

  /// The world origin, which a caller uses as the default origin of a
  /// conversion.
  static const WorldPosition origin = WorldPosition(0, 0, 0);

  /// Metres along the world X axis.
  final double x;

  /// Metres along the world Y axis, which is up.
  final double y;

  /// Metres along the world Z axis. With X right and Y up, positive Z points
  /// towards a viewer looking down negative Z: the frame is right-handed.
  final double z;

  /// This point moved by [dx], [dy], [dz] metres, for a caller placing
  /// something next to something else.
  WorldPosition translated(double dx, double dy, double dz) =>
      WorldPosition(x + dx, y + dy, z + dz);

  /// The offset from [origin] to this point, in metres and still in double
  /// precision.
  ///
  /// This is the step before a caller narrows to float32: subtract in doubles
  /// first, then round the (small) difference, and the rounding costs
  /// micrometres instead of centimetres.
  ({double x, double y, double z}) relativeTo(WorldPosition origin) =>
      (x: x - origin.x, y: y - origin.y, z: z - origin.z);

  /// The straight-line distance to [other], in metres, for a caller asking
  /// how far apart two things are.
  double distanceTo(WorldPosition other) => math.sqrt(distanceSquaredTo(other));

  /// The square of [distanceTo], for a caller comparing distances who does
  /// not need the root.
  double distanceSquaredTo(WorldPosition other) {
    final dx = x - other.x;
    final dy = y - other.y;
    final dz = z - other.z;
    return dx * dx + dy * dy + dz * dz;
  }

  /// Whether every coordinate is a finite number, for a caller checking a
  /// position read from a file or the network before trusting it.
  bool get isFinite => x.isFinite && y.isFinite && z.isFinite;

  /// The point a fraction [t] of the way from [a] to [b]; [t] outside 0..1
  /// extrapolates. For a caller interpolating between two published states.
  static WorldPosition lerp(WorldPosition a, WorldPosition b, double t) =>
      WorldPosition(
        a.x + (b.x - a.x) * t,
        a.y + (b.y - a.y) * t,
        a.z + (b.z - a.z) * t,
      );

  @override
  bool operator ==(Object other) =>
      other is WorldPosition && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => 'WorldPosition($x, $y, $z)';
}
