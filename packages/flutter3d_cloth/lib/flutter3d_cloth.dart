/// An XPBD cloth solver, standing alone the way `flutter3d_physics` does.
///
/// **No Flutter, no renderer, no scene graph.** A [ClothMesh] is a grid of
/// particles and the constraints between them; [stepCloth] advances one by a
/// fixed `dt`, with gravity, wind, damping and pins baked into the same
/// per-particle inverse-mass mechanism `flutter3d_physics` already uses for
/// an immovable body. Collision is one function, [pushOutsideObstacle],
/// against that package's own [CollisionShape] — this package generates no
/// shapes of its own, only reacts to ones already built.
///
/// ## Why XPBD, not a spring-mass system
///
/// A spring-mass cloth needs a stiff spring to look inextensible and a stiff
/// spring needs a tiny timestep to stay stable — the two pull against each
/// other, and a cloth stiff enough not to sag under its own weight explodes
/// at any timestep large enough to run in real time. Position-based dynamics
/// sidesteps the spring entirely: a constraint moves particles directly
/// towards satisfying it, which cannot diverge the way an unstable spring
/// force can. XPBD adds back a physically meaningful compliance (so a
/// constraint's own apparent stiffness does not silently change with the
/// substep count, which plain PBD's iteration-count-as-stiffness trick
/// always did) without giving up that stability.
library;

export 'package:flutter3d_physics/flutter3d_physics.dart' show CollisionShape;

export 'src/cloth_collision.dart';
export 'src/cloth_mesh.dart';
export 'src/cloth_settings.dart';
export 'src/xpbd_solver.dart';
