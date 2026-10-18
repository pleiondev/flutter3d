/// The crossings between the engine's foundation types and `vector_math`.
///
/// Beside [WorldPosition] and [LinearColor] in the foundation, so the
/// crossing lives with the types it crosses: every package that works in
/// `vector_math` and speaks a world position or a colour has both from one
/// import. They lived in `flutter3d_physics` until 1.0.0-rc.1, when the
/// foundation types were in a package with no dependencies at all.
///
/// **The narrowing is the point of the API.** A world position is three
/// doubles and a `Vector3` is three float32s, so a conversion that dropped
/// precision silently would undo what [WorldPosition] is for. Each crossing
/// here names its origin: subtract in doubles first, narrow the small
/// difference second.
library;

import 'package:vector_math/vector_math.dart';

import 'linear_color.dart';
import 'world_position.dart';

/// A [WorldPosition] narrowed to float32, relative to an origin.
extension WorldPositionVector on WorldPosition {
  /// The offset from [origin] to this point as a float32 `Vector3`, for a
  /// caller handing a position to the view, a GPU buffer or a physics shape
  /// that works in a local frame.
  ///
  /// Pass the camera's position, or the corner of the chunk the work happens
  /// in, as [origin]: the difference is computed in doubles and only then
  /// rounded, so the error is relative to the distance from [origin], not to
  /// the distance from the world's origin.
  Vector3 toVector3Relative(WorldPosition origin) {
    final offset = relativeTo(origin);
    return Vector3(offset.x, offset.y, offset.z);
  }
}

/// A float32 `Vector3` read back into world space, or as a colour.
extension Vector3Foundation on Vector3 {
  /// This vector taken as an offset from [origin], widened to a
  /// [WorldPosition]: the inverse of [WorldPositionVector.toVector3Relative],
  /// for a caller bringing a local result (a hit point, a spawned body's
  /// position) back into the world.
  WorldPosition toWorldPosition({
    WorldPosition origin = WorldPosition.origin,
  }) => origin.translated(x, y, z);

  /// This vector's components as the red, green and blue of a
  /// [LinearColor], for a caller holding a colour in a `Vector3`. The values
  /// are taken as linear; one holding sRGB values wants
  /// [LinearColor.fromSrgb] instead.
  LinearColor toLinearColor([double alpha = 1]) => LinearColor(x, y, z, alpha);
}

/// A float32 `Vector4` read as a colour.
extension Vector4Foundation on Vector4 {
  /// This vector's components as a linear [LinearColor], `w` as alpha, for a
  /// caller holding a colour in a `Vector4` (a clear colour, a uniform).
  LinearColor toLinearColor() => LinearColor(x, y, z, w);
}

/// A [LinearColor] in the shapes `vector_math` and a GPU buffer take.
extension LinearColorVector on LinearColor {
  /// Red, green and blue as a `Vector3`, for a caller filling a uniform that
  /// has no alpha.
  Vector3 toVector3() => Vector3(r, g, b);

  /// Red, green, blue and alpha as a `Vector4`, for a caller filling a
  /// uniform or a clear colour.
  Vector4 toVector4() => Vector4(r, g, b, a);
}
