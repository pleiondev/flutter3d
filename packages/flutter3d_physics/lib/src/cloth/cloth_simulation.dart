import 'cloth_collision.dart';
import 'cloth_mesh.dart';
import 'cloth_settings.dart';
import 'xpbd_solver.dart';

/// A [ClothMesh] stepped by a world's physics: `backend.cloth(mesh)`, the
/// core where the run is on it and [stepCloth] where it is on the reference.
///
/// **The mesh stays the cloth.** Its positions, velocities and inverse
/// masses are read at the start of every [step] and its positions and
/// velocities written at the end, so code that draws the sheet from
/// [ClothMesh.positions], pins a particle by zeroing its
/// [ClothMesh.invMass] or carries one by writing its position reads and
/// writes the same arrays it did when it called [stepCloth] itself. What
/// the mesh is made of — its constraints, triangles and rest shape — is
/// read once, when the simulation is made.
///
/// The two backends are close, not equal: a sheet stepped on the core is
/// where the reference would put it to within the rounding of single
/// precision and the order the constraints are solved in, and each agrees
/// with itself from run to run.
///
/// **Extended outside this package: an `abstract base class` with defaults**
/// (decision 5 of `tasks/1.0-api-review.md`), so a member added in a minor
/// arrives with a default body and every implementation keeps compiling.
abstract base class ClothSimulation {
  const ClothSimulation();

  /// The sheet this steps, in place.
  ClothMesh get mesh;

  /// Advances [mesh] by [dt] seconds as [settings] say, against
  /// [obstacles] where they stand now: what [stepCloth] does.
  void step(
    ClothSettings settings,
    double dt, {
    List<ClothObstacle> obstacles = const <ClothObstacle>[],
  });

  /// Lets go of what the backend holds for [mesh]. The mesh itself stays
  /// as the last step left it. Nothing, by default.
  void dispose() {}
}

/// The reference: [stepCloth] on [mesh], nothing held besides.
final class DartCloth extends ClothSimulation {
  DartCloth(this.mesh);

  @override
  final ClothMesh mesh;

  @override
  void step(
    ClothSettings settings,
    double dt, {
    List<ClothObstacle> obstacles = const <ClothObstacle>[],
  }) => stepCloth(mesh, settings, dt, obstacles: obstacles);

  /// Nothing: the reference keeps nothing but the mesh.
  @override
  void dispose() {}
}
