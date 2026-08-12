/// A 3D engine, written against a graphics vocabulary rather than a graphics
/// API.
///
/// Everything a consumer needs is exported here. The layout behind it is not
/// arbitrary and is worth knowing before reaching past this file:
///
/// - **This package names no graphics API.** It depends on `flutter3d_graphics` and
///   nothing below it, so an application chooses a backend — `flutter3d_impeller`
///   today — and hands it to `Renderer.create`. That is checked, not intended:
///   `test/backend_is_contained_test.dart`.
/// - `geometry`, `scene`, `assets` and `render/key_sort` need no device at all,
///   which is what lets bounds, culling, framing, picking, decoding and sorting
///   be unit tested without one.
///
/// The shader bundle is still an asset of *this* package, and that is a known
/// wrinkle rather than a decision: it is `impellerc` output, so it belongs with
/// the backend that can read it. The GLSL it is built from is shared. Moving it
/// is a question about where shader sources live, which is worth answering on
/// its own rather than as a side effect of the package split.
/// `packages/flutter3d/tool/build_shaders.sh` builds it, and it has to be
/// rebuilt after every Flutter SDK change.
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
export 'src/engine/assets/texture_upload.dart';

// Geometry: CPU-side meshes and the shapes that generate them.
export 'src/engine/geometry/geometry.dart';

// The graphics vocabulary, re-exported from `flutter3d_graphics`.
//
// Re-exported rather than left for a consumer to depend on separately, because
// these names are all over this package's own API — a `Material` holds
// `SamplerOptions`, a `RenderNode` is handed a `GraphicsDevice` — and a
// consumer should not have to add a dependency to spell the type of something
// this package handed them.
//
// The backend is deliberately **not** re-exported. An application picks one and
// depends on it by name: `flutter3d_impeller` today, a second one beside it later.
// That choice is the one thing that must stay visible in an application's
// pubspec.
export 'package:flutter3d_graphics/flutter3d_graphics.dart';

// Particles: a pooled simulation and the recipes that drive it.
export 'src/engine/particles/particle.dart';
export 'src/engine/particles/particle_affector.dart';
export 'src/engine/particles/particle_emitter.dart';
export 'src/engine/particles/light_emitter.dart';
export 'src/engine/particles/particle_contributor.dart';
export 'src/engine/particles/particle_system.dart';

// Maths that the scene layer needs and that is worth having on its own.
export 'src/engine/math/intersections.dart';

// Rendering.
export 'src/engine/render/debug_draw.dart';
export 'src/engine/render/key_sort.dart';
export 'src/engine/render/lighting_model.dart';
export 'src/engine/render/material.dart';
export 'src/engine/render/procedural_texture.dart';
export 'src/engine/render/render_list.dart';
export 'src/engine/render/render_node.dart';
export 'src/engine/render/parity_scene.dart';
export 'src/engine/render/pass_contributor.dart';
export 'src/engine/render/render_view.dart';
export 'src/engine/render/frame_graph.dart';
export 'src/engine/render/frame_plan.dart';
export 'src/engine/render/frame_resources.dart';
export 'src/engine/render/shadow_slots.dart';
export 'src/engine/render/renderer.dart';
export 'src/engine/render/view_model_node.dart';

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
