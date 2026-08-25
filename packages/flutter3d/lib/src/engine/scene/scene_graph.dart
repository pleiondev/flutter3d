/// Scene graph: hierarchy, transforms, cameras and lights.
///
/// The layer depends on `MeshGeometry` and `Material` but on no rendering code
/// and no backend, so a scene can be built and tested — transform composition,
/// reparenting, bounds, culling inputs — with no device present. `MeshGeometry`
/// and not a concrete mesh: `CpuMesh` satisfies it, which is what lets a test
/// build a scene without uploading anything.
library;

export 'bvh.dart';
export 'camera_node.dart';
export 'light_buffer.dart';
export 'light_node.dart';
export 'lod_group.dart';
export 'mesh_node.dart';
export 'orbit_controller.dart';
export 'projection.dart';
export 'raycaster.dart';
export 'scene.dart';
export 'scene_node.dart';
export 'scene_spheres.dart';
export 'skeleton.dart';
