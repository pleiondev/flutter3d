/// Collision and character movement, with nothing above them.
///
/// Shapes that overlap exactly, a broadphase over a uniform grid, sweeps and
/// rays that do not tunnel, and a controller that walks, jumps, climbs a step
/// and rides a lift. Nothing here knows what a monster is, what a level is, or
/// how a frame is drawn.
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
library;

export 'src/character_controller.dart';
export 'src/collider.dart';
export 'src/collision_shape.dart';
export 'src/contact.dart';
export 'src/dynamics.dart';
export 'src/rigid_body.dart';
export 'src/collision_world.dart';
export 'src/spatial_grid.dart';
