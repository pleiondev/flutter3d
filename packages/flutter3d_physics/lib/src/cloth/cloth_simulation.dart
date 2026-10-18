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
  /// A simulation; a subclass gives its [mesh] and its [step].
  const ClothSimulation();

  /// The sheet this steps, in place.
  ClothMesh get mesh;

  /// Advances [mesh] by the step's [ClothStep.dt] seconds as its settings
  /// say, against its obstacles where they stand now: what [stepCloth]
  /// does.
  void step(ClothStep step);

  /// Lets go of what the backend holds for [mesh]. The mesh itself stays
  /// as the last step left it. Nothing, by default.
  void dispose() {}
}

/// The reference: [stepCloth] on [mesh], nothing held besides.
final class DartCloth extends ClothSimulation {
  /// The reference simulation of [mesh], stepping it in place.
  DartCloth(this.mesh);

  @override
  final ClothMesh mesh;

  @override
  void step(ClothStep step) =>
      stepCloth(mesh, step.settings, step.dt, obstacles: step.obstacles);

  /// Nothing: the reference keeps nothing but the mesh.
  @override
  void dispose() {}
}

/// What [ClothSimulation.step] is handed: the settings, the step's length
/// in seconds and the obstacles where they stand now.
///
/// **One object, so a minor can hand a simulation more** — a wind, a
/// moving frame — without breaking one written against 1.0.
/// **Reusable**: a sheet stepped every frame keeps one and sets it before
/// the call; a simulation reads it during [ClothSimulation.step] and does
/// not keep it.
final class ClothStep {
  /// A step of [dt] seconds, nought unless given, with the default
  /// settings and no obstacles unless given.
  ClothStep({
    this.settings = const ClothSettings(),
    this.dt = 0.0,
    this.obstacles = const <ClothObstacle>[],
  });

  /// How the sheet behaves.
  ClothSettings settings;

  /// The step, in seconds.
  double dt;

  /// What it collides with, where it stands now.
  List<ClothObstacle> obstacles;
}
