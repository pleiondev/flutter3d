/// Scene graph: hierarchy, transforms, cameras and lights.
///
/// The layer depends on `GpuMesh` and `Material` but on no rendering code, so a
/// scene can be built and tested — transform composition, reparenting, bounds,
/// culling inputs — with no GPU present.
library;

export 'bvh.dart';
export 'camera_node.dart';
export 'light_buffer.dart';
export 'light_node.dart';
export 'lod_group.dart';
export 'mesh_node.dart';
export 'raycaster.dart';
export 'scene.dart';
export 'scene_spheres.dart';
export 'scene_node.dart';
export 'orbit_controller.dart';
