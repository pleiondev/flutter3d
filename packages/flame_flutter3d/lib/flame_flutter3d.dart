/// A bridge to the Flame 2D game engine.
///
/// Flame draws its own layer, flutter3d draws its own, and this package
/// keeps the two reconciled: transforms and lifecycle
/// ([Flutter3dFlameWidget], [BridgePlane], [Object3dComponent]), the actor
/// system ([ActorComponent], [ActorSystemComponent]), physics
/// ([RigidBodyComponent], [PhysicsStepComponent], [CollisionBridge]), input
/// ([FlameInputBridge]) and camera ([CameraSyncController],
/// [CameraSyncComponent], [ChaseCamera], [BridgeProjector]) and an endless
/// world built piece by piece ([ChunkStreamer]). See
/// `apps/flutter3d_showcase`'s `flame` pages for one mechanism per page.
library;

export 'src/animation/model_animation_component.dart';
export 'src/camera/camera_sync_component.dart';
export 'src/camera/camera_sync_controller.dart';
export 'src/camera/chase_camera.dart';
export 'src/camera/projected_viewfinder.dart';
export 'src/debug/hitboxes3d.dart';
export 'src/ecs/actor_component.dart';
export 'src/ecs/actor_system_component.dart';
export 'src/host/bridge_clock.dart';
export 'src/host/bridge_priority.dart';
export 'src/host/flutter3d_flame_widget.dart';
export 'src/host/has_fixed_step.dart';
export 'src/host/has_flutter3d.dart';
export 'src/host/transparent_flame_game.dart';
export 'src/input/flame_input_bridge.dart';
export 'src/input/taps3d.dart';
export 'src/particles/particles3d_component.dart';
export 'src/physics/collider_registry.dart';
export 'src/physics/collision_bridge.dart';
export 'src/physics/physics_step_component.dart';
export 'src/physics/rigid_body_component.dart';
export 'src/transform/instanced_object3d_component.dart';
export 'src/transform/object3d_component.dart';
export 'src/transform/plane.dart';
export 'src/transform/projector.dart';
export 'src/world/chunk_streamer.dart';
