/// A 3D engine, written against a graphics vocabulary rather than a graphics
/// API.
///
/// Everything a consumer needs is exported here. The layout behind it is not
/// arbitrary and is worth knowing before reaching past this file:
///
/// - **This package names no graphics API.** It depends on `flutter3d_hardware` and
///   nothing below it, so an application chooses a backend package
///   today — and hands it to `Renderer.create`. That is checked, not intended:
///   `tool/structure.dart`'s "the engine names no backend" rule, which scans
///   this package's `lib/`. The rule named here until now — "the hardware
///   layer names no graphics API" — scans `flutter3d_hardware` and says
///   nothing whatever about this file's claim.
/// - `geometry`, `scene`, `assets` and `render/key_sort` need no device at all,
///   which is what lets bounds, culling, framing, picking, decoding and sorting
///   be unit tested without one.
///
/// The shader bundle is still an asset of *this* package, and that is a known
/// wrinkle rather than a decision: a compiled bundle is one backend's output,
/// so it belongs with
/// the backend that can read it. The GLSL it is built from is shared. Moving it
/// is a question about where shader sources live, which is worth answering on
/// its own rather than as a side effect of the package split.
/// `packages/flutter3d_impeller/tool/build_shaders.sh` builds it — beside the
/// backend that needs it, not beside this package — and it has to be rebuilt
/// after every Flutter SDK change.
library;

// Assets: the formats and the documents they decode into are
// `package:flutter3d_formats` — glTF/GLB, OBJ, the project's own .f3d container
// and its .fmat material, `ModelDocument`, `SurfaceMaterial`, `LightingModel`
// and the synchronous half of loading. Exported whole, so an application that
// imports the engine keeps every name it had.
export 'package:flutter3d_formats/flutter3d_formats.dart';
// Geometry: CPU-side meshes, the shapes that generate them and the ray
// arithmetic that reads one, all of it `package:flutter3d_geometry` since the
// day a program with no Flutter SDK had to be able to say `MeshData`. Exported
// whole, so an application that imports the engine keeps every name it had.
export 'package:flutter3d_geometry/flutter3d_geometry.dart';
// The graphics vocabulary, re-exported from `flutter3d_hardware`.
//
// Re-exported rather than left for a consumer to depend on separately, because
// these names are all over this package's own API — a `Material` holds
// `SamplerOptions`, a `RenderNode` is handed a `GraphicsDevice` — and a
// consumer should not have to add a dependency to spell the type of something
// this package handed them.
//
// The backend is deliberately **not** re-exported. An application picks one and
// depends on one by name; there are three today — `flutter3d_impeller`,
// `flutter3d_webgl` and `flutter3d_cpu` — and room for more.
// That choice is the one thing that must stay visible in an application's
// pubspec.
export 'package:flutter3d_hardware/flutter3d_hardware.dart';

// Animation: clips, tracks, sampling, playback. A clip, a track and the mask a
// layer is filtered through are `flutter3d_formats`, because a clip is
// something a `.glb` carries and a program that reads one has no scene to play
// it in; what is here is what applies a pose.
export 'src/engine/animation/animation.dart';
export 'src/engine/animation/animation_player.dart';
export 'src/engine/animation/animation_target.dart';
export 'src/engine/animation/baked_poses.dart';
// What could not go with them, each because it needs something this package may
// name and that one may not: the isolate loader and the two asset sources
// (Flutter's bundle, and `dart:io`), the bundle resolvers, the KTX2 reader with
// its HAL formats, and everything from `ModelAsset` down that has met a device.
export 'src/engine/assets/gltf_resolvers.dart';
export 'src/engine/assets/ktx2/ktx2.dart';
export 'src/engine/assets/material_loader.dart';
export 'src/engine/assets/model_asset.dart';
export 'src/engine/assets/model_loader.dart';
export 'src/engine/assets/resource_cache.dart';
export 'src/engine/assets/texture_upload.dart';
// `device_mesh.dart` is the rest of that layer by subject matter and stayed
// here, because it holds the two types that have met a device — and a package
// that named `GraphicsDevice` would be a package with Flutter behind it again.
export 'src/engine/geometry/device_mesh.dart';
// Particles are `package:flutter3d_particles` and are named nowhere here.
// The engine defines what a contributor is; what draws through one is not its
// business, which is the whole test of the extension model.

// Rendering.
export 'src/engine/render/debug_draw.dart';
export 'src/engine/render/debug_draw_gizmos.dart';
export 'src/engine/render/empty_frame.dart';
export 'src/engine/render/environment_map.dart';
export 'src/engine/render/frame_graph.dart';
export 'src/engine/render/frame_plan.dart';
export 'src/engine/render/frame_resources.dart';
export 'src/engine/render/key_sort.dart';
export 'src/engine/render/material.dart';
export 'src/engine/render/mesh_overlay.dart';
export 'src/engine/render/pass_contributor.dart';
export 'src/engine/render/probe_faces.dart';
export 'src/engine/render/procedural_texture.dart';
export 'src/engine/render/render_list.dart';
export 'src/engine/render/render_node.dart';
export 'src/engine/render/render_view.dart';
export 'src/engine/render/renderer.dart';
export 'src/engine/render/shadow_slots.dart';
export 'src/engine/render/sky_settings.dart';
export 'src/engine/render/view_model_node.dart';
// The scene graph and everything that walks it.
export 'src/engine/scene/bvh.dart';
export 'src/engine/scene/camera_node.dart';
export 'src/engine/scene/instanced_mesh_node.dart';
export 'src/engine/scene/light_buffer.dart';
export 'src/engine/scene/light_node.dart';
export 'src/engine/scene/lod_group.dart';
export 'src/engine/scene/mesh_node.dart';
export 'src/engine/scene/morph_state.dart';
export 'src/engine/scene/orbit_controller.dart';
export 'src/engine/scene/projection.dart';
export 'src/engine/scene/raycaster.dart';
export 'src/engine/scene/reflection_probe_node.dart';
export 'src/engine/scene/scene.dart';
export 'src/engine/scene/scene_graph.dart';
export 'src/engine/scene/scene_node.dart';
export 'src/engine/scene/scene_spheres.dart';
export 'src/engine/scene/skeleton.dart';
export 'src/engine/scene/sky.dart';
export 'src/engine/scene/sky_gradient.dart';
