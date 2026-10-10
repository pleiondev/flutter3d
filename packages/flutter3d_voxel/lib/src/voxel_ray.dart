import 'package:vector_math/vector_math.dart';

import 'voxel_world.dart';

/// The block a ray met, and the face it came in through.
final class VoxelHit {
  /// The voxel at `(x, y, z)`, entered through the face whose outward
  /// normal is `(normalX, normalY, normalZ)`, [distance] along the ray.
  const VoxelHit({
    required this.x,
    required this.y,
    required this.z,
    required this.normalX,
    required this.normalY,
    required this.normalZ,
    required this.distance,
  });

  /// The block hit.
  final int x, y, z;

  /// The outward normal of the face the ray entered by: one axis, plus or
  /// minus one, or all nought when the ray started inside the block.
  final int normalX, normalY, normalZ;

  /// How far along the (normalised) ray the face is, in metres (a voxel is a
  /// metre).
  final double distance;

  /// The voxel in front of the face — where a block placed against this one
  /// goes.
  ({int x, int y, int z}) get before =>
      (x: x + normalX, y: y + normalY, z: z + normalZ);
}

/// Rays through the grid, voxel by voxel.
extension VoxelRays on VoxelWorld {
  /// The first solid block along the ray from [origin] towards [direction],
  /// no further than [maxDistance], or null.
  ///
  /// **Through the grid rather than through the colliders**: the boxes a
  /// chunk collides as are merged, and a box says where a ray stopped but not
  /// which of its voxels that was — which is the one question picking a block
  /// asks. Amanatides and Woo's walk: from voxel to voxel across whichever
  /// face is nearest along the ray, so no block is stepped over however
  /// shallow the angle.
  VoxelHit? raycast(Vector3 origin, Vector3 direction, double maxDistance) {
    final length = direction.length;
    if (length == 0.0) return null;
    final dir = direction / length;
    final cell = <int>[origin.x.floor(), origin.y.floor(), origin.z.floor()];
    final from = <double>[origin.x, origin.y, origin.z];
    final along = <double>[dir.x, dir.y, dir.z];
    final step = <int>[for (final a in along) a > 0 ? 1 : (a < 0 ? -1 : 0)];
    // How far along the ray each axis's next face is, and how far between
    // two of them.
    final next = <double>[
      for (var i = 0; i < 3; i++)
        along[i] == 0.0
            ? double.infinity
            : ((step[i] > 0 ? cell[i] + 1 : cell[i]) - from[i]) / along[i],
    ];
    final every = <double>[
      for (final a in along) a == 0.0 ? double.infinity : 1.0 / a.abs(),
    ];
    final normal = <int>[0, 0, 0];
    var travelled = 0.0;
    while (travelled <= maxDistance) {
      if (isSolid(cell[0], cell[1], cell[2])) {
        return VoxelHit(
          x: cell[0],
          y: cell[1],
          z: cell[2],
          normalX: normal[0],
          normalY: normal[1],
          normalZ: normal[2],
          distance: travelled,
        );
      }
      final axis = next[0] < next[1]
          ? (next[0] < next[2] ? 0 : 2)
          : (next[1] < next[2] ? 1 : 2);
      travelled = next[axis];
      next[axis] += every[axis];
      cell[axis] += step[axis];
      normal
        ..fillRange(0, 3, 0)
        ..[axis] = -step[axis];
    }
    return null;
  }
}
