/// A 3D engine on Flutter GPU.
///
/// Everything a consumer needs is exported here. The layout behind it is not
/// arbitrary and is worth knowing before reaching past this file:
///
/// - `geometry`, `scene`, `assets` and `render/key_sort` do not import
///   `flutter_gpu`. That is a property held on purpose, because it is what lets
///   bounds, culling, framing, picking, decoding and sorting be unit tested
///   without a device — and it is checked by the console benchmark, which could
///   not compile at all if the rule were broken.
/// - `gpu` and the renderer are the only parts that need a device.
///
/// The shader bundle is an asset of this package, so a consuming application
/// gets it without declaring anything, but it must still be built:
/// `packages/flutter3d/tool/build_shaders.sh`, and again after every Flutter SDK
/// change, because the bundle format is tied to the SDK version.
library;

// Animation: clips, tracks, sampling, playback.
export 'src/engine/animation/animation.dart';
export 'src/engine/animation/animation_clip.dart';
export 'src/engine/animation/animation_player.dart';

// Assets: decoders for glTF/GLB, OBJ and the project's own .f3d container,
// plus loading and caching.
export 'src/engine/assets/asset_resolver.dart';
export 'src/engine/assets/f3d/f3d.dart';
export 'src/engine/assets/gltf/gltf.dart';
export 'src/engine/assets/gltf_resolvers.dart';
export 'src/engine/assets/model_asset.dart';
export 'src/engine/assets/model_document.dart';
export 'src/engine/assets/model_loader.dart';
export 'src/engine/assets/obj/obj.dart';
export 'src/engine/assets/resource_cache.dart';

// Geometry: CPU-side meshes and the shapes that generate them.
export 'src/engine/geometry/geometry.dart';

// GPU resources.
export 'src/engine/gpu/gpu_mesh.dart';
export 'src/engine/gpu/render_target_pool.dart';
export 'src/engine/gpu/texture_upload.dart';

// Maths that the scene layer needs and that is worth having on its own.
export 'src/engine/math/intersections.dart';

// Rendering.
export 'src/engine/render/debug_draw.dart';
export 'src/engine/render/key_sort.dart';
export 'src/engine/render/lighting_model.dart';
export 'src/engine/render/material.dart';
export 'src/engine/render/procedural_texture.dart';
export 'src/engine/render/render_list.dart';
export 'src/engine/render/render_view.dart';
export 'src/engine/render/renderer.dart';

// The scene graph and everything that walks it.
export 'src/engine/scene/bvh.dart';
export 'src/engine/scene/camera_node.dart';
export 'src/engine/scene/light_buffer.dart';
export 'src/engine/scene/light_node.dart';
export 'src/engine/scene/lod_group.dart';
export 'src/engine/scene/mesh_node.dart';
export 'src/engine/scene/orbit_controller.dart';
export 'src/engine/scene/raycaster.dart';
export 'src/engine/scene/scene.dart';
export 'src/engine/scene/scene_graph.dart';
export 'src/engine/scene/scene_node.dart';
export 'src/engine/scene/scene_spheres.dart';
export 'src/engine/scene/skeleton.dart';
