/// The engine's rendering core, with no Flutter SDK behind it.
///
/// **mcp-03n's own split.** `flutter3d` named Flutter in five files out of
/// eighty-nine, all in `engine/assets/`, for one of three reasons:
/// `rootBundle` to read the asset bundle, `kIsWeb` to skip a background
/// isolate the web does not have, and `dart:ui` to decode a PNG or JPEG. The
/// other eighty-four already resolved without it and simply lived in a
/// package that declared the SDK anyway — a modeller's document layer, the
/// tool an agent starts with `dart run`, and a service checking an uploaded
/// asset all want a `Renderer` that draws a frame with none of that behind
/// it.
///
/// **Two libraries sit beside this one, and this one exports both.**
/// `package:flutter3d_core/geometry.dart` is the mesh vocabulary —
/// `MeshData`, `VertexLayout`, shapes, tangents, morph targets, `Ray` — and
/// `package:flutter3d_core/formats.dart` is what a model arrives in and leaves
/// in — `ModelDocument`, the glTF/OBJ/STL/`.f3d`/USDZ readers and writers, the
/// FBX refusal, the image and KTX2 codecs. They were two packages of their own
/// once, for callers that wanted a mesh or a `.glb` with no renderer; a plain
/// Dart package costs such a caller nothing it does not import, so a caller
/// that wants only one of them imports only that library.
///
/// `flutter3d` re-exports this package whole and stays the thin shell three
/// things could not leave: `BundleAssetSource` (names `rootBundle`),
/// `assetUriResolver` (the same), and `defaultImageDecoder` (names
/// `dart:ui`) — plus `ModelAsset` and `bindMaterial`/`loadMaterial`, which
/// default to that decoder and stayed beside it so every existing caller of
/// either keeps compiling unchanged. A `dart run` caller with no Flutter SDK
/// reaches the same `uploadEncodedImage` this package exports directly,
/// handing it a decoder of its own.
library;

// The graphics vocabulary and this package's own two libraries, re-exported
// because this package's API is written in their words — a `RenderNode` is
// handed a `GraphicsDevice`, a `MeshNode` holds a `MeshData` — and a caller
// should not have to add an import to spell the type of something this
// package handed them. The formats library's `Ktx2Texture` is hidden: the
// engine's own, below, carries a `TextureFormat` rather than a raw `vkFormat`.
export 'package:flutter3d_hardware/flutter3d_hardware.dart';

export 'formats.dart' hide Ktx2Texture;
export 'geometry.dart';
// Animation: clips, tracks, sampling, playback. A clip, a track and the mask
// a layer is filtered through are the formats library's, because a clip is
// something a `.glb` carries and a program that reads one has no scene to
// play it in; what is here is what applies a pose.
export 'src/engine/animation/animation.dart';
export 'src/engine/animation/animation_player.dart';
export 'src/engine/animation/animation_target.dart';
export 'src/engine/animation/baked_poses.dart';
export 'src/engine/animation/inverse_kinematics.dart';
export 'src/engine/animation/pose.dart';
export 'src/engine/animation/skin_blend.dart';
// Assets: the isolate loader, the `dart:io` asset source, the file-relative
// glTF resolver, the KTX2 reader with its HAL formats, and
// `uploadEncodedImage` behind an injected [ImageDecoder]. Not here:
// `ModelAsset`, `bindMaterial`/`loadMaterial` and the two Flutter-named
// sources/resolvers — see this library's own doc comment for why.
export 'src/engine/assets/asset_source.dart';
export 'src/engine/assets/gltf_resolvers.dart';
export 'src/engine/assets/image_decoder.dart';
export 'src/engine/assets/ktx2/ktx2.dart';
export 'src/engine/assets/model_loader.dart';
export 'src/engine/assets/model_part.dart';
export 'src/engine/assets/model_writer.dart';
export 'src/engine/assets/resource_cache.dart';
export 'src/engine/assets/texture_upload.dart';
// `device_mesh.dart` holds the two types that have met a device —
// `DeviceMesh` and its buffers — and named `flutter3d_hardware` already, so
// nothing about it is more Flutter-shaped for living here than the render
// graph is.
export 'src/engine/geometry/device_mesh.dart';
// Rendering.
export 'src/engine/render/adaptive_scale.dart';
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
export 'src/engine/render/pass_contribution.dart';
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
export 'src/engine/scene/free_look.dart';
export 'src/engine/scene/instanced_mesh_node.dart';
export 'src/engine/scene/light_buffer.dart';
export 'src/engine/scene/light_node.dart';
export 'src/engine/scene/lod_group.dart';
export 'src/engine/scene/mesh_node.dart';
export 'src/engine/scene/morph_state.dart';
export 'src/engine/scene/orbit_controller.dart';
export 'src/engine/scene/posed_mesh.dart';
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
