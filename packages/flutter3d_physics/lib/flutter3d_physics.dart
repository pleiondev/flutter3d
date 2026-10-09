/// Collision, character movement, cloth and liquids, with nothing above them.
///
/// Shapes that overlap exactly, a broadphase over a uniform grid, sweeps and
/// rays that do not tunnel, and a controller that walks, jumps, climbs a step
/// and rides a lift. Nothing here knows what a monster is, what a level is, or
/// how a frame is drawn.
///
/// **`src/cloth/` was its own package once** — an XPBD solver reacting to
/// this package's own [CollisionShape]s and depending on nothing else, which
/// made "a package of its own" the only reason it stayed apart. It moved
/// here rather than the other way round because collision is the older,
/// larger half and cloth is the one thing that only ever pushed against it.
///
/// **Plain Dart.** No Flutter and no `flutter3d`, so the whole of it runs under
/// `dart test` on the VM. That is not tidiness: the failures this code has are
/// the ones that happen once in a thousand steps — a body that ends up inside
/// geometry, a sweep that passes through a wall at a high speed, a platform
/// that stops carrying its passenger — and finding those means running
/// thousands of steps in a loop, which is possible exactly because none of it
/// needs a device.
///
/// ## Layers are numbers here, and names somewhere else
///
/// A collider carries a `layer` and a `mask`, and two of them meet when each is
/// in the other's mask. Which bit means what is a game's business: this package
/// shipped as part of one for a while and its layer list named `monster`,
/// `pickup` and `projectile`, which is exactly the knowledge a collision world
/// must not have. [Layers.all] is the only constant left, because "every bit"
/// means the same thing in every game.
///
/// ## What is not here
///
/// `WorldPosition`, the crossings between it and `vector_math`
/// (`toVector3Relative`, `toWorldPosition`) and `Portable` are
/// `flutter3d_foundation`'s, the package under every other one. They were
/// exported from here during the 1.0 work; a file that named them through
/// this library imports the foundation.
///
/// What a world and its bodies are made of — `WorldProperties`, the
/// material catalogue, the standard world and the constants — is
/// `flutter3d_matter`'s, and is not re-exported: a file that names it
/// depends on that package.
library;

export 'src/character_controller.dart';
export 'src/character_mover.dart';
export 'src/cloth/cloth_collision.dart';
export 'src/cloth/cloth_mesh.dart';
export 'src/cloth/cloth_settings.dart';
export 'src/cloth/cloth_simulation.dart';
export 'src/cloth/xpbd_solver.dart';
export 'src/collider.dart';
export 'src/collision_shape.dart';
export 'src/collision_world.dart';
export 'src/contact.dart';
export 'src/dynamics.dart';
export 'src/fluid/buoyancy.dart' hide pushBodiesInDart;
export 'src/fluid/capillary.dart';
export 'src/fluid/fluid_medium.dart';
export 'src/fluid/fluid_solver.dart';
export 'src/fluid/fluid_world.dart';
export 'src/fluid/free_surface.dart' hide ringModesInDart;
export 'src/fluid/jet.dart' hide flyParcelsInDart;
export 'src/fluid/liquid_body.dart';
export 'src/fluid/liquid_layer.dart';
export 'src/fluid/outflow.dart';
export 'src/fluid/particle_fluid.dart' hide moveParticlesInDart;
export 'src/fluid/pipe.dart' hide flowPipesInDart;
export 'src/fluid/vessel_shape.dart';
export 'src/human_body.dart';
export 'src/inertia.dart';
export 'src/physics_backend.dart';
export 'src/push.dart';
export 'src/rigid_body.dart';
export 'src/rigid_dynamics.dart';
export 'src/snapshot.dart';
export 'src/spatial_grid.dart';
export 'src/tolerances.dart';
export 'src/world_rays.dart';
