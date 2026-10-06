import '../physics_backend.dart';
import 'cloth_collision.dart';
import 'cloth_mesh.dart';
import 'cloth_settings.dart';
import 'xpbd_solver.dart';

/// A [ClothMesh] stepped by the run's physics: `PhysicsBackend.current
/// .cloth(mesh)`, the core where the run is on it and [stepCloth] where it
/// is on the reference.
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
abstract interface class ClothSimulation {
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
  /// as the last step left it.
  void dispose();
}

/// A backend with a cloth of its own: what [PhysicsBackendCloth.cloth]
/// asks a backend for before it falls back to the reference.
///
/// **An interface beside [PhysicsBackend], not a member of it.** A backend
/// a test writes to count what it was given has no cloth to offer, and
/// should not have to say so.
abstract interface class ClothPhysics {
  /// A simulation of [mesh] on this backend.
  ClothSimulation cloth(ClothMesh mesh);
}

/// Cloth from whatever backend the run is on.
extension PhysicsBackendCloth on PhysicsBackend {
  /// A simulation of [mesh] on this backend if it has a cloth of its own
  /// ([ClothPhysics]), on the reference ([DartCloth]) if not.
  ClothSimulation cloth(ClothMesh mesh) => switch (this) {
    final ClothPhysics own => own.cloth(mesh),
    _ => DartCloth(mesh),
  };
}

/// The reference: [stepCloth] on [mesh], nothing held besides.
final class DartCloth implements ClothSimulation {
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
