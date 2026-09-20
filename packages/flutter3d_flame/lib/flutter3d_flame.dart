/// A bridge to the Flame 2D game engine.
///
/// Flame draws its own layer, flutter3d draws its own, and this package
/// keeps the two reconciled: transforms and lifecycle
/// ([Flutter3dFlameWidget], [BridgePlane], [Object3dComponent]), the actor
/// system ([ActorComponent], [ActorSystemComponent]), physics
/// ([RigidBodyComponent], [CollisionBridge]), input ([FlameInputBridge]),
/// and camera ([CameraSyncController]). See `apps/flutter3d_showcase`'s
/// `flame` pages for one mechanism per page.
library;

export 'src/camera/camera_sync_controller.dart';
export 'src/ecs/actor_component.dart';
export 'src/ecs/actor_system_component.dart';
export 'src/host/bridge_clock.dart';
export 'src/host/flutter3d_flame_widget.dart';
export 'src/host/transparent_flame_game.dart';
export 'src/input/flame_input_bridge.dart';
export 'src/physics/collision_bridge.dart';
export 'src/physics/rigid_body_component.dart';
export 'src/transform/object3d_component.dart';
export 'src/transform/plane.dart';
