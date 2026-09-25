import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_core/geometry.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_shaders/typed_blocks.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../geometry/device_mesh.dart';
import '../scene/camera_node.dart';
import '../scene/instanced_mesh_node.dart';
import '../scene/irradiance_field.dart';
import '../scene/irradiance_gather.dart' show kIrradianceReach;
import '../scene/light_buffer.dart';
import '../scene/light_node.dart';
import '../scene/mesh_node.dart';
import '../scene/morph_state.dart';
import '../scene/occlusion/hi_z_occlusion.dart';
import '../scene/occlusion/occlusion_test.dart';
import '../scene/occlusion/software_occlusion.dart';
import '../scene/projection.dart';
import '../scene/reflection_probe_node.dart';
import '../scene/scene.dart';
import '../scene/scene_node.dart';
import 'composite_mix.dart';
import 'debug_draw.dart';
import 'debug_draw_gizmos.dart';
import 'empty_frame.dart';
import 'engine_tables.dart';
import 'field_pass.dart';
import 'frame_capture.dart';
import 'frame_graph.dart';
import 'frame_history.dart';
import 'frame_plan.dart';
import 'frame_resources.dart';
import 'frame_work_budget.dart';
import 'identity_indices.dart';
import 'light_clusters.dart';
import 'material.dart';
import 'object_id_frame.dart';
import 'pass_contributor.dart';
import 'probe_faces.dart';
import 'procedural_texture.dart';
import 'render_list.dart';
import 'render_node.dart';
import 'render_settings.dart';
import 'render_view.dart';
import 'shadow_slots.dart';
import 'sky_settings.dart';
import 'static_bake_key.dart';

// Settings and results are a public part of this library's surface but not
// of `Renderer`'s own concerns, so they live in their own file. Re-exported
// here rather than added to `flutter3d.dart` directly, so this file keeps
// being the one place that decides what a consumer reaches through.
//
// What `Renderer.captureObjectIds` answers with, for the same reason.
export 'object_id_frame.dart';
export 'render_settings.dart';

part 'renderer_batch.dart';
part 'renderer_contributor_lights.dart';
part 'renderer_fog_pass.dart';
part 'renderer_frame_nodes.dart';
part 'renderer_irradiance_pass.dart';
part 'renderer_light_list.dart';
part 'renderer_mesh_encode.dart';
part 'renderer_pick_pass.dart';
part 'renderer_post_pass.dart';
part 'renderer_probe_pass.dart';
part 'renderer_resources.dart';
part 'renderer_scene_pass.dart';
part 'renderer_shadow_pass.dart';
part 'renderer_sky_pass.dart';
part 'renderer_temporal_pass.dart';
part 'renderer_transparency_pass.dart';
part 'renderer_velocity_pass.dart';
part 'renderer_xray_pass.dart';

const String _kFragInfoBlock = 'FragInfo';

/// The per-draw half of the light list — `gfx-74n`.
const String _kLightListBlock = 'LightListInfo';

const String _kMorphInfoBlock = 'MorphInfo';

/// Texture slots, unlike uniform blocks, are reflected under the variable name.
const String _kAlbedoTextureSlot = 'base_color_texture';

const String _kNormalTextureSlot = 'normal_texture';
const String _kMetallicRoughnessTextureSlot = 'metallic_roughness_texture';

/// The LTC tables — `L7`. Metal-rough only; see `lib/ltc.glsl`.
const String _kLtcTextureSlot = 'ltc_texture';

/// The layered model's coat map and its block — `M1`. See `lib/pbr.glsl`.
const String _kCoatTextureSlot = 'coat_texture';
const String _kSheenTextureSlot = 'sheen_texture';
const String _kOcclusionTextureSlot = 'occlusion_texture';
const String _kEmissiveTextureSlot = 'emissive_texture';
const String _kLightmapTextureSlot = 'lightmap_texture';
const String _kEnvironmentTextureSlot = 'environment_texture';
const String _kShadowTextureSlot = 'shadow_texture';
const String _kPostSourceSlot = 'source_texture';
const String _kSceneTextureSlot = 'scene_texture';
const String _kBloomTextureSlot = 'bloom_texture';
const String _kAoTextureSlot = 'ao_texture';
const String _kLutTextureSlot = 'lut_texture';
const String _kContactShadowTextureSlot = 'contact_shadow_texture';

/// Draws a [Scene] through one or more [RenderView]s.
///
/// **A frame graph, compiled once per frame.** Every pass is a node that
/// declares what it reads and what it writes — the two cube shadow atlases and
/// the cascade, the reflection probes, the scene itself, object ids,
/// screen-space reflections, the exposure meter, ambient occlusion, bloom and
/// the composite — and [FrameGraph] derives the order from those declarations,
/// culls whatever nothing consumes, and hands each surviving pass its targets.
/// Registration order is the version chain: nothing here carries a priority
/// number, which is the whole reason the graph replaced the list of `if`s that
/// came before it.
///
/// **What it does not own is as much of the shape as what it does.** The scene
/// is handed in, the views are handed in, and an application extends the frame
/// rather than editing it: [addNode] registers a pass of its own — in either
/// [FramePhase] — and [addContributor] draws inside the scene's pass. What the
/// renderer does own is the machinery of a frame: a culled and sorted render
/// list, the shadow slot allocator, the render target pool, and the pipeline
/// cache whose size [FrameResult.pipelines] reports so a permutation cannot
/// creep in where a uniform belonged.
///
/// One [GraphicsDevice], injected, is the whole of what it knows about a
/// backend — see [device].
final class Renderer implements RenderServices {
  Renderer._({
    required this.device,
    required this.vertexShader,
    required this.skinnedVertexShader,
    required this.instancedVertexShader,
    required this.lightmappedVertexShader,
    required this.debugLineVertexShader,
    required this.debugLineFragmentShader,
    required this.fullscreenVertexShader,
    required this.bloomThresholdShader,
    required this.bloomDownsampleShader,
    required this.bloomUpsampleShader,
    required this.compositeShader,
    required this.fxaaShader,
    required this.reflectionShader,
    required this.ssaoShader,
    required this.contactShadowShader,
    required this.cameraVelocityShader,
    required this.velocityShader,
    required this.velocityVertexShader,
    required this.velocitySkinnedVertexShader,
    required this.velocityInstancedVertexShader,
    required this.reactiveShader,
    required this.temporalResolveShader,
    required this.temporalAccumulateShader,
    required this.ssaoBlurShader,
    required this.lightShaftsShader,
    required this.volumetricFogShader,
    required this.volumetricFogUpsampleShader,
    required this.depthOfFieldShader,
    required this.velocityTileMaxShader,
    required this.velocityNeighborMaxShader,
    required this.motionBlurShader,
    required this.viewportShadeShader,
    required this.wboitResolveShader,
    required TextureHandle fallbackAlbedo,
    required TextureHandle fallbackNormal,
    required TextureHandle fallbackBlack,
    required this.msaaEnabled,
  }) : targetPool = RenderTargetPool(device),
       // `prefer_initializing_formals` wants `this._fallbackAlbedo` here and
       // Dart will not have it: a named parameter may not be private, so the
       // only way to satisfy the lint is to make the fields public — which is
       // the opposite of what they are for. The two textures are stood in for
       // every material that ships without one, and nothing outside this class
       // has any business reaching them.
       // ignore: prefer_initializing_formals
       _fallbackAlbedo = fallbackAlbedo,
       // ignore: prefer_initializing_formals
       _fallbackNormal = fallbackNormal,
       // ignore: prefer_initializing_formals
       _fallbackBlack = fallbackBlack;

  /// The backend, injected rather than reached for.
  ///
  /// The renderer names no graphics API at all: it holds one of these and hands
  /// the narrower [GraphicsDevice] view of it to every node and contributor. A
  /// second backend is a second implementation of this and nothing else, and a
  /// **fake** one is what makes a node's drawing testable off a device.
  final GraphicsDevice device;

  /// The stages this renderer can find by name: the application's, then the
  /// backend's bundle.
  ///
  /// **This is how a look is added without changing the engine.** A material
  /// names its shader — see [LightingModel.shaderName], whose own docstring says
  /// there is no complete list to have — and the name is resolved here. An
  /// application that compiles a stage of its own and hands the library in gets
  /// that stage found first, and needs no entry in any table of this package's.
  ShaderLibrary get shaders => _shaders;
  late final ShaderLibrary _shaders;

  /// What draws alongside the world.
  ///
  /// A registry rather than a parameter per feature. `render()` grew one for
  /// the weapon view model and another for the particles, and fog, decals and
  /// a debug overlay would each have added a third — a parameter list is a
  /// registry with no ordering and nothing an application can add to.
  /// Things that draw inside the scene's pass.
  final ContributorRegistry contributors = ContributorRegistry();

  /// Things that own a pass of their own.
  final RenderNodeRegistry nodes = RenderNodeRegistry();

  T addContributor<T extends PassContributor>(T c) => contributors.add(c);

  /// Registers a pass of an application's own, in [phase].
  ///
  /// **The phase belongs here rather than only on [nodes].** This is the method
  /// the render-node seam is documented in terms of, and it took no phase — so
  /// the one thing [FramePhase] exists to make sayable could only be said by
  /// reaching past this to `renderer.nodes.add(node, phase: …)`. A caller who
  /// did not know that got the [FramePhase.overlay] default, which is the
  /// arrangement `FramePhase.present` was added because it silently fails:
  /// the pass runs, costs its time, and the composite overwrites it.
  ///
  /// Left off, the phase is the node's own [RenderNode.preferredPhase], as it
  /// is through [RenderNodeRegistry.add]. A default of `overlay` here used to
  /// override that answer, so `FullscreenEffect.present` registered through
  /// this method landed before the composite — the exact failure above.
  T addNode<T extends RenderNode>(T node, {FramePhase? phase}) =>
      nodes.add(node, phase: phase);

  /// Takes a contributor back out, and says whether it was there.
  ///
  /// Nothing here calls it: a game built on this engine adds its passes once and
  /// runs. It is for an application that turns a feature off at run time — an
  /// editor with a checkbox per pass, or a game dropping a post effect on a
  /// machine that cannot afford it — where the alternative is rebuilding the
  /// renderer and losing every resource it holds.
  bool removeContributor(PassContributor c) => contributors.remove(c);

  /// Takes a node back out, and says whether it was there.
  ///
  /// For the same caller as [removeContributor], one node at a time: an editor
  /// deleting the thing that was selected, which nothing in this repository
  /// does because nothing here deletes anything mid-frame.
  bool removeNode(RenderNode node) => nodes.remove(node);

  final ShaderHandle vertexShader;

  /// The skinned vertex stage. A separate shader because joints and weights are
  /// vertex attributes, and the layout is taken from the `in`
  /// declarations — so a skinned mesh cannot share a shader with a static one
  /// however similar the body is.
  final ShaderHandle skinnedVertexShader;

  /// The instanced vertex stage: the standard layout in slot 0 and a
  /// per-instance transform and colour in slot 1. The same varyings and the
  /// same `FrameInfo` as [vertexShader], so every fragment shader and both
  /// shadow passes draw from it unchanged — see `mesh_instanced.vert`.
  final ShaderHandle instancedVertexShader;

  /// The lightmapped vertex stage: the standard layout with the colour read
  /// as the vertex's place in the level's lightmap and the tint held at
  /// white. The same varyings as [vertexShader] plus the coordinate, which
  /// the other three stages leave at zero — see `mesh_lightmapped.vert`.
  final ShaderHandle lightmappedVertexShader;

  /// The debug overlay's own stage pair. Separate from the mesh shaders because
  /// the line buffer has a different vertex layout, and a backend takes the
  /// layout from the shader's `in` declarations.
  final ShaderHandle debugLineVertexShader;
  final ShaderHandle debugLineFragmentShader;

  /// The post-processing stages. All of them share one vertex shader, because a
  /// full-screen pass differs only in its fragment work.
  final ShaderHandle fullscreenVertexShader;
  final ShaderHandle bloomThresholdShader;
  final ShaderHandle bloomDownsampleShader;
  final ShaderHandle bloomUpsampleShader;
  final ShaderHandle compositeShader;

  /// `gfx-04n`: edges smoothed on the composited picture.
  final ShaderHandle fxaaShader;

  /// The screen-space reflection pass.
  final ShaderHandle reflectionShader;

  /// The ambient occlusion pass.
  final ShaderHandle ssaoShader;

  /// The short march toward the light — `gfx-76n`. See `post/contact_shadow.frag`.
  final ShaderHandle contactShadowShader;

  /// `post/camera_velocity.frag` — `R1`.
  final ShaderHandle cameraVelocityShader;

  /// `post/velocity.frag` and the three vertex stages that feed it, for
  /// nodes that moved — `R1`.
  final ShaderHandle velocityShader;
  final ShaderHandle velocityVertexShader;
  final ShaderHandle velocitySkinnedVertexShader;
  final ShaderHandle velocityInstancedVertexShader;

  /// `post/reactive.frag` — `R4`: a blended surface marked in the velocity's
  /// blue, through the same three vertex stages.
  final ShaderHandle reactiveShader;

  /// `post/temporal_resolve.frag` — `R2`.
  final ShaderHandle temporalResolveShader;

  /// `post/temporal_accumulate.frag` — `R3`.
  final ShaderHandle temporalAccumulateShader;

  /// The temporal resolve's two histories, at the output's size: one read,
  /// one written, swapped each frame. The renderer's own, like the cube
  /// atlases, because what they hold outlives the frame.
  final List<TextureHandle?> _history = <TextureHandle?>[null, null];
  int _historyRead = 0;

  /// Whether [_history] holds a frame worth blending: false at first, after a
  /// resize, and after a frame drawn with temporal anti-aliasing off.
  bool _historyValid = false;

  /// `gfx-32n`'s depth-aware blur over what that pass produced.
  final ShaderHandle ssaoBlurShader;

  /// `gfx-33n`'s volumetric shafts through the directional shadow map.
  final ShaderHandle lightShaftsShader;

  /// `S4`'s half-resolution march through the air, and the depth-aware pass
  /// that lays it over the scene.
  final ShaderHandle volumetricFogShader;
  final ShaderHandle volumetricFogUpsampleShader;

  /// `gfx-34n`'s thin lens and its gather.
  final ShaderHandle depthOfFieldShader;

  /// `R6`'s motion blur: the tile search, walked once per axis, the
  /// neighbourhood over the tiles, and the gather.
  final ShaderHandle velocityTileMaxShader;
  final ShaderHandle velocityNeighborMaxShader;
  final ShaderHandle motionBlurShader;

  /// `gfx-43n`/`44n`/`45n`'s three branches over the surface buffer.
  final ShaderHandle viewportShadeShader;

  /// `R8`'s resolve: the transparent layers' weighted average, laid over the
  /// scene.
  final ShaderHandle wboitResolveShader;

  /// 1x1 opaque white, bound when a material has no base-colour texture.
  ///
  /// A shader that declares a sampler must have something bound to it, so
  /// "no texture" has to be a neutral texture rather than an absent binding.
  /// White is also neutral for the ORM, occlusion and emissive slots: it
  /// multiplies each factor by one, so the same texture serves all four.
  ///
  /// Backed by a nullable field that [dispose] clears. Reading this after
  /// dispose is a bug, and it throws rather than handing back a stale
  /// texture — the same contract [ResourceHandle.value] makes for the same
  /// reason: an exception at the mistake is cheaper to debug than a frame
  /// that silently draws with a released resource.
  TextureHandle get fallbackAlbedo =>
      _fallbackAlbedo ?? (throw StateError(_kDisposedMessage));
  TextureHandle? _fallbackAlbedo;

  /// 1x1 (0.5, 0.5, 1.0): the tangent-space normal that perturbs nothing.
  ///
  /// See [fallbackAlbedo] for why this is a throwing getter over a nullable
  /// field rather than a plain final one.
  TextureHandle get fallbackNormal =>
      _fallbackNormal ?? (throw StateError(_kDisposedMessage));
  TextureHandle? _fallbackNormal;

  /// 1x1 black, bound to the lightmap slot of a material without a map: the
  /// map is added, so black is the neutral that adds nothing.
  ///
  /// See [fallbackAlbedo] for why this is a throwing getter over a nullable
  /// field rather than a plain final one.
  TextureHandle get fallbackBlack =>
      _fallbackBlack ?? (throw StateError(_kDisposedMessage));
  TextureHandle? _fallbackBlack;

  /// A one-texel black cube, bound when a scene has no environment.
  ///
  /// **Bound, not omitted.** A sampler a shader declares and nobody binds is a
  /// native crash on Metal rather than a black texture — the rule that keeps
  /// the sky's cube out of `sky.frag` and a white texel under the composite's
  /// occlusion. The shader branches on the level count instead, so what this
  /// contains is never read; black is chosen so that a branch gone wrong is a
  /// scene that goes dark rather than one that glows.
  ///
  /// Null on a device that cannot make cubes at all, which is allowed: the
  /// binding is skipped and so is the branch that would have used it.
  TextureHandle? _fallbackEnvironment;

  /// Made on demand, once, and only where cubes exist.
  TextureHandle? _environmentFallback(GraphicsDevice device) {
    if (_fallbackEnvironment != null) return _fallbackEnvironment;
    if (!device.supportsCubeTextures) return null;
    final face = ByteData(4);
    return _fallbackEnvironment = device.createCubeTextureFromPixels(
      size: 1,
      format: TextureFormat.r8g8b8a8UNormInt,
      faces: <ByteData>[for (var i = 0; i < 6; i++) face],
    );
  }

  /// Releases every GPU-side resource this renderer holds a reference to:
  /// the pipeline cache, the fragment-shader cache, the target pool, and the
  /// fallback albedo and normal textures.
  ///
  /// **This used to open by saying no backend exposes an explicit free, and
  /// that was not true.** `flutter3d_webgl` has always had a real
  /// `dispose`, and every backend now implements
  /// `TextureAllocator.releaseTexture` — a no-op where the collector already
  /// does the job, a `gl.deleteTexture` where nothing else will. So there is a
  /// device call to make here, and this makes it.
  ///
  /// It clears the pipeline and fragment-shader caches, gives the pool's free
  /// list back to the device, drops the fallback textures and the sort-id
  /// table, and releases the targets this renderer owns outright: the shadow
  /// map, both cube atlases, the fallback environment and the debug index
  /// buffer. Reading [fallbackAlbedo] or [fallbackNormal] afterwards is a bug,
  /// and throws rather than handing back a texture nothing else may still
  /// consider live.
  ///
  /// **The sort-id table is not housekeeping.** It held a strong reference to
  /// every material ever drawn, and a material holds its textures, so a
  /// renderer that had drawn a level kept that level's textures alive however
  /// thoroughly the resource cache evicted them. It is weak now — see
  /// [MaterialSortIds] — and clearing it here as well costs nothing.
  ///
  /// The window-sized targets — HDR, LDR, surface, reflection, the depth and
  /// MSAA attachments — are released here too. They used to be left out on the
  /// argument that discarding a renderer drops every reference to it anyway;
  /// that frees them where the collector frees textures and frees nothing on
  /// WebGL2, where only `gl.deleteTexture` does — so a host that rebuilt its
  /// renderer leaked seven full-screen driver objects per rebuild. Released
  /// directly rather than through the frames-in-flight ring the resize path
  /// uses, because that ring is only emptied at the top of a later frame and a
  /// disposed renderer has no later frames — which is also why both rings are
  /// drained here.
  ///
  /// A genuine method of this class rather than a member of
  /// `renderer_resources.dart`'s extension, even though the caches it clears
  /// are read and filled there: that extension is private, so its members
  /// are only in scope inside this library, and a host application calling
  /// this from its own code could not see them.
  ///
  /// Idempotent: calling this twice clears already-empty caches and trims an
  /// already-trimmed pool, so a caller does not have to track whether it
  /// already ran.
  void dispose() {
    _pipelineCache.clear();
    _fragmentShaders.clear();

    // Whatever the last frames queued but no frame has retired yet: pooled
    // targets go back through the pool so the trim below frees them, owned
    // ones go straight to the device.
    for (final slot in _pendingRelease) {
      for (final texture in slot) {
        targetPool.release(texture);
      }
      slot.clear();
    }
    for (final slot in _pendingDestroy) {
      for (final texture in slot) {
        device.releaseTexture(texture);
      }
      slot.clear();
    }
    targetPool.trim();

    // The window-sized targets `_ensureTargets` owns. On a resize they go
    // through the frames-in-flight ring because the frame drawn with them may
    // still be reading; here there is no next frame to wait for, so they are
    // given back directly, and the size is zeroed so a second call finds
    // nothing to release.
    for (final texture in <TextureHandle?>[
      _hdrColor,
      _hdrMsaa,
      _surfaceColor,
      _albedoColor,
      _surfaceMsaa,
      _reflectionColor,
      _depthStencil,
      _depthStencilSingle,
      _wboitAccumulation,
      _wboitRevealage,
      _wboitDepth,
      ..._ldrFrames,
      ..._history,
      for (final effect in _effectHistories.values) ...effect.textures,
      _irradianceAtlas,
      _irradianceGpu?.atlas.current,
      _irradianceGpu?.radiance,
      _irradianceGpu?.surface,
    ]) {
      if (texture != null) device.releaseTexture(texture);
    }
    _effectHistories.clear();
    _history
      ..[0] = null
      ..[1] = null;
    _historyValid = false;
    _hdrColor = null;
    _hdrMsaa = null;
    _surfaceColor = null;
    _albedoColor = null;
    _surfaceMsaa = null;
    _reflectionColor = null;
    _depthStencil = null;
    _depthStencilSingle = null;
    _wboitAccumulation = null;
    _wboitRevealage = null;
    _wboitDepth = null;
    _ldrFrames.clear();
    _ldrFree.clear();
    _ldrCurrent = null;
    _targetWidth = 0;
    _targetHeight = 0;
    _frameTargetWidth = 0;
    _frameTargetHeight = 0;

    // Released rather than merely dropped, and nulled so a second call is the
    // no-op this method promises to be.
    for (final texture in <TextureHandle?>[
      _fallbackAlbedo,
      _fallbackNormal,
      _fallbackBlack,
      _fallbackEnvironment,
      _shadowMap,
      _shadowMapStatic,
      _shadowMapStaticSpare,
      _shadowDepth,
      _shadowMoments,
      _shadowMomentsScratch,
      _cubeShadow,
      _cubeShadowStatic,
      _cubeShadowDepth,
      _lightListTexture,
      for (final probe in _probeStates.values) ...<TextureHandle>[
        probe.capture,
        probe.filtered,
      ],
    ]) {
      if (texture != null) device.releaseTexture(texture);
    }
    _probeStates.clear();
    _fallbackAlbedo = null;
    _fallbackNormal = null;
    _fallbackBlack = null;
    _fallbackEnvironment = null;
    _shadowMap = null;
    _shadowMapStatic = null;
    _shadowMapStaticSpare = null;
    _shadowDepth = null;
    _shadowMoments = null;
    _shadowMomentsScratch = null;
    _shadowMomentsKey = null;
    _cubeShadow = null;
    _cubeShadowStatic = null;
    _cubeShadowDepth = null;
    _cubeShadowTile = 0;
    _lightListTexture = null;
    _lightListUploaded = Float32List(0);

    _debugIndices.release(device);
    final fullscreen = _fullscreenVertices;
    if (fullscreen != null) device.releaseGeometry(fullscreen);
    _fullscreenVertices = null;

    // The batches hold their mesh and material strongly — the same reason the
    // sort-id table below went weak — so a renderer kept past a level would
    // otherwise keep that level's geometry and textures with it.
    _batchPool.clear();
    _batchesUsed.clear();

    _renderList.materialIds.clear();

    // A question no frame will ever answer is answered now — a pixel with
    // nothing, a whole frame with an error: a future that never completes is
    // a caller waiting for a renderer that is gone.
    for (final pick in _pendingPicks) {
      pick.abandon();
    }
    _pendingPicks.clear();
  }

  final bool msaaEnabled;

  /// Which slot of the deferred-release ring this frame retires.
  ///
  /// The per-frame uniform allocators used to be rotated here too. They belong
  /// to the backend now — where a uniform's bytes live until the GPU has read
  /// them is a property of the API, not of the engine — and
  /// `GraphicsDevice.beginFrame` rotates them. The ring length is the same fact
  /// twice, which is why it is named once here and once there.
  int _frameIndex = 0;

  /// How many frames this renderer has drawn — `G2`.
  ///
  /// Public because everything temporal is a function of it and of nothing
  /// else: a jitter sequence, a noise layer, a history's age. Two runs that
  /// draw the same frames in the same order see the same numbers, which is
  /// what keeps a multi-frame golden as deterministic as a still.
  int get frameIndex => _frameIndex;

  /// What the previous frame looked like — `G2`. Recorded at the end of each
  /// frame while [FrameHistory.tracking] is on, and read during the next.
  final FrameHistory frameHistory = FrameHistory();

  static const int _kFramesInFlight = 3;

  final RenderList _renderList = RenderList();

  /// Reused across frames, so a steady overlay allocates nothing.
  final DebugDraw debugDraw = DebugDraw();

  /// The scene's lights, repacked once per view.
  final LightBuffer lights = LightBuffer();

  /// The scene [lights] was last gathered from — the world scene of the frame
  /// being drawn. [encodeScene] compares against it: a contributor drawing the
  /// same scene reuses the frame's tables, and one drawing its own scene gets
  /// that scene's lights instead of the world's. The view model found the
  /// difference the visible way: its studio's two lights were never gathered,
  /// so a metallic weapon was lit by torches metres behind the camera and
  /// rendered nearly black on every backend at once.
  Scene? _lightsScene;

  /// Lights for a contributor scene, gathered per [encodeScene] call. Its own
  /// buffer rather than a re-gather into [lights], because the frame's buffer
  /// is what the shadow tables were built against and must survive the pass.
  final LightBuffer _passLights = LightBuffer();

  /// The slot table that says "no light casts a point shadow", for scenes the
  /// frame's atlas assignment knows nothing about. `slots[i].x < 0` is the
  /// shader's own early-out, so binding this is cheaper than a flag.
  static final Float32List _noShadowSlots = Float32List(
    4 * LightBuffer.maxLights,
  )..fillRange(0, 4 * LightBuffer.maxLights, -1.0);

  // Uniform scratch, reused rather than rebuilt per draw. Writing a fresh
  // Float32List for every member of every draw is precisely the allocation
  // pattern the render list was shaped to avoid.
  /// Eight morph weights and the shape of the delta texture.
  ///
  /// Written on every mesh draw, neutral when the mesh has no targets: the
  /// vertex stage declares the block whatever is drawn through it, so leaving
  /// it unbound is the arrangement that killed Metal in `sky.frag`.
  // The uniform blocks the renderer fills, one object each and laid out as
  // the compiler lays them out — `H1`. The scratch arrays below were fields
  // of their own and are now the blocks' members under their old names, so
  // every write that filled them fills the block.
  final BloomInfoBlock _bloomInfo = BloomInfoBlock();
  final CompositeInfoBlock _compositeInfo = CompositeInfoBlock();
  final ContactShadowInfoBlock _contactShadowInfo = ContactShadowInfoBlock();
  final CameraVelocityInfoBlock _cameraVelocityInfo = CameraVelocityInfoBlock();
  final PrevFrameInfoBlock _prevFrameInfo = PrevFrameInfoBlock();
  final VelocityInfoBlock _velocityInfo = VelocityInfoBlock();
  final ReactiveInfoBlock _reactiveInfo = ReactiveInfoBlock();
  final TemporalInfoBlock _temporalInfo = TemporalInfoBlock();
  final NoiseInfoBlock _noiseInfo = NoiseInfoBlock();
  final AccumulateInfoBlock _accumulateInfo = AccumulateInfoBlock();

  /// Whether this frame's screen-space effects read the blue noise and keep
  /// histories — `R3`: while a temporal resolve runs, on a device that can
  /// run one. Set at the top of [render].
  bool _temporalEffects = false;

  /// The noisy effects' histories, by the resource each one smooths — `R3`.
  final Map<ResourceId, _EffectHistory> _effectHistories =
      <ResourceId, _EffectHistory>{};

  /// The texture every noise-reading effect binds this frame, with
  /// [_noiseInfo] filled to match — `R3`. The engine's blue noise while
  /// [_temporalEffects], uploaded on first use; the one-texel stand-in
  /// otherwise, which the shader does not read.
  TextureHandle get _blueNoise {
    _noiseInfo.noise
      ..[0] = _temporalEffects ? 1.0 : 0.0
      ..[1] = (_frameIndex % 32).toDouble();
    return _temporalEffects
        ? EngineTables.of(device).blueNoise
        : fallbackAlbedo;
  }

  final DofInfoBlock _dofInfo = DofInfoBlock();
  final TileMaxInfoBlock _tileMaxInfo = TileMaxInfoBlock();
  final NeighborMaxInfoBlock _neighborMaxInfo = NeighborMaxInfoBlock();
  final MotionBlurInfoBlock _motionBlurInfo = MotionBlurInfoBlock();
  final FogInfoBlock _fogInfo = FogInfoBlock();
  final LayerInfoBlock _layerInfo = LayerInfoBlock();
  final FrameInfoBlock _frameInfo = FrameInfoBlock();
  final IdInfoBlock _idInfo = IdInfoBlock();
  final LineInfoBlock _lineInfo = LineInfoBlock();
  final SkinInfoBlock _skinInfo = SkinInfoBlock();
  final FragCoordInfoBlock _fragCoordInfo = FragCoordInfoBlock();
  final FragInfoBlock _fragInfo = FragInfoBlock();
  final FxaaInfoBlock _fxaaInfo = FxaaInfoBlock();
  final EasuInfoBlock _easuInfo = EasuInfoBlock();
  final LocalExposureInfoBlock _localExposureInfo = LocalExposureInfoBlock();
  final LocalExposureBlurInfoBlock _localExposureBlurInfo =
      LocalExposureBlurInfoBlock();
  final LightListInfoBlock _lightListInfo = LightListInfoBlock();
  final LuminanceInfoBlock _luminanceInfo = LuminanceInfoBlock();
  final DepthPyramidInfoBlock _depthPyramidInfo = DepthPyramidInfoBlock();
  final MaskInfoBlock _maskInfo = MaskInfoBlock();
  final MorphInfoBlock _morphInfo = MorphInfoBlock();
  final MorphInstanceInfoBlock _morphInstanceInfo = MorphInstanceInfoBlock();
  final PointShadowBlock _pointShadow = PointShadowBlock();
  final ProbeInfoBlock _probeInfo = ProbeInfoBlock();
  final ReflectionInfoBlock _reflectionInfo = ReflectionInfoBlock();
  final ShadeInfoBlock _shadeInfo = ShadeInfoBlock();
  final ShadowLightBlock _shadowLight = ShadowLightBlock();
  final ShaftInfoBlock _shaftInfo = ShaftInfoBlock();
  final VolumeFogInfoBlock _volumeFogInfo = VolumeFogInfoBlock();
  final FogUpsampleInfoBlock _fogUpsampleInfo = FogUpsampleInfoBlock();
  final SsaoBlurInfoBlock _ssaoBlurInfo = SsaoBlurInfoBlock();
  final SsaoInfoBlock _ssaoInfo = SsaoInfoBlock();

  Float32List get _morphWeights => _morphInfo.morphWeights;
  Float32List get _morphParams => _morphInfo.morphParams;
  Float32List get _morphInstanceParams => _morphInstanceInfo.instanceParams;

  Float32List get _fogData => _fogInfo.fog;
  Float32List get _cameraData => _fragInfo.cameraPosition;

  /// Which way the camera of the pass being encoded looks, in world space.
  ///
  /// Beside the camera position because the surface buffer's depth is measured
  /// along it — see `ViewDepth` in `lib/color.glsl`. Written wherever
  /// [_cameraData] is, and the two are meaningless apart.
  Float32List get _forwardData => _fogInfo.forward;
  final vm.Vector3 _forward = vm.Vector3.zero();
  Float32List get _baseColorData => _fragInfo.baseColor;
  Float32List get _emissiveData => _fragInfo.emissive;
  Float32List get _materialData => _fragInfo.material;
  Float32List get _material2Data => _fragInfo.material2;
  Float32List get _frameParams => _fragInfo.frameParams;

  /// The reflection probes this renderer has drawn, by the node that placed
  /// them. Two cubes each, kept across frames — see `renderer_probe_pass.dart`.
  final Map<ReflectionProbeNode, _ProbeState> _probeStates =
      <ReflectionProbeNode, _ProbeState>{};

  /// Whether a probe has already drawn a whole cube this frame.
  ///
  /// The frame's budget, and one is the whole of it — see
  /// `_claimWholeProbeCapture`. Cleared where the probe nodes are built,
  /// which is once per `render`.
  bool _wholeProbeCaptured = false;
  Float32List get _probeParams => _probeInfo.params;
  final vm.Vector3 _probePosition = vm.Vector3.zero();
  PipelineHandle? _probePrefilterPipeline;

  PipelineHandle? _debugLinePipeline;

  /// A 0, 1, 2, … index buffer for the debug overlay.
  ///
  /// The overlay's vertices are already in draw order, so indices carry no
  /// information — but `draw()` submits nothing without an index buffer bound,
  /// and there is no non-indexed entry point in the API. Keeping the identity
  /// sequence in a device buffer that only grows means the cost is one upload
  /// when the overlay gets bigger, not one per frame.
  final IdentityIndices _debugIndices = IdentityIndices();

  /// Pipelines keyed by both stages; creating one compiles and links state on
  /// the backend, far too expensive to repeat per frame.
  ///
  /// Keyed on the pair rather than the fragment shader alone, because skinning
  /// added a second vertex stage: with only the fragment name as the key, a
  /// skinned draw would be handed the static pipeline the first PBR draw built,
  /// and the vertex layouts do not match.
  ///
  /// A field, not a part of `renderer_resources.dart`: a `part` shares this
  /// library's scope but not a class's *body* — an extension can add the
  /// getters and methods that read this cache, the same way the shadow and
  /// sky passes already do, but the field itself has to live where the class
  /// is declared.
  final Map<String, PipelineHandle> _pipelineCache = <String, PipelineHandle>{};

  /// Pipelines the renderer has built so far.
  ///
  /// Reported per frame because it is the number that has to stay put: light
  /// count, light type and material values are all uniforms, and any of them
  /// pushing this up would mean a permutation had crept in where a uniform
  /// belonged. With no runtime shader compilation, that is not a slow path —
  /// it is a wrong one.
  ///
  /// A plain getter on the class rather than in `renderer_resources.dart`
  /// with the cache's other readers: nothing in this repository calls it yet
  /// — it is public API for a host application's own overlay — and the
  /// analyzer's dead-code check is stricter for a private extension's
  /// members than for the class's own, so this one stays where it cannot be
  /// mistaken for unused.
  int get pipelineCount => _pipelineCache.length;

  /// Drops every pipeline this renderer has linked, so the next frame links
  /// them again from whatever the stages are now.
  ///
  /// **The engine's half of a hot reload.** A `LoadedShaderLibrary.refresh`
  /// swaps the code behind a stage while keeping the handle — that is its
  /// promise — but a pipeline is a pair of stages *linked*, and the linked
  /// object on every backend still holds the old code until it is built
  /// again. Nothing here compiles, so the cost is one link per pipeline the
  /// next frame binds, which is exactly the cost of the first frame.
  ///
  /// Every cache goes, not only the material pipelines: a bundle handed in as
  /// `materials` wins any name it shares with the engine's, so a reload can
  /// have changed the sky, a shadow stage or the composite as easily as a
  /// look. The fragment-stage cache goes with them, because a stage the
  /// reloaded bundle newly answers has to be looked up again to be found.
  ///
  /// The resolved vertex stages the renderer holds — `vertexShader` and its
  /// siblings — are not re-resolved; they do not need to be, since their
  /// handles are the same objects after a reload. What this cannot do is pick
  /// up a stage a bundle *newly* lists under a name the renderer resolved to
  /// nothing at `Renderer.create`; that path throws at create, so there is no
  /// renderer to reload.
  ///
  /// Contributors keep their own pipelines — `ParticleContributor` links once
  /// and holds — and are not reached from here; a contributor that wants to
  /// follow a reload exposes its own way to drop what it linked.
  void relinkShaders() {
    _pipelineCache.clear();
    _fragmentShaders.clear();
    _fullscreenPipelines.clear();
    _debugLinePipeline = null;
    _shadowPipeline = null;
    _skinnedShadowPipeline = null;
    _instancedShadowPipeline = null;
    _maskedShadowPipeline = null;
    _skinnedMaskedShadowPipeline = null;
    _instancedMaskedShadowPipeline = null;
    _maskedCubeShadowPipeline = null;
    _skinnedMaskedCubeShadowPipeline = null;
    _instancedMaskedCubeShadowPipeline = null;
    _bloomUpsamplePipeline = null;
    _wboitResolvePipeline = null;
    _compositePipeline = null;
    _probePrefilterPipeline = null;
    _skyPipeline = null;
    _skyCubePipeline = null;
    _cubeShadowPipeline = null;
    _skinnedCubeShadowPipeline = null;
    _instancedCubeShadowPipeline = null;
    _cubeShadowResetPipeline = null;
    _shadowCopyPipeline = null;
  }

  final Map<String, ShaderHandle> _fragmentShaders = <String, ShaderHandle>{};

  /// Vertex stages a material brought with it, by entry point — `gfx-75n`.
  ///
  /// Beside [_fragmentShaders] and for its reason: the lookup throws when the
  /// name is not there, and a throw per draw would be a throw per frame.
  final Map<String, ShaderHandle> _materialVertexShaders =
      <String, ShaderHandle>{};

  /// Textures reused across frames and across bloom levels.
  ///
  /// The device is the allocator: one rule for every texture in the engine,
  /// and no second way to make one.
  final RenderTargetPool targetPool;

  /// Gives back every pooled transient target no live frame is holding —
  /// `gfx-71n`.
  ///
  /// **What the pool does without this is settle at a high-water mark and stay
  /// there.** It keeps one texture of every attachment shape any frame has ever
  /// needed: turn bloom on once and its five levels are held for the rest of
  /// the session, take one screenshot at twice the window size and that pair of
  /// targets is held too. On a desktop that is a megabyte nobody notices; on a
  /// phone it is the difference between a slow frame and the process being
  /// killed, which is why this is wired to the platform's own warning rather
  /// than to a budget this package would have to invent.
  ///
  /// Safe at any moment between frames: what is lent out is left alone, and
  /// `RenderTargetPool.trim` marks those retired so they go back to the device
  /// when their frame releases them rather than into a free list for a size
  /// nothing will ask for again. The next frame allocates what it needs and
  /// draws the same picture, a little slower once.
  ///
  /// `Flutter3dSurface` calls it from `didHaveMemoryPressure`. An application
  /// that owns its own renderer calls it from wherever its platform says.
  void releaseTransientTargets() => targetPool.trim();

  /// Called with every pooled target of a [render] frame at the moment its
  /// lifetime in the frame ends — `H7`. Null, and so nothing, by default.
  ///
  /// A test hook, and the way `RenderSettings.aliasTargets` is proved safe: a
  /// callback that fills the texture with garbage makes a pass that reads a
  /// resource after its last declared use, or loads a target it never wrote,
  /// show up as a changed picture.
  void Function(TextureHandle texture)? debugOnTargetRetired;

  int _targetWidth = 0;
  int _targetHeight = 0;

  /// The finished frame's size, which is [_targetWidth] × [_targetHeight]
  /// except while temporal anti-aliasing reconstructs a larger one — `R2`.
  int _frameTargetWidth = 0;
  int _frameTargetHeight = 0;

  /// The finished frame's format — `R9`: the device's first HDR output
  /// format under `OutputTransform.extendedSrgb` where it has one, its
  /// default colour format otherwise. Set per frame by [render].
  TextureFormat _frameFormat = TextureFormat.r8g8b8a8UNormInt;
  TextureFormat? _frameTargetFormat;

  /// Whether this frame is encoded for an extended-range display — `R9`.
  bool _extendedOutput = false;

  /// This frame's allowance for work that can wait — `N3`. Remade when the
  /// setting changes, started again at the top of every frame.
  FrameWorkBudget _workBudget = FrameWorkBudget();

  /// The allowance the last frame ran under, for a caller or a test to read
  /// what it spent and what it put off.
  FrameWorkBudget get frameWorkBudget => _workBudget;

  /// This frame's output size, as [render] worked it out.
  int _outputWidth = 0;
  int _outputHeight = 0;

  /// The nodes that run at the output size rather than the scene's: those
  /// registered after the temporal resolve. Empty while it is off.
  Set<FrameGraphNode> _outputSized = const <FrameGraphNode>{};

  /// The scene, in linear light with no upper bound. Everything post-processing
  /// does depends on values above display white surviving this far, which is
  /// exactly what the old 8-bit target threw away.
  TextureHandle? _hdrColor;
  TextureHandle? _hdrMsaa;

  /// The finished frames, and which of them the compositor has let go of.
  ///
  /// **One texture was a frame you could watch being drawn.** The composite
  /// writes the picture a caller presents, and presenting it hands *that same
  /// allocation* to Flutter, which composites on its own thread on its own
  /// schedule — so the next frame's clear and passes land in the texture the
  /// screen is reading. On a scene that changes every frame nobody sees it: a
  /// half-written frame is a mix of two pictures a millimetre of camera apart.
  /// On a still scene — an editor holding a level with nobody touching the
  /// keyboard — it is unmissable.
  ///
  /// **A ring of a fixed depth is a guess, and every depth was wrong.** Three
  /// flickered, eight flickered less, sixteen stopped it on this machine —
  /// which says nothing about the next one, because what the depth has to be
  /// depends on the display's rate, the build's speed and how far behind the
  /// GPU is. So the depth is not chosen: a texture goes back into rotation when
  /// [GraphicsDevice.onFrameComplete] says the work that read it is done, and
  /// a frame that finds none free makes one. On a machine that needs two, two
  /// is what it keeps.
  ///
  /// **What that callback tracks is the renderer's GPU work, not the
  /// compositor's.** The texture is handed to Flutter as an image, and the
  /// raster thread samples it on its own command buffer, later; the
  /// completion this waits for is the renderer's, which comes first. The
  /// surface probe (`ARCHITECTURE.md` §15) reduced this arrangement to a
  /// clear-only frame and watched it reuse one texture at the display's
  /// pace: one display period, 8.3 ms on the machine measured, between a
  /// clear and the next, with the compositor's read landing somewhere inside
  /// it. What the probe cannot do is catch that read going wrong. It reads
  /// one frame back per path — the last — and it reads it out of the texture
  /// this side owns rather than out of the composite Flutter drew, so a
  /// picture torn on the raster thread leaves no mark on it. Most likely both
  /// sit on one queue in submission order, and that is what keeps the picture
  /// whole rather than anything here — which the probe did not observe and
  /// nothing in this repository checks. A real frame's passes finish later
  /// than a clear does, so the ring grows to what the overlap needs. The ring
  /// could close the gap itself — keep a presented texture out of rotation
  /// for one more presented frame, at the cost of one more texture, which is
  /// the effect the backend's own presentable surface buys with a reference
  /// count; the probe runs that variant too — and does not, because no torn
  /// frame has been seen since the ring replaced the single texture. That is
  /// an eye on the samples and the golden scenes rather than an instrument,
  /// and it is the whole of the evidence.
  /// That surface was measured and not taken, for the reason §15 gives with
  /// the numbers.
  final List<TextureHandle> _ldrFrames = <TextureHandle>[];
  final List<TextureHandle> _ldrFree = <TextureHandle>[];
  TextureHandle? _ldrCurrent;

  /// The frame currently being drawn into.
  TextureHandle? get _ldrColor => _ldrCurrent;
  Float32List get _reflectionParams => _reflectionInfo.params;
  Float32List get _reflectionScreen => _reflectionInfo.screen;
  Float32List get _reflectionCameraData => _reflectionInfo.camera;
  final vm.Vector3 _reflectionCamera = vm.Vector3.zero();
  Float32List get _reflectionForwardData => _reflectionInfo.forward;
  final vm.Vector3 _reflectionForward = vm.Vector3.zero();
  TextureHandle? _reflectionColor;
  TextureHandle? _surfaceColor;

  /// The albedo buffer — `L5`. See [FrameResourceIds.albedoBuffer].
  TextureHandle? _albedoColor;
  TextureHandle? _surfaceMsaa;
  TextureHandle? _depthStencil;

  /// A one-sample depth, for the frames that switch multisampling off because
  /// they want the surface buffer. Attachments in one target must agree on
  /// sample count, so a four-sample depth cannot sit beside a resolved colour.
  TextureHandle? _depthStencilSingle;

  /// Weighted blended transparency's targets — `R8`: the accumulation, the
  /// revealage, and a one-sample depth the scene pass stores for the
  /// transparent passes to load. Made the first time a frame asks, released
  /// with the others on a resize; see `renderer_transparency_pass.dart`.
  ///
  /// Their own depth rather than [_depthStencilSingle], which is
  /// `deviceTransient` — memoryless on Apple GPUs, with nothing to load.
  TextureHandle? _wboitAccumulation;
  TextureHandle? _wboitRevealage;
  TextureHandle? _wboitDepth;

  // `hdrFormat` is declared in `renderer_resources.dart`, alongside the
  // caches that key off it.

  /// The two materials every marked node is drawn again with, and the nodes
  /// this view marks. See `renderer_xray_pass.dart`.
  ///
  /// Held rather than built per frame for the reason the uniform scratch
  /// arrays are: a material per node per frame is an allocation in the draw
  /// loop. The colour is written into `baseColor` from the settings each
  /// frame, and `doubleSided` from the node each draw.
  ///
  /// **[LightingModel.xray] rather than [LightingModel.unlit], and the
  /// difference is the surface buffer.** Unlit writes attachment one like
  /// every other model — a silhouette would then have stamped a hidden
  /// monster's normal and depth over the wall in front of it, since the
  /// paint's depth test passes exactly where the monster is behind something.
  /// Nothing in the blend state could take that back: it protects attachment
  /// zero, and only on the backends whose `setBlend` honours an attachment
  /// index. `xray.frag` declares no second output at all.
  final Material _xrayMark = Material(
    name: 'x-ray mark',
    lighting: LightingModel.xray,
    depthWrite: false,
    depthCompare: CompareFunction.lessEqual,
  );
  final Material _xraySilhouette = Material(
    name: 'x-ray silhouette',
    lighting: LightingModel.xray,
    depthWrite: false,
    depthCompare: CompareFunction.greater,
  );
  final List<MeshNode> _xrayNodes = <MeshNode>[];

  PipelineHandle? _shadowPipeline;
  PipelineHandle? _skinnedShadowPipeline;

  /// `gfx-60n`: the same three again, against the cut-out shadow stages.
  ///
  /// Separate handles rather than a flag on the three above, because a
  /// pipeline is a shader pair and these pair a different fragment stage. A
  /// scene with no cut-out caster never builds them.
  PipelineHandle? _maskedShadowPipeline;
  PipelineHandle? _skinnedMaskedShadowPipeline;
  PipelineHandle? _instancedMaskedShadowPipeline;
  PipelineHandle? _maskedCubeShadowPipeline;
  PipelineHandle? _skinnedMaskedCubeShadowPipeline;
  PipelineHandle? _instancedMaskedCubeShadowPipeline;

  /// `gfx-60n`: the cutoff and the base alpha, packed for the shadow stages.
  Float32List get _shadowMask => _maskInfo.mask;
  PipelineHandle? _instancedShadowPipeline;
  PipelineHandle? _bloomUpsamplePipeline;
  PipelineHandle? _wboitResolvePipeline;
  PipelineHandle? _compositePipeline;

  /// Positions and UVs of the one triangle every full-screen pass draws.
  GeometryBuffer? _fullscreenVertices;

  /// Built the first time a frame asks for a sky, and never if none does.
  ///
  /// Lazy, and deliberately absent from the eager list `Renderer.create`
  /// resolves: an application whose shader bundle predates the sky would
  /// otherwise fail to start rather than fail to draw a sky it never asked for.
  /// That is the same argument `renderer_create_test.dart` already pins for the
  /// particle stages.
  PipelineHandle? _skyPipeline;

  /// The textured half of the same pair, built only if a cube is ever set.
  PipelineHandle? _skyCubePipeline;

  /// World space to the shadow camera's clip space, rebuilt each frame the
  /// light or the scene moves.
  final vm.Matrix4 _shadowMatrix = vm.Matrix4.identity();

  /// The second and third cascades' matrices. Copies of the first when there is
  /// only one, so the shader can read all three without asking how many.
  final vm.Matrix4 _shadowMatrixFar = vm.Matrix4.identity();
  final vm.Matrix4 _shadowMatrixFarthest = vm.Matrix4.identity();

  /// x, y: where cascades 0 and 1 end, in metres from the camera. z: how many
  /// there are. w: one texel of a tile, vertically.
  Float32List get _shadowCascades => _fragInfo.shadowCascades;

  int _shadowCascadeCount = 1;

  /// How far each cascade reached, in metres, as of the last shadow pass.
  ///
  /// For tests and for a frame inspector. The whole argument for cascades is a
  /// number — how much world one texel covers — and a change that cannot be
  /// measured is a change that gets quietly undone.
  List<double> get debugCascadeRadii =>
      List<double>.unmodifiable(_shadowCascadeRadii);
  final List<double> _shadowCascadeRadii = <double>[];

  /// Where each cascade was centred, after snapping, as of the last pass.
  ///
  /// Exposed for one test, and it is the only way to make that test honest: the
  /// snapping's whole job is that this value *quantises* as the camera creeps,
  /// and a picture at any single moment cannot show the difference between a
  /// number that jumps and one that slides.
  List<vm.Vector3> get debugCascadeCentres =>
      List<vm.Vector3>.unmodifiable(_shadowCascadeCentres);
  final List<vm.Vector3> _shadowCascadeCentres = <vm.Vector3>[];

  /// [_shadowMatrix] in the backend's clip space, for drawing the map with.
  final vm.Matrix4 _shadowDrawMatrix = vm.Matrix4.identity();
  Float32List get _shadowParams => _fragInfo.shadowParams;

  /// `FragInfo.target_origin`: the rows of the target the scene draws into
  /// when its row zero is the bottom of the picture — see
  /// `lib/frag_coord.glsl`. Set where each pass that draws meshes begins.
  Float32List get _targetOrigin => _fragInfo.targetOrigin;

  /// `FragCoordInfo.origin`, the same number for a full-screen pass.
  Float32List get _fragCoordOrigin => _fragCoordInfo.origin;

  /// How many rows [target] has if this backend counts them from the bottom,
  /// and zero if it counts from the top — what `FragCoordFromTop` turns
  /// `gl_FragCoord` around with.
  double _rowsFromBottom(TextureHandle target) =>
      device.framebufferOrigin == FramebufferOrigin.bottomLeft
      ? ScreenRect.of(target).height.toDouble()
      : 0.0;

  /// Binds `FragCoordInfo` for [stage] drawing into [target]. A stage that
  /// does not declare the block answers false and nothing is bound.
  void _bindFragCoord(
    PassEncoder pass,
    ShaderHandle stage,
    TextureHandle target,
  ) {
    _fragCoordOrigin[0] = _rowsFromBottom(target);
    pass.bindBlock(stage, _fragCoordInfo);
  }

  /// `ShadowSettings.bias` per cascade, in each cascade's own depth: see
  /// `shadow_bias` in `surface.glsl`.
  Float32List get _shadowCascadeBias => _fragInfo.shadowBias;
  final List<double> _shadowCascadeBiasScale = <double>[1.0, 1.0, 1.0];
  TextureHandle? _shadowMap;

  /// The static casters' own directional atlas — `S1`: drawn when they
  /// change, and copied tile by tile into [_shadowMap] under the dynamic
  /// ones. Null while nothing in the scene is marked static.
  TextureHandle? _shadowMapStatic;

  /// The other static atlas, which a frame that changes a static tile draws
  /// into from [_shadowMapStatic] before the two change places — `S1`.
  TextureHandle? _shadowMapStaticSpare;

  /// The matrices each static tile was drawn with, for the next frame to
  /// scroll it by, and the static casters' key it was drawn under.
  final List<vm.Matrix4?> _staticShaderMatrices = <vm.Matrix4?>[
    null,
    null,
    null,
  ];
  final List<vm.Matrix4?> _staticRawMatrices = <vm.Matrix4?>[null, null, null];
  int? _staticSceneKey;

  /// The depth buffer the cascade atlas is drawn with, kept for as long as the
  /// atlas is rather than borrowed from the pool a frame at a time.
  ///
  /// **A pooled one is a different texture every frame, and that is a problem
  /// the engine below cannot see.** A backend may cache the framebuffer it
  /// built for a colour attachment — Impeller's Vulkan backend does — and a
  /// framebuffer holds a view of every attachment in it. Pairing one long-lived
  /// atlas with a fresh depth buffer each frame hands that cache a key it thinks
  /// it has seen, and the pass is drawn with the *previous* depth texture: a
  /// crash where that texture has since been freed, and a shadow map drawn into
  /// the wrong buffer where it has not. Filed as flutter/flutter#192538.
  ///
  /// Owning it costs one texture the size of the atlas and takes the question
  /// away.
  TextureHandle? _shadowDepth;

  /// The directional atlas as blurred exponential moments, and the atlas the
  /// first of the two blur passes lands in — `S2`. Null until a frame asks
  /// for [ShadowFilter.evsm] on a device that can filter them.
  TextureHandle? _shadowMoments;
  TextureHandle? _shadowMomentsScratch;

  /// Counts the frames that drew into [_shadowMap], so the moments are made
  /// again only when the depth they are made of changed — a kept atlas keeps
  /// its moments too.
  int _shadowMapVersion = 0;

  /// What [_shadowMoments] was last made from: [_shadowMapVersion], the blur
  /// radius and the cascade count. Null when it holds nothing yet.
  (int, int, int)? _shadowMomentsKey;
  int _shadowResolution = 0;
  int _shadowCasters = 0;
  int _shadowsDenied = 0;

  /// Whether the current run of empty frames has already been explained.
  ///
  /// See the assert at the end of [render]: the report is once per run of
  /// empty frames, not once per empty frame and not once per renderer.
  bool _emptyFrameReported = false;

  Float32List get _bloomParams => _bloomInfo.params;

  /// The upsample step's per-channel factor: the ratio of this level's
  /// halation and scatter weight to the one above's. See `_renderBloom`.
  Float32List get _bloomTint => _bloomInfo.tint;
  Float32List get _fxaaParams => _fxaaInfo.params;

  /// `gfx-29n`: x is the sharpening amount, the rest unclaimed.
  Float32List get _fxaaSharpen => _fxaaInfo.sharpen;

  /// `gfx-32n`: one texel of the occlusion buffer, the tap count, and how
  /// fast a tap's weight falls off with depth.
  Float32List get _ssaoBlurParams => _ssaoBlurInfo.params;

  /// `gfx-33n`'s own four vectors. The three matrices it also needs are the
  /// shadow pass's, reused rather than recomputed.
  Float32List get _shaftCamera => _shaftInfo.camera;
  Float32List get _shaftForward => _shaftInfo.forward;
  Float32List get _shaftScatter => _shaftInfo.scatter;

  /// The shafts' `sun`: the direction towards the caster, and the phase's g.
  Float32List get _shaftSun => _shaftInfo.sun;
  Float32List get _shaftCascades => _shaftInfo.cascades;
  final vm.Vector3 _shaftCameraVec = vm.Vector3.zero();
  final vm.Vector3 _shaftForwardVec = vm.Vector3.zero();
  Float32List get _dofLens => _dofInfo.lens;
  Float32List get _dofParams => _dofInfo.params;
  Float32List get _shadeParams => _shadeInfo.params;
  Float32List get _shadeScreen => _shadeInfo.screen;
  Float32List get _shadeLight => _shadeInfo.light;
  final vm.Vector3 _shadeLightVec = vm.Vector3.zero();
  Float32List get _compositeParams => _compositeInfo.params;
  Float32List get _compositeAoTexel => _compositeInfo.aoTexel;
  Float32List get _luminanceParams => _luminanceInfo.params;

  /// The exposure as it stands, while auto exposure is on; null until a frame
  /// has asked for it.
  ///
  /// Kept across a setting switched off and on again, so a game that toggles
  /// the meter for a menu comes back to the exposure it left rather than to
  /// the setting's number and a second climb.
  ExposureAdapter? _autoExposure;

  /// One adapter per view, for `gfx-22n`'s per-view metering.
  ///
  /// Beside [_autoExposure] rather than replacing it: with per-view metering
  /// off there is one exposure for the frame and this stays empty, which is
  /// what keeps a stereo pair — and every golden — on the path it has always
  /// taken. Indexed by the view's place in the ordered list, so a frame that
  /// gains a view gains an adapter starting where the frame's own exposure is
  /// rather than at the setting's number and a fresh climb.
  final List<ExposureAdapter> _viewExposure = <ExposureAdapter>[];

  /// `C2`: the occluders rasterised on the CPU, made on the first frame
  /// that asks for [OcclusionMode.software] and kept, so a renderer that
  /// never does allocates no buffer.
  SoftwareOcclusion? _softwareOcclusion;

  /// `C3`: the last depth reading and the grid it is reprojected into, made
  /// on the first frame that asks for [OcclusionMode.hiZ].
  HiZOcclusion? _hiZ;

  /// Advanced whenever the reading is thrown away, so a readback that was
  /// already in the air lands on nothing rather than restoring a reading of
  /// a scene the frame has since stopped trusting.
  int _hiZEpoch = 0;

  /// Whether a depth-pyramid readback has been asked for and not yet
  /// answered — one at a time, for the reason [_meterInFlight] gives.
  bool _pyramidInFlight = false;

  /// The occlusion reading, for tests and a profiler: how many readings of
  /// the depth pyramid have arrived and been kept. Null until a frame has
  /// asked for [OcclusionMode.hiZ].
  HiZOcclusion? get debugHiZ => _hiZ;

  /// Readbacks of the luminance target that came back as an error. Diagnostic:
  /// a meter that has stopped hearing from the device holds its last answer,
  /// which looks like a meter that has settled, and this is what tells the
  /// two apart.
  int get debugMeterFailures => _meterFailures;
  int _meterFailures = 0;

  /// Whether a luminance readback has been asked for and not yet answered.
  ///
  /// The meter asks once per answer rather than once per frame. A hardware
  /// backend answers a frame or two after the ask, and on flutter_gpu the
  /// answer is a `toByteData` off a staging texture — a GPU download the
  /// raster thread pays for — so a meter that asked every frame would keep
  /// two or three of those in the air for ever and grow the staging pool to
  /// match. An exposure that adapts over seconds cannot tell the difference
  /// between a reading every frame and one every other frame; a pool that
  /// holds one staging texture instead of three can.
  bool _meterInFlight = false;

  /// Seconds between one `render` and the next, for the adapter's rate.
  ///
  /// Measured here rather than passed in, because `render` takes no clock and
  /// the rate is the one thing in the frame that is about time: the composite
  /// does not care how long the last frame took, the meter's approach does.
  final Stopwatch _sinceLastFrame = Stopwatch();

  /// What the composite last exposed with — see [exposure].
  double _lastExposure = RenderSettings.defaultExposure;

  /// The exposure the last frame was composited with.
  ///
  /// The setting's own number, or the meter's answer while
  /// `RenderSettings.autoExposure` is on. Readable so a HUD can show it and a
  /// test can watch it climb.
  double get exposure => _lastExposure;

  /// Questions [pickPixel] has been asked since the last frame, answered by
  /// the next one.
  final List<_PickRequest> _pendingPicks = <_PickRequest>[];

  /// Which mesh the next frame draws at ([u], [v]) — fractions of the frame
  /// from the top left, so a caller with a widget's local position divides by
  /// the widget's size and need not know the render size.
  ///
  /// **Exact by pixel, and answered by the frame after this call.** The next
  /// [render] draws every visible mesh once more with a stage that writes the
  /// draw's number instead of its colour, reads the one pixel back through
  /// `GraphicsDevice.readback`, and completes this with the node whose number
  /// came back — or null for the clear colour, which is nothing. A hardware
  /// backend answers a frame or two after that render; the software one
  /// answers when the render returns.
  ///
  /// The old way is `Raycaster`, which is still what a game wants: a ray
  /// against bounds needs no frame and answers now. This is for the editor,
  /// where a bounding box is a metre wider than the monster in it and a torch
  /// hangs inside the wall's box, and "what did I click" has to mean what is
  /// on the screen.
  ///
  /// An instanced batch answers as the batch. A masked material — glTF's
  /// `MASK` — is a hole where its alpha falls under the cutoff, in the id
  /// pass as in the picture, so a click through a fence's hole answers with
  /// what is seen through it. A pick asked while no frame follows — a
  /// renderer nobody renders with again — is answered null by [dispose].
  ///
  /// **A blended surface is picked as though it were opaque**, and that is the
  /// one place this parts company with what the eye sees. Glass, a translucent
  /// marker, an additive flash: the id pass draws them like everything else,
  /// so a click on one answers with the surface rather than with the thing
  /// visible through it. Transparency and a hole are different questions —
  /// `MASK` says "there is nothing here", which the pass honours, and `BLEND`
  /// says "there is something here, faintly", which is still something to
  /// click on. A caller that wants the thing behind the glass filters the
  /// answer; the renderer does not guess which of the two was meant.
  ///
  /// **Or with an error.** The frame the question belongs to can fail — a
  /// pass throws, or the graph refuses an application node before any pass
  /// has run — and the question is then completed with that failure rather
  /// than left for ever; so can the device, a frame or two later, when the
  /// copy is refused or a fence never signals. A caller that awaits this from
  /// a pointer handler catches, and treats the error as "nothing there".
  Future<MeshNode?> pickPixel(double u, double v) {
    final request = _PixelPick(u, v);
    _pendingPicks.add(request);
    return request.completer.future;
  }

  /// Which mesh the next frame draws at every pixel: [pickPixel]'s pass, run
  /// for the whole frame and read back whole.
  ///
  /// Answered the way [pickPixel] is — by the frame after this call, when its
  /// readback arrives — and with the same rules about masked, blended and
  /// instanced meshes, since it is the same pass; a frame with both kinds of
  /// question pending draws the ids once. It costs a scene's worth of draws
  /// and a readback of the whole frame, so it is for a tool that has to say
  /// what is on the screen — how much of a wall shows, and what hides a torch
  /// — and not for anything that runs every frame.
  ///
  /// Fails with the frame when the frame fails, and with a [StateError] when
  /// the renderer is disposed before any frame answers: an empty frame would
  /// read as a scene with nothing in it.
  Future<ObjectIdFrame> captureObjectIds() {
    final request = _FramePick();
    _pendingPicks.add(request);
    return request.completer.future;
  }

  /// What the composite exposes with this frame.
  double _exposureFor(RenderSettings settings) => settings.autoExposure.enabled
      ? _autoExposure?.value ?? settings.exposure
      : settings.exposure;

  /// What the composite exposes view [index] with — `gfx-22n`.
  ///
  /// The frame's own exposure unless per-view metering is on and this view has
  /// an adapter, which is what makes the single-view case the case it always
  /// was: one view meters the whole histogram, so its answer and the frame's
  /// are the same number arrived at the same way.
  double _exposureForView(RenderSettings settings, int index) {
    if (!settings.autoExposure.enabled || !settings.autoExposure.perView) {
      return _exposureFor(settings);
    }
    if (index < 0 || index >= _viewExposure.length) {
      return _exposureFor(settings);
    }
    return _viewExposure[index].value;
  }

  /// The look, packed for the composite's uniform block.
  ///
  /// Two vectors rather than one because std140 pads a `vec3` to sixteen bytes
  /// anyway, so seven floats cost the same as eight and the split reads better
  /// on the shader's side: grading in one, the lens and the film in the other.
  Float32List get _compositeLook => _compositeInfo.look;
  Float32List get _compositeLookMore => _compositeInfo.lookMore;

  /// `gfx-24n`'s fifth block: x is the dither amount, y and z the white
  /// balance pair `gfx-27n` added. Allocated once and zero on every frame
  /// that does not ask for any of them.
  Float32List get _compositeOutputEncode => _compositeInfo.outputEncode;

  /// `gfx-27n`'s three ranges. Neutral is (0,0,0) for the lift and (1,1,1)
  /// for the other two, which is what the composite reads as "do nothing".
  Float32List get _compositeLift => _compositeInfo.lift;
  Float32List get _compositeGamma => _compositeInfo.gamma;
  Float32List get _compositeGain => _compositeInfo.gain;

  /// `gfx-76n`'s strength, in x. Neutral is zero, which the composite reads as
  /// a multiplier of exactly one — the same arrangement the occlusion's
  /// strength has, and for the same reason: forty-four goldens go through this
  /// block and "off" has to be a number the shader cancels, not one it nearly
  /// cancels.
  Float32List get _compositeContact => _compositeInfo.contact;

  /// Builds a renderer on [device].
  ///
  /// The backend arrives as a value rather than being reached for, which is the
  /// whole of how a second one will be selected: an application constructs
  /// `GpuRenderBackend.create()` and hands it over. A compile-time choice could
  /// not be faked, and a fake is the only way anything below this line is ever
  /// exercised without a GPU.
  ///
  /// Which shaders it must contain is this package's business and is stated by
  /// name — see [LightingModel.shaderName] and the `require` calls below. Where
  /// those shaders come from, and in what format, is the backend's.
  /// The two fallbacks are what a material without a map samples: white, so
  /// that an untextured surface is its own base colour, and the neutral
  /// tangent-space normal, so that sampling it perturbs nothing and the shader
  /// needs no branch. **Optional, because every application in this repository
  /// passed the same two** — `SolidColorTexture.white` and
  /// `SolidColorTexture.flatNormal`, uploaded on the spot, in a dozen places
  /// including four `main.dart`s that each did it twice. They are still
  /// parameters: a renderer drawing into somebody else's colour space may want
  /// its white somewhere other than 1.0, and that is not a decision this
  /// package can take back. What it can do is stop asking for the answer it
  /// already knows.
  factory Renderer.create({
    required GraphicsDevice device,
    TextureHandle? fallbackAlbedo,
    TextureHandle? fallbackNormal,
    ShaderLibrary? materials,
  }) {
    // Consulted before the backend's, so an application can replace a stage as
    // well as add one — see [LayeredShaderLibrary] for why that order.
    final library = materials == null
        ? device.shaders
        : LayeredShaderLibrary(materials, device.shaders);
    ShaderHandle require(String name) {
      final shader = library[name];
      if (shader == null) {
        throw StateError(
          'The bundle has no "$name" entry. Check the backend\'s bundle '
          'manifest and rebuild it. Each backend package keeps its own '
          'shaders/flutter3d.shaderbundle.json and tool/build_shaders.sh.',
        );
      }
      return shader;
    }

    return Renderer._(
        device: device,
        vertexShader: require('MeshVertex'),
        skinnedVertexShader: require('MeshSkinnedVertex'),
        instancedVertexShader: require('MeshInstancedVertex'),
        lightmappedVertexShader: require('MeshLightmappedVertex'),
        debugLineVertexShader: require('DebugLineVertex'),
        debugLineFragmentShader: require('DebugLine'),
        fullscreenVertexShader: require('FullscreenVertex'),
        bloomThresholdShader: require('BloomThreshold'),
        bloomDownsampleShader: require('BloomDownsample'),
        bloomUpsampleShader: require('BloomUpsample'),
        compositeShader: require('Composite'),
        fxaaShader: require('Fxaa'),
        reflectionShader: require('Reflections'),
        ssaoShader: require('Ssao'),
        contactShadowShader: require('ContactShadow'),
        cameraVelocityShader: require('CameraVelocity'),
        velocityShader: require('Velocity'),
        velocityVertexShader: require('VelocityVertex'),
        velocitySkinnedVertexShader: require('VelocitySkinnedVertex'),
        velocityInstancedVertexShader: require('VelocityInstancedVertex'),
        reactiveShader: require('Reactive'),
        temporalResolveShader: require('TemporalResolve'),
        temporalAccumulateShader: require('TemporalAccumulate'),
        ssaoBlurShader: require('SsaoBlur'),
        lightShaftsShader: require('LightShafts'),
        volumetricFogShader: require('VolumetricFog'),
        volumetricFogUpsampleShader: require('VolumetricFogUpsample'),
        depthOfFieldShader: require('DepthOfField'),
        velocityTileMaxShader: require('VelocityTileMax'),
        velocityNeighborMaxShader: require('VelocityNeighborMax'),
        motionBlurShader: require('MotionBlur'),
        viewportShadeShader: require('ViewportShade'),
        wboitResolveShader: require('WboitResolve'),
        fallbackAlbedo:
            fallbackAlbedo ?? SolidColorTexture.white.upload(device),
        fallbackNormal:
            fallbackNormal ?? SolidColorTexture.flatNormal.upload(device),
        fallbackBlack: SolidColorTexture(
          vm.Vector4(0.0, 0.0, 0.0, 1.0),
        ).upload(device),
        msaaEnabled: device.supportsOffscreenMsaa,
      )
      .._shaders = library
      .._listenForGpuTimings();
  }

  /// What the GPU spent in each graph node's passes, from the last frame a
  /// device reported on — `H2`. A frame or two behind the one being drawn,
  /// because the GPU has to finish a frame before its timestamps can be read.
  Map<String, int> _lastGpuMicros = const <String, int>{};

  void _listenForGpuTimings() {
    if (!device.supportsGpuTimestamps) return;
    device.onGpuTimings((GpuFrameTimings timings) {
      final byNode = <String, int>{};
      for (final pass in timings.passes) {
        byNode[pass.label] = (byNode[pass.label] ?? 0) + pass.micros;
      }
      _lastGpuMicros = byNode;
    });
  }

  // `_fragmentShaderFor` and `_pipelineFor` are declared in
  // `renderer_resources.dart`, next to the caches they read and fill.

  void _ensureTargets(
    int width,
    int height, [
    int? outputWidth,
    int? outputHeight,
  ]) {
    final frameWidth = outputWidth ?? width;
    final frameHeight = outputHeight ?? height;
    if (width == _targetWidth &&
        height == _targetHeight &&
        frameWidth == _frameTargetWidth &&
        frameHeight == _frameTargetHeight &&
        _frameFormat == _frameTargetFormat) {
      return;
    }

    // **Everything below is about to be replaced by assigning over a field.**
    // Where the collector frees a texture that is the whole story; where it
    // does not — WebGL2 — dropping the handle leaks the driver's object, and
    // this method is what a person resizing a window calls over and over. Sent
    // through the frames-in-flight ring rather than freed here, because the
    // frame these were drawn with may still be reading them.
    _destroyAfterFrame(_hdrColor);
    _destroyAfterFrame(_hdrMsaa);
    _destroyAfterFrame(_surfaceColor);
    _destroyAfterFrame(_albedoColor);
    _destroyAfterFrame(_surfaceMsaa);
    _destroyAfterFrame(_reflectionColor);
    _destroyAfterFrame(_depthStencil);
    _destroyAfterFrame(_depthStencilSingle);
    // `R8`'s, which are made on demand rather than here: dropped, and the
    // next frame that asks makes them at the new size.
    _destroyAfterFrame(_wboitAccumulation);
    _destroyAfterFrame(_wboitRevealage);
    _destroyAfterFrame(_wboitDepth);
    _wboitAccumulation = null;
    _wboitRevealage = null;
    _wboitDepth = null;
    // The composited frames are the one set with an owner outside this class:
    // `Texture.asImage` hands one to the widget tree, and the compositor may
    // still be holding the last of them. The ring is what covers that, and it
    // is the same ring the pool's own releases wait in.
    for (final frame in _ldrFrames) {
      _destroyAfterFrame(frame);
    }

    // From the device, not a literal. Four is what these goldens were recorded
    // with, and no two of the three backends answer the same number — Impeller
    // four, WebGL2 whatever its context reports, the software rasteriser one
    // because it does not multisample at all. The engine no longer decides it
    // on their behalf.
    final sampleCount = msaaEnabled ? device.preferredSampleCount : 1;

    // Straight from the device rather than through the pool: these live for as
    // long as the window keeps its size, and the pool is for what is acquired
    // and released within a frame.
    TextureHandle make(
      StorageMode storageMode,
      TextureFormat format, {
      int sampleCount = 1,
    }) => device.createTexture(
      RenderTargetSpec(
        width: width,
        height: height,
        format: format,
        sampleCount: sampleCount,
        storageMode: storageMode,
      ),
    );

    // The scene target is sampled by the composite pass, so it has to be
    // devicePrivate rather than transient — tile memory cannot be read back.
    _hdrColor = make(StorageMode.devicePrivate, hdrFormat);

    // deviceTransient is tile memory: more bandwidth, less memory. Right for
    // intermediates like the MSAA and depth attachments, never read back.
    _hdrMsaa = msaaEnabled
        ? make(StorageMode.deviceTransient, hdrFormat, sampleCount: sampleCount)
        : null;

    // The final image is 8-bit and display-referred; it is what becomes the
    // ui.Image, so there is nothing to gain from more precision here.
    // The old ones are the wrong size now, and the compositor may still be
    // holding one — so they are dropped rather than reused, and the first frame
    // at the new size makes what it needs.
    _ldrFrames.clear();
    _ldrFree.clear();
    _ldrCurrent = null;
    //
    // At the output size, which is the scene's except while temporal
    // anti-aliasing reconstructs a larger picture — `R2`.
    final frameFormat = _frameFormat;
    _makeLdrFrame = () => device.createTexture(
      RenderTargetSpec(
        width: frameWidth,
        height: frameHeight,
        format: frameFormat,
        storageMode: StorageMode.devicePrivate,
      ),
    );

    // The surface buffer: world-space normal and depth, for whatever runs after
    // the scene. Allocated with the rest rather than on demand, because a
    // resize is the only moment any of this is allowed to be reallocated and a
    // buffer that appears mid-session would be the one that is the wrong size.
    _surfaceColor = make(StorageMode.devicePrivate, hdrFormat);
    // `L5`: the albedo buffer, eight bits a channel since it is a colour.
    _albedoColor = make(
      StorageMode.devicePrivate,
      TextureFormat.r8g8b8a8UNormInt,
    );
    _reflectionColor = make(StorageMode.devicePrivate, hdrFormat);

    _surfaceMsaa = msaaEnabled
        ? make(StorageMode.deviceTransient, hdrFormat, sampleCount: sampleCount)
        : null;

    _depthStencil = make(
      StorageMode.deviceTransient,
      device.defaultDepthStencilFormat,
      sampleCount: sampleCount,
    );

    _depthStencilSingle = msaaEnabled
        ? make(StorageMode.deviceTransient, device.defaultDepthStencilFormat)
        : null;

    // Every pooled spec is keyed on size, so after a resize none of them can
    // ever match again.
    targetPool.trim();

    _targetWidth = width;
    _targetHeight = height;
    _frameTargetWidth = frameWidth;
    _frameTargetHeight = frameHeight;
    _frameTargetFormat = _frameFormat;
  }

  /// Index of the first directional light in the packed buffer that asks to
  /// cast, or -1.
  ///
  /// Only a directional light casts today: it is the one whose shadow volume is
  /// a box rather than a frustum or a cube, so it needs neither cascades nor six
  /// faces to be useful.
  int _firstDirectionalIndex() => _directionalIndexIn(lights);

  /// The same question asked of a buffer that is not this renderer's.
  ///
  /// `gfx-41n` needs it: a plan gathers the scene's lights into a buffer of
  /// its own so that asking what a frame *would* do cannot disturb what the
  /// last frame did.
  ///
  /// **[LightNode.castsShadow] is read here, and was not until 0.7.1.** Only
  /// the cube shadows read it, so clearing it on the sun did nothing and the
  /// nearest way to say "not this one" was to turn shadows off for the frame
  /// or mesh by mesh. A light with no node behind it casts: that is
  /// [LightBuffer.useDefaultLight]'s, which has no flag to clear.
  static int _directionalIndexIn(
    LightBuffer buffer, {
    bool castingOnly = true,
  }) {
    for (var i = 0; i < buffer.count; i++) {
      if (castingOnly &&
          i < buffer.packed.length &&
          !buffer.packed[i].castsShadow) {
        continue;
      }
      if (buffer.positions[i * 4 + 3] == ShaderLightType.directional) return i;
    }
    return -1;
  }

  /// Which way the sun lies *from* a surface, or null when nothing directional
  /// lights the scene — `gfx-76n`.
  ///
  /// The buffer holds the direction a light points; a march goes the other way.
  /// Taken from the same buffer and the same index the shadow map's caster comes
  /// from, so a frame cannot march toward one sun and shadow from another.
  static vm.Vector3? _toLightIn(LightBuffer buffer, int index) {
    if (index < 0) return null;
    final at = index * 4;
    final direction = vm.Vector3(
      buffer.directions[at],
      buffer.directions[at + 1],
      buffer.directions[at + 2],
    );
    // A directional light with no direction is not a light this pass can march
    // toward, and normalising a zero vector is how you get a frame of NaN.
    if (direction.length2 == 0.0) return null;
    return -direction.normalized();
  }

  /// Which way the contact shadows march: towards the shadow map's caster when
  /// there is one, so the seam continues the shadow the map drew, and towards
  /// the first directional light otherwise.
  ///
  /// **Not only the caster.** The march reads the surface buffer and no
  /// shadow map, and a sun with `castsShadow` cleared — the cheap setup this
  /// pass exists for, contact shadows without paying for a map — used to
  /// switch the pass off with the map.
  static vm.Vector3? _contactToLightIn(LightBuffer buffer, int caster) =>
      _toLightIn(
        buffer,
        caster >= 0 ? caster : _directionalIndexIn(buffer, castingOnly: false),
      );

  /// Which light the volumetric fog scatters as its sun — `S4`: the shadow
  /// map's caster when there is one, so the air is shadowed by the map it
  /// reads, and the first directional light otherwise, unshadowed.
  static int _airLightIn(LightBuffer buffer, int caster) =>
      caster >= 0 ? caster : _directionalIndexIn(buffer, castingOnly: false);

  /// The colour times the intensity of the light at [index] in [buffer], or
  /// null when there is none — what the light shafts scatter.
  static vm.Vector3? _radianceIn(LightBuffer buffer, int index) {
    if (index < 0) return null;
    final at = index * 4;
    final intensity = buffer.colors[at + 3];
    return vm.Vector3(
      buffer.colors[at] * intensity,
      buffer.colors[at + 1] * intensity,
      buffer.colors[at + 2] * intensity,
    );
  }

  /// Restates this frame's atlas assignment in the slot order [buffer] packed.
  ///
  /// The shader knows a light only as an index into the eight slots it was
  /// handed, so the row table has to be written per packing. `x < 0` is the
  /// shader's own early-out for "no shadow here", which is why every slot is
  /// cleared to it first and only the rows that exist are written.
  void _writeShadowSlots(LightBuffer buffer, Float32List out) {
    out.fillRange(0, out.length, -1.0);
    if (_shadowRowOf.isEmpty) return;
    for (var i = 0; i < buffer.packed.length; i++) {
      final row = _shadowRowOf[buffer.packed[i]];
      if (row == null) continue;
      out[i * 4] = row.toDouble();
      out[i * 4 + 1] = _shadowRowShape[row];
      out[i * 4 + 2] = _shadowRowTangent[row];
    }
  }

  /// The lights one draw is lit by, and the slot table that goes with them.
  ///
  /// When the scene's live lights all fit, every draw in the frame shares the
  /// frame's own buffer and table — the same arrays, not a copy — so a scene
  /// that fits costs exactly what it cost before and packs byte for byte the
  /// same. Only a scene that overflows pays for selection, and it pays per
  /// draw: a night map may carry two hundred torches while each object is told
  /// about the eight that reach it.
  ///
  /// An instanced batch is one draw and therefore gets one list, chosen for the
  /// bounds of the whole batch. For a cluster of props that is right; for a
  /// crowd spread across a map it is not, and the answer there is not a
  /// per-instance list — the shader reads eight slots for the whole draw and
  /// giving each instance its own would be the new shader this deliberately
  /// avoids — but splitting the crowd into batches that are local enough to
  /// share a light list. The same caveat covers a single mesh that spans the
  /// map: a ground plane's bounding sphere touches every torch, so it scores
  /// them all at distance zero and keeps the eight brightest, which is the best
  /// answer a per-draw list can give and a reason to build big ground out of
  /// tiles.
  ({LightBuffer lights, Float32List shadowSlots}) _drawLightsFor({
    required LightBuffer frameLights,
    required Float32List frameShadowSlots,
    required MeshNode node,
    double fadeBand = 0.0,
  }) {
    // **The fast path is what makes `gfx-12n` free when nobody uses it.** A
    // scene whose lights fit and whose lights ask for no channel shares the
    // frame's own arrays, not a copy, and packs byte for byte what it packed
    // before channels existed. Both halves of the condition matter: a
    // channelled light in a scene of three still has to be filtered, and an
    // object on every channel in a scene of two hundred still has to rank.
    final channels = node.lightChannels;
    final channelled =
        frameLights.anyChannelled || channels != LightChannels.all;
    if (frameLights.overflow == 0 && !channelled) {
      return (lights: frameLights, shadowSlots: frameShadowSlots);
    }
    if (frameLights.overflow == 0) {
      _drawLights.gatherMatchingFrom(frameLights, channels);
    } else {
      _drawLights.gatherNearFrom(
        frameLights,
        node.worldBoundsCentre,
        node.worldBoundsRadius,
        channels: channels,
        fadeBand: fadeBand,
      );
    }
    // The frame's table is the world scene's; a contributor scene was handed
    // `_noShadowSlots` and its lights own no rows, so rebuilding from the row
    // map would invent shadows the atlas never drew.
    if (identical(frameShadowSlots, _shadowSlots)) {
      _writeShadowSlots(_drawLights, _drawShadowSlots);
    } else {
      _drawShadowSlots.fillRange(0, _drawShadowSlots.length, -1.0);
    }
    return (lights: _drawLights, shadowSlots: _drawShadowSlots);
  }

  /// The six directions a cube shadow looks in, and the up vector for each.
  ///
  /// Order fixes the atlas layout, so the shader's face selection and this
  /// list are one decision written twice — which is why they are both spelled
  /// out rather than derived: +X, -X, +Y, -Y, +Z, -Z, left to right along the
  /// light's own row of six tiles.
  static final List<(vm.Vector3, vm.Vector3)> _cubeFaces =
      <(vm.Vector3, vm.Vector3)>[
        (vm.Vector3(1.0, 0.0, 0.0), vm.Vector3(0.0, 1.0, 0.0)),
        (vm.Vector3(-1.0, 0.0, 0.0), vm.Vector3(0.0, 1.0, 0.0)),
        (vm.Vector3(0.0, 1.0, 0.0), vm.Vector3(0.0, 0.0, 1.0)),
        (vm.Vector3(0.0, -1.0, 0.0), vm.Vector3(0.0, 0.0, -1.0)),
        (vm.Vector3(0.0, 0.0, 1.0), vm.Vector3(0.0, 1.0, 0.0)),
        (vm.Vector3(0.0, 0.0, -1.0), vm.Vector3(0.0, 1.0, 0.0)),
      ];

  /// Allocates the two cube atlases, or reallocates them when the tile size
  /// changed.
  ///
  /// Hoisted out of [_renderCubeShadow] because the static bake is skipped once
  /// it has run: if the allocation lived inside the pass, a resolution change
  /// would drop the baked walls and only the dynamic call would notice, leaving
  /// the static atlas blank for the rest of the run.
  ///
  /// **The one legal way to drop these two textures.** Every claim anybody
  /// holds about their contents is invalidated here, in one place and in one
  /// step: the tile size, whether the walls are baked, whether either texture
  /// holds defined pixels at all, and both schedulers' memory of what they last
  /// drew. A second route to reallocation would have to repeat all six, and the
  /// one it forgot would be a stale tile that only shows when a light stops
  /// moving.
  ///
  /// Called by both atlas nodes rather than by the frame, and idempotent so
  /// that costs nothing: each of them needs the texture before it can draw, and
  /// neither may assume the other ran. See [_CubeShadowStaticNode].
  void _ensureCubeAtlas(ShadowSettings settings) {
    final tile = settings.cubeResolution.clamp(
      ShadowSettings.minCubeTile,
      ShadowSettings.maxCubeTile,
    );
    if (_cubeShadow != null && _cubeShadowTile == tile) return;
    // A grid of square tiles six faces across and [kShadowedLights] rows down:
    // the face across, the light down.
    // Square because a ninety-degree frustum is square, and any other aspect
    // would stretch one axis of every face.
    final width = tile * 6;
    final height = tile * kShadowedLights;
    final spec = RenderTargetSpec(
      width: width,
      height: height,
      format: hdrFormat,
    );
    // Two atlases at 75 MB each with the default tile, replaced whenever a
    // setting the pass reads changes. Dropping them is a free on one backend
    // and a leak on another — see [_destroyAfterFrame].
    _destroyAfterFrame(_cubeShadowStatic);
    _destroyAfterFrame(_cubeShadow);
    _destroyAfterFrame(_cubeShadowDepth);
    _cubeShadowStatic = device.createTexture(spec);
    _cubeShadow = device.createTexture(spec);
    _cubeShadowDepth = device.createTexture(
      RenderTargetSpec(
        width: width,
        height: height,
        format: device.defaultDepthStencilFormat,
        storageMode: StorageMode.deviceTransient,
      ),
    );
    _cubeShadowTile = tile;
    _staticShadowBaked = false;
    // Belt and braces: the flag above already forces a bake, and a stale key
    // beside a cleared flag is the kind of pair that stops agreeing the moment
    // somebody adds a third reason to redraw.
    _staticBakeKey = null;
    _cubeShadowCleared = false;
    _cubeShadowStaticCleared = false;
    _shadowSlotAllocator.reset();
    _shadowFaceScheduler.reset();
  }

  /// How many point lights may have a cube map at once.
  ///
  /// **Six, and the number is the crypt's.** That level hangs six torches, so at
  /// four rows two of them lit their corner and cast nothing — and which two
  /// changed as the player walked, because the rows go to whatever matters most
  /// from where the camera is. Two torches side by side behaving differently is
  /// the shape a player reads as "the shadows are broken", and they are right:
  /// it is not a subtle difference, it is a shadow that is there and then is
  /// not.
  ///
  /// Six rather than eight because eight is the light budget
  /// ([LightBuffer.maxLights]) and a row for every light in the frame would make
  /// the allocator pointless while costing a third more atlas again. Six covers
  /// the rooms this engine has been asked to draw and leaves the mechanism that
  /// hands rows out doing its job when a level goes further.
  ///
  /// **What it costs is a quarter of what it would have.** The atlas is
  /// `cubeResolution` × 6 by `cubeResolution` × rows; at the 512 that
  /// [ShadowSettings.cubeResolution] now defaults to, six rows is 3072 × 3072 —
  /// 75 MB, against 50 for four. Taken before that split, when a cube tile
  /// inherited the cascade's 1024, the same step would have been 302 MB per
  /// atlas and there are two of them.
  ///
  /// A limit on how many lights are shadowed *at the same moment*, not on how
  /// many a level may hold: [ShadowSlotAllocator] hands the rows to whichever
  /// lights matter most from where the camera is, and takes them back when they
  /// stop mattering. It used to be the first four in scene order, which meant a
  /// level with five torches had one that could never cast a shadow anywhere.
  static const int kShadowedLights = 6;

  Float32List get _cubeFaceMatrices => _pointShadow.faces;

  /// The irradiance field's atlas and how to read it — `L3`. Uploaded when
  /// the scene's field changes identity or version; see `_bindIrradiance`.
  final IrradianceInfoBlock _irradianceInfo = IrradianceInfoBlock();
  IrradianceField? _irradianceField;
  int _irradianceVersion = -1;
  TextureHandle? _irradianceAtlas;
  int _irradianceColumns = 1;
  int _irradianceMomentsTop = 0;

  /// The field being updated on the GPU, when one is — `L4`.
  _IrradianceGpu? _irradianceGpu;
  final ConvolveInfoBlock _convolveInfo = ConvolveInfoBlock();

  /// The texture the lit stages read the irradiance field from this frame:
  /// the GPU-updated atlas when the field is kept current there, the
  /// uploaded bake otherwise, null with no field — `L4`. For tools and tests
  /// that want to look at what the field has become.
  TextureHandle? get irradianceAtlas =>
      _irradianceGpu?.atlas.current ?? _irradianceAtlas;

  /// What a surface facing up, and one facing down, receive from the
  /// environment. Recomputed once a frame — see [_updateAmbient].
  Float32List get _ambientSky => _fragInfo.ambientSky;
  Float32List get _ambientGround => _fragInfo.ambientGround;

  /// Resolves the two ends of the hemispheric ambient for this frame.
  ///
  /// White at both ends unless a sky says otherwise, and that is what keeps
  /// this change invisible until somebody asks for it: `mix(white, white, t)`
  /// is white for every t, so a scene with no sky shades exactly as it did when
  /// ambient was one grey scalar.
  ///
  /// **Built from the gradient rather than from [SkySettings.sample].** Sample
  /// includes the sun disc, and the disc is the one part of a sky that must not
  /// reach ambient: a sun near the zenith would hand every upward-facing
  /// surface the disc's intensity — which is far above white, deliberately —
  /// and the scene would blow out for no reason a reader could see.
  ///
  /// Half the zenith and half the horizon, rather than either alone, because a
  /// hemisphere seen by a flat surface is mostly the band near the horizon and
  /// the strip overhead in roughly equal measure. It is an approximation of an
  /// integral this engine does not compute, and it is named as one rather than
  /// dressed up: proper irradiance is what IBL will bring, and it needs the mip
  /// chains that only just started being built.
  void _updateAmbient(Scene scene, RenderSettings settings) {
    final tint = scene.ambientColor;
    final sky = settings.sky;

    var upX = 1.0, upY = 1.0, upZ = 1.0;
    var downX = 1.0, downY = 1.0, downZ = 1.0;
    if (sky.enabled) {
      final zenith = sky.resolvedZenith;
      final horizon = sky.resolvedHorizon;
      final nadir = sky.resolvedNadir;
      upX = (zenith.x + horizon.x) * 0.5;
      upY = (zenith.y + horizon.y) * 0.5;
      upZ = (zenith.z + horizon.z) * 0.5;
      // Below the horizon a sky is haze, not ground, so this is a stand-in for
      // a bounce nothing here computes. It is dimmer than the upper half, which
      // is the half of the effect that reads.
      downX = (horizon.x + nadir.x) * 0.5;
      downY = (horizon.y + nadir.y) * 0.5;
      downZ = (horizon.z + nadir.z) * 0.5;
    }

    _ambientSky[0] = upX * tint.x;
    _ambientSky[1] = upY * tint.y;
    _ambientSky[2] = upZ * tint.z;
    _ambientGround[0] = downX * tint.x;
    _ambientGround[1] = downY * tint.y;
    _ambientGround[2] = downZ * tint.z;
    // `L8`: the metal-rough models' diffuse lobe rides in the sky colour's
    // spare lane — frame-wide, as this is, and set here rather than in the
    // scene pass so a probe captured before it shades the room the same way.
    _ambientSky[3] = settings.diffuseModel == DiffuseModel.eon ? 1.0 : 0.0;
  }

  /// Per atlas row: xyz the direction a spot aims, w the tangent of half its
  /// frustum — or w negative when the row belongs to a point light.
  ///
  /// Separate from [_cubeLightData] rather than widening it, because that array
  /// is uploaded to the shader as `lights[]` and this is not: the shading reads
  /// a spot's tile through the matrix in `faces[]`, which already carries the
  /// aim. This is what the *pass* needs in order to build that matrix.
  final Float32List _cubeLightAim = Float32List(4 * kShadowedLights);
  Float32List get _cubeLightData => _pointShadow.lights;

  /// One vec4 per light the shading knows about; x is its atlas row or -1.
  final Float32List _shadowSlots = Float32List(4 * LightBuffer.maxLights);

  /// Which atlas row each shadowed light owns, keyed by the light rather than
  /// by its slot.
  ///
  /// A slot index only means something inside one packing, and with per-object
  /// light lists there is a packing per draw. Keyed by the node, the assignment
  /// is stated once for the frame and every packing can look itself up in it.
  final Map<LightNode, int> _shadowRowOf = <LightNode, int>{};

  /// Per row, what a slot needs beside the row number: y the shape (1 for a
  /// spot's single cone-shaped tile, 0 for a cube), z the tangent of half the
  /// frustum the row was drawn through.
  final Float32List _shadowRowShape = Float32List(kShadowedLights);
  final Float32List _shadowRowTangent = Float32List(kShadowedLights);

  /// Repacked once per draw, for scenes that hold more lights than a draw can
  /// carry, with the slot table that belongs to that packing. Hot-loop scratch,
  /// like the uniform staging beside it. See [_drawLightsFor].
  final LightBuffer _drawLights = LightBuffer();
  final Float32List _drawShadowSlots = Float32List(4 * LightBuffer.maxLights);

  /// What a lit contributor binds its lights through — `N6`. One for the
  /// renderer, pointed at each view's lights as its contributors run.
  late final _ContributorLights _contributorLights = _ContributorLights(this);

  Float32List get _pointShadowParams => _pointShadow.params;
  Float32List get _pointShadowParams2 => _pointShadow.params2;

  /// x: whether this backend stores the cube atlas bottom-up. See surface.glsl.
  Float32List get _pointShadowParams3 => _pointShadow.params3;

  /// Number of atlas rows in use, or -1 when none are.
  int _cubeShadowLight = -1;

  final vm.Vector3 _cubePosition = vm.Vector3.zero();

  final ShadowSlotAllocator _shadowSlotAllocator = ShadowSlotAllocator(
    slotCount: kShadowedLights,
  );
  final ShadowFaceScheduler _shadowFaceScheduler = ShadowFaceScheduler(
    tileCount: kShadowedLights * 6,
  );
  final List<ShadowCandidate> _shadowCandidates = <ShadowCandidate>[];
  final vm.Vector3 _shadowEye = vm.Vector3.zero();
  final vm.Vector3 _shadowAim = vm.Vector3.zero();
  final vm.Vector3 _spotAim = vm.Vector3.zero();
  final vm.Vector3 _spotUp = vm.Vector3.zero();

  /// How much wider than its cone a spot's shadow frustum is drawn.
  ///
  /// The shader bails with "lit" for a fragment that projects outside its tile,
  /// which is right for a cube face — a neighbouring face holds that direction
  /// — and is the last thing wanted at the rim of a cone, where outside the
  /// tile is simply where the light stops.
  ///
  /// Fitted exactly, a fragment at the very edge of the cone lands at |ndc| of
  /// one, and the test is `> 1.0`, so in exact arithmetic it does not fire.
  /// This is insurance against that arithmetic being float32 in one place and
  /// float64 in another, on a ring where the cone's own falloff has nearly
  /// closed anyway.
  ///
  /// **Stated honestly: no test here tells 1.06 from 1.0.** The mutation was
  /// applied and `spot_shadow_test.dart` stayed green. It is kept because a few
  /// per cent of angle costs a few per cent of texel density, and the failure
  /// it guards against would be a thin bright ring that reads as a shader bug
  /// rather than as a fitting one.
  static const double _kSpotFrustumMargin = 1.06;

  /// The signature of a tile that holds nothing and is meant to keep holding
  /// nothing: the five columns beside a spot's own.
  ///
  /// A constant rather than null, because null means "no row here at all" and
  /// leaves whatever the last owner drew. Any value would do as long as it
  /// never collides with a real one; this one is far from anything
  /// [_bakeKeyFor] produces from centimetres and thousandths.
  static const int _kBlankTileSignature = 0x5B1A4E;

  /// Builds this frame's list of lights asking for an atlas row.
  ///
  /// Relevance is measured from the view drawn first — the main camera. A row
  /// chosen for a rear-view mirror would be a row spent on a shadow nobody is
  /// looking at.
  /// [into] is where the candidates land — this renderer's own list for a
  /// frame, and a list of its own for `gfx-41n`'s plan, so asking what a frame
  /// would do cannot disturb the scratch the last frame left.
  void _collectShadowCandidates(
    Scene scene,
    List<RenderView> views, {
    List<ShadowCandidate>? into,
  }) {
    final candidates = into ?? _shadowCandidates;
    candidates.clear();
    if (views.isEmpty) return;

    var primary = views.first;
    for (final view in views) {
      if (view.priority < primary.priority) primary = view;
    }
    primary.camera.readWorldPosition(_shadowEye);

    for (final light in scene.lights) {
      final spot = light.type == LightType.spot;
      if (light.type != LightType.point && !spot) continue;
      if (!light.castsShadow) continue;
      if (!light.visibleInHierarchy || light.intensity <= 0.0) continue;

      light.readWorldPosition(_cubePosition);
      final range = light.range > 0.0 ? light.range : 20.0;
      final distance = _cubePosition.distanceTo(_shadowEye);

      // Angular size: how large the lit sphere looks from the camera. The same
      // rule PlayCanvas sorts by, and the reason a torch at the far end of a
      // corridor yields to one in this room. Clamped away from zero so a light
      // the camera is standing inside scores high rather than dividing by it.
      var priority = range / math.max(distance, 0.05);

      // A cone lights a fraction of what a sphere of the same range does, and
      // the two compete for the same rows. Unscaled, a tight downlight
      // outscores the point light filling the room, because both are measured
      // by a range neither spends the same way. `sin` of the half-angle is the
      // radius of the lit disc at unit distance — the same "how much of the
      // frame does this cover" the rest of the expression asks — and it is 1
      // for a hemisphere, which keeps a wide-open spot competing as a point.
      if (spot) {
        priority *= math.sin(light.outerConeAngle.clamp(0.0, math.pi / 2));
      }

      light.readDirection(_shadowAim);
      candidates.add(
        ShadowCandidate(
          light: light,
          priority: priority,
          bakeKey: _bakeKeyFor(
            _cubePosition,
            range,
            spot ? _shadowAim : null,
            spot ? light.outerConeAngle : 0.0,
          ),
        ),
      );
    }
  }

  /// What each tile of the dynamic atlas would hold if it were drawn now.
  ///
  /// One entry per tile, `slot * 6 + face`, or null where the row is unused.
  /// Two tiles with the same signature would draw the same picture, which is
  /// what lets [ShadowFaceScheduler] leave one alone.
  ///
  /// Conservative on purpose: a caster is folded into every face whose ninety
  /// degree frustum its bounding sphere might touch, widened by the sphere's
  /// angular radius. Naming one face too many costs a redraw of something that
  /// did not change; naming one too few leaves a stale shadow on screen, and
  /// those are not the same mistake.
  List<int?> _computeFaceSignatures(
    Scene scene,
    int slotCount,
    ShadowSettings settings,
  ) {
    const int faces = 6;
    // The half-angle from a face's axis to its corner: a ninety degree square
    // frustum reaches 45 degrees at the edge and atan(sqrt(2)) at the corner.
    const double faceHalfAngle = 0.9553166;

    _faceSignatures.length = kShadowedLights * faces;
    for (var i = 0; i < _faceSignatures.length; i++) {
      _faceSignatures[i] = null;
    }

    for (var slot = 0; slot < slotCount; slot++) {
      final range = _cubeLightData[slot * 4 + 3];
      if (range <= 0.0) continue;
      _cubePosition.setValues(
        _cubeLightData[slot * 4],
        _cubeLightData[slot * 4 + 1],
        _cubeLightData[slot * 4 + 2],
      );
      final spotTanHalf = _cubeLightAim[slot * 4 + 3];
      final isSpot = spotTanHalf > 0.0;
      _shadowAim.setValues(
        _cubeLightAim[slot * 4],
        _cubeLightAim[slot * 4 + 1],
        _cubeLightAim[slot * 4 + 2],
      );

      // The light's own placement is part of every one of its faces: move the
      // light and every face of that row draws something different. So does
      // the settings' choice of faces and padding: only the resolution resets
      // the atlas, and a `casterFaces` changed at runtime otherwise left every
      // face of a still scene as it was drawn before.
      final base = _mix(
        isSpot
            ? _bakeKeyFor(_cubePosition, range, _shadowAim, spotTanHalf)
            : _bakeKeyFor(_cubePosition, range),
        StaticBakeKey.of(settings).hashCode,
      );
      for (var face = 0; face < faces; face++) {
        // A spot uses one column, and the five beside it are not "unused" in
        // the sense that a whole empty row is: they hold whatever the previous
        // owner of this row drew there. Null would mean "never redraw" and the
        // stale picture would stay — invisible in the shading, which never
        // looks at them, and plainly visible in `showShadowMap`, which is the
        // one view anybody debugs this subsystem through. A constant redraws
        // them once, blank, and then leaves them alone for as long as the spot
        // holds the row.
        _faceSignatures[slot * faces + face] = isSpot && face > 0
            ? _kBlankTileSignature
            : base;
      }

      for (final node in scene.meshes) {
        if (!node.visibleInHierarchy || !node.castsShadow) continue;
        if (node.shadowIsStatic) continue;
        final mesh = node.mesh;
        if (mesh is! DrawableGeometry || mesh.indexCount == 0) continue;

        final radius = node.worldBoundsRadius;
        _shadowToCaster
          ..setFrom(node.worldBoundsCentre)
          ..sub(_cubePosition);
        final distance = _shadowToCaster.length;
        if (distance - radius > range) continue;

        final hash = _casterKeyFor(node);
        // How many columns this row's shape can put a caster in, and which
        // directions they point. One for a spot, six for a cube.
        final drawn = isSpot ? 1 : faces;
        if (distance <= radius || distance < 1e-6) {
          // The light is inside the caster's sphere, so it may show on any
          // face it has. No direction to test against.
          for (var face = 0; face < drawn; face++) {
            final at = slot * faces + face;
            _faceSignatures[at] = _mix(_faceSignatures[at]!, hash);
          }
          continue;
        }

        _shadowToCaster.scale(1.0 / distance);
        // The half-angle from the axis to the corner of the tile. A ninety
        // degree square frustum reaches atan(sqrt(2)); a cone drawn through a
        // square tile reaches atan(tan θ · sqrt 2), which is the same formula
        // with the cube's `tan 45° = 1` written out.
        final cornerAngle = isSpot
            ? math.atan(spotTanHalf * math.sqrt2)
            : faceHalfAngle;
        final limit =
            cornerAngle + math.asin((radius / distance).clamp(0.0, 1.0));
        final cosLimit = limit >= math.pi ? -1.0 : math.cos(limit);
        for (var face = 0; face < drawn; face++) {
          final aim = isSpot ? _shadowAim : _cubeFaces[face].$1;
          if (_shadowToCaster.dot(aim) < cosLimit) continue;
          final at = slot * faces + face;
          _faceSignatures[at] = _mix(_faceSignatures[at]!, hash);
        }
      }
    }
    return _faceSignatures;
  }

  /// A caster's contribution to a signature: which node, and where it is.
  ///
  /// The whole world matrix, not just the position — the spinning pickup that
  /// forced the static/dynamic split in the first place changes its silhouette
  /// without moving its centre, and a signature that missed that would freeze
  /// its shadow in one pose.
  ///
  /// And the pose on top of that for a skinned one, because the same argument
  /// applies twice over: a character walking on the spot keeps its world matrix
  /// exactly where it was and changes its silhouette on every frame. The pose
  /// stamp is a sum of globally monotonic version numbers, so it costs one read
  /// rather than sixty-four matrices hashed, and it cannot repeat a value it
  /// has already had.
  static int _casterKeyFor(MeshNode node) {
    var hash = identityHashCode(node);
    final m = node.worldMatrix.storage;
    for (var i = 0; i < 16; i++) {
      hash = _mix(hash, (m[i] * 1000.0).round());
    }
    final skeleton = node.skeleton;
    if (skeleton != null) hash = _mix(hash, skeleton.poseVersion);
    // Which faces it records, for the same reason as the pose: a node that
    // starts casting from both sides changes the face without moving.
    hash = _mix(hash, node.castsShadowFromEveryFace ? 1 : 0);
    // And what it is made of: a swapped mesh, a changed expression, or an
    // instance moved inside a batch changes the silhouette with the node's own
    // matrix standing still.
    hash = _mix(hash, identityHashCode(node.mesh));
    hash = _mix(hash, node.morph?.version ?? 0);
    if (node is InstancedMeshNode) hash = _mix(hash, node.dataVersion);
    return hash;
  }

  static int _mix(int hash, int value) => (hash * 31 + value) & 0x3FFFFFFF;

  final List<int?> _faceSignatures = <int?>[];
  final vm.Vector3 _shadowToCaster = vm.Vector3.zero();

  /// The frame, ordered by what each pass declares.
  ///
  /// Built per frame because the set depends on settings and on what the
  /// application registered, and because a node holds this frame's arguments.
  ///
  /// The frame asks for one thing, the finished image, and everything that runs
  /// is what that turned out to need. Bloom switched off is a node the graph
  /// culls on its way back from the output, not a branch anybody wrote — and
  /// the same is now true of every shadow pass, which run because the scene
  /// said it would sample what they produce.
  ///
  /// **Nothing is external any more.** Every name this frame uses is written by
  /// a node registered here, which is what the migration was for: the last two
  /// were the cube atlases, and [FrameGraph.addExternal] now has no caller in
  /// the engine at all.
  ///
  /// Registration order is the version chain, so it is the order the frame used
  /// to be written in: the shadow passes, the scene, the application's overlays,
  /// reflections, bloom, the composite. What the graph derives is the *run*
  /// order, and it derives it from the reads and writes rather than from this
  /// list — but two passes with no dependency between them keep the order they
  /// were registered in, which is what makes the frame reproducible enough to
  /// hold a golden against.
  CompiledFrameGraph _compileFrameGraph(
    RenderView view,
    RenderSettings s, {
    required _CubeShadowStaticNode cubeStatic,
    required _CubeShadowNode cube,
    required _ShadowMapNode shadow,
    required List<_ReflectionProbeNode> probes,
    required _IrradianceUpdateNode irradiance,
    required _SceneNode scene,
    required _BloomNode bloom,
    required _CompositeNode composite,
    required _LuminanceNode luminance,
    required _ObjectIdNode objectIds,
    required int viewCount,
    required vm.Vector3? sunToLight,
    required vm.Vector3? sunRadiance,
    required vm.Vector3? contactToLight,
    required vm.Vector3? fogToLight,
    required vm.Vector3? fogRadiance,
  }) {
    final graph = FrameGraph()
      // The atlas before the directional map, which is the order they were
      // submitted in before either was a node. Nothing derives it — they write
      // different textures and neither reads the other — so registration order
      // decides.
      //
      // **And it does not matter.** Registering the directional map first and
      // running the whole suite gives all twenty-seven goldens byte-identical.
      // So this is the old order kept because there is no reason to change it,
      // not an ordering anything depends on; a reader who needs to move one of
      // these is not walking into a trap. The paragraph that used to hedge here
      // was replaced by the run.
      //
      // The static bake first, because that is the order the frame checked the
      // two gates in when it ran them by hand: the bake, then the schedule.
      //
      // All four are registered whether or not they have anything to draw, for
      // the reason bloom is: a name has to be *known* for a read of it to
      // compile. Unregistering one when shadows are off would make the scene's
      // optional read conditional too, which moves the branch rather than
      // deleting it.
      ..addNode(cubeStatic)
      ..addNode(cube)
      ..addNode(shadow)
      // `S2`: after the map it is made of and before anything lit reads it.
      // Active only for the `evsm` filter, and refused as unsupported on a
      // device that cannot filter the moments.
      ..addNode(_ShadowMomentsNode(this, s.shadows));

    // After the shadows, which a probe's capture samples, and before the
    // scene, which samples the probe. Both orderings are derived from reads —
    // a probe optionally reads the three maps and the scene optionally reads
    // every probe — so this is the version chain in the order it is read.
    for (final probe in probes) {
      graph.addNode(probe);
    }
    // `L4`: beside the probes, for their reason — it draws the lit scene and
    // the scene reads what it writes.
    graph.addNode(irradiance);
    graph
      ..addNode(scene)
      // After the scene, whose render list it builds and sorts again the same
      // way, and before anything else: it reads nothing and writes a name
      // nothing else reads, so its place in the chain is nobody's concern,
      // and inactive it is culled.
      ..addNode(objectIds);

    for (final node in nodes.of(FramePhase.overlay)) {
      graph.addNode(node);
    }
    // Registered whether or not it is switched on, for the reason bloom and
    // the occlusion are: a name has to be known for a read of it to compile,
    // and a node left out when its setting is off cannot be reported on.
    // `gfx-38n` — this was the last post node still registered inside an `if`.
    graph.addNode(_ReflectionsNode(this, view, s));
    // After reflections and before bloom: the meter reads the scene as the
    // composite will, glow not yet added. Registered whether or not it is on,
    // for the reason every other node is — a name has to be known — and
    // culled when it is off.
    graph.addNode(luminance);
    // `C3`: beside the meter, for its reason — a small target read back, a
    // frame output while it is on, culled when it is off. After the scene,
    // whose surface buffer it reduces.
    final depthPyramid = _DepthPyramidNode(this, view, s, viewCount);
    graph.addNode(depthPyramid);
    // Before bloom, because the composite reads both and the registration order
    // is the version chain. Registered whether or not it is switched on, for
    // the reason bloom is: a name has to be known for a read of it to compile,
    // and the composite reads the occlusion.
    graph.addNode(_SsaoNode(this, view, s));
    // `gfx-32n`. A link in the occlusion chain rather than a second producer:
    // it reads `ao` and writes the next version of it, so with the blur off
    // the node is inactive, consumes no version, and the composite binds what
    // the occlusion pass left — the version-skip the graph already does for
    // every other optional link.
    graph.addNode(_SsaoBlurNode(this, s));
    // `gfx-76n`, beside the occlusion rather than in it: the composite
    // multiplies both into the ambient term, but each has its own strength, so
    // either can be off without the other having to be. Registration order does
    // not matter here — it writes a name nothing else writes — and this is
    // simply where the pass it belongs next to is.
    graph.addNode(_ContactShadowNode(this, view, s, contactToLight));
    // `R1`: the motion of every pixel, for the temporal resolve. Before any
    // reader of it, which is all registration order has to promise here.
    graph
      ..addNode(_CameraVelocityNode(this, view, s))
      // And the nodes that moved, over it: the next version of the same
      // resource, so registration order is what puts them on top.
      ..addNode(_ObjectVelocityNode(this, view, s, composite._scene))
      // `R4`: what blends, marked over both for the resolve to trust less.
      ..addNode(_ReactiveNode(this, view, s, composite._scene))
      // `R3`: the two effects that march with noise, each carried into a
      // history of its own. After the velocity, which they reproject by, and
      // before anything reads them: the composite takes the last version.
      ..addNode(
        _AccumulateNode(this, view, s, FrameResourceIds.ao, 'ssao history'),
      )
      ..addNode(
        _AccumulateNode(
          this,
          view,
          s,
          FrameResourceIds.contactShadow,
          'contact shadow history',
        ),
      );
    // `gfx-33n`. After the occlusion and before bloom: a shaft is light in
    // the air, so it should glow the way any other light does. It is not a
    // surface, and the occlusion should have nothing to say about it — but
    // the composite multiplies the occlusion into this whole colour, shafts
    // included, so a crease darkens the air in front of it too. A known
    // compromise rather than a claim: separating them needs the in-scatter as
    // a resource of its own, which would also take it out of bloom and focus.
    // `S4`. Before the shafts, beside them in what it reads: the air dims
    // the scene behind it and adds its own light, and the shafts, when both
    // are on, add theirs to that rather than being dimmed by a fog that has
    // already scattered the same sun.
    graph.addNode(_VolumetricFogNode(this, view, s, fogToLight, fogRadiance));
    graph.addNode(_LightShaftsNode(this, view, s, sunToLight, sunRadiance));
    // `gfx-34n`. After the shafts, because a lens is in front of everything
    // the scene emits and light in the air defocuses exactly as the geometry
    // behind it does; before bloom, because a glow is what the sensor does
    // with light that has already been through the lens.
    graph.addNode(_DepthOfFieldNode(this, s));
    // `R6`. After the lens, whose light the exposure smears, and before the
    // resolve, which blends the smeared frames as it would sharp ones.
    graph.addNode(_MotionBlurNode(this, s));
    // Then bloom, so it reads the scene as everything before it left it — the
    // registration order *is* the version chain — and the composite last, so it
    // reads the end of that chain and the glow taken from it.
    //
    // Bloom is registered whether or not it is switched on, which is not the
    // `if` this step removed. A name has to be *known* for a read of it to
    // compile, and the composite reads the glow; leaving the node out when the
    // setting is off would make that read conditional too, which is the branch
    // moved rather than deleted. Registered and inactive, nothing produces the
    // glow, the graph culls the node, and the optional read comes back null.
    final fxaa = _FxaaNode(
      this,
      s.antiAlias,
      upscaleSharpen: _upscales(s) ? s.spatialUpscale.sharpen : 0.0,
    );
    // `R5`: after the composite and before the sharpening, inactive (and so
    // culled) unless the frame is upscaled.
    final easu = _EasuNode(this, s, fxaa);
    final shade = _ViewportShadeNode(this, view, s);
    // `R2`: after everything that reads the scene's own buffers and before
    // bloom, so the glow is taken from the resolved picture and the
    // screen-space effects work at the scene's size.
    final resolve = _TemporalResolveNode(this, view, s);
    graph
      ..addNode(resolve)
      ..addNode(_LocalExposureNode(this, s))
      ..addNode(bloom)
      ..addNode(composite)
      ..addNode(easu)
      // And the smoothing after the composite, which is what lets it read a
      // finished picture — `gfx-04n`. Registered whether or not it is on, for
      // the same reason bloom is: registration order is the version chain, and
      // an inactive node is culled rather than branched around.
      ..addNode(fxaa)
      // `gfx-43n`/`44n`/`45n`, last: a mode here is about the finished
      // picture, so it goes after the tone map and after the edges are
      // smoothed. Before the antialias it would have had its own outline
      // blurred, which is the one thing an outline must not be.
      ..addNode(shade);

    // After the composite, which is the whole of what [FramePhase.present]
    // means: registration order is the version chain, so a node here reads the
    // version the composite wrote and produces the next one. Nothing about the
    // node changes between the two phases — it is where it is registered that
    // decides what it sees.
    final present = nodes.of(FramePhase.present).toList();
    for (final node in present) {
      graph.addNode(node);
    }

    // `R2`: everything after the resolve works on the picture it
    // reconstructed, at the size that was asked for.
    // `R5`: with the spatial upscale, everything after it.
    _outputSized = s.antiAlias.temporal.enabled
        ? <FrameGraphNode>{resolve, bloom, composite, fxaa, shade, ...present}
        : _upscales(s)
        ? <FrameGraphNode>{easu, fxaa, shade, ...present}
        : const <FrameGraphNode>{};

    return graph.compile(
      disabled: s.disabledPasses,
      outputs: <ResourceId>[
        FrameResourceIds.frame,
        // An application that asked for the surface buffer is a consumer no node
        // declares, so it is a frame output. Without this, `surfaceBuffer` on its
        // own would leave the buffer unread, the scene would not attach it, and
        // the application would read whatever the texture held last.
        // `gfx-50n` adds the second half of that condition, and it is the one
        // place the device has to be asked outside a node. An output is a
        // consumer the graph cannot see, so naming the buffer here makes the
        // scene pass attach it — on a device that opens one attachment that
        // is the pass that aborts. A caller asking for the buffer on such a
        // device gets a frame without one, which is the same "nobody filled
        // it" the flag has always had to handle.
        if (s.surfaceBuffer && device.maxColorAttachments > 1)
          FrameResourceIds.surfaceBuffer,
        // Both read back rather than read by a node, which is a consumer the
        // graph cannot see, so both are outputs while their node is active or
        // the node is culled for producing something nobody wants.
        if (luminance.isActive) FrameResourceIds.luminance,
        if (depthPyramid.isActive) FrameResourceIds.depthPyramid,
        if (objectIds.isActive) FrameResourceIds.objectIds,
      ],
    );
  }

  /// A signature of what a static bake of this light would capture.
  ///
  /// Quantised to a centimetre, because a light that drifts by a hair has not
  /// invalidated its view of the walls and re-baking on floating-point noise
  /// would mean re-baking every frame — which is the whole cost the split
  /// exists to avoid.
  ///
  /// [aim] and [coneAngle] are what a spot light adds, and leaving them out is
  /// the trap this signature has that a point light's has not: a cube sees in
  /// every direction, so where it *looks* is not part of what it captures — but
  /// a spot that only turns keeps its position and its range exactly, and a key
  /// built from those two alone never changes. The bake would then hold the
  /// walls as they looked through the old aim, for as long as the level runs,
  /// and nothing would report it. Null for a point light, so the key it
  /// produces is bit-identical to the one it produced before spots existed.
  static int _bakeKeyFor(
    vm.Vector3 position,
    double range, [
    vm.Vector3? aim,
    double coneAngle = 0.0,
  ]) {
    var hash = 17;
    for (final value in <double>[position.x, position.y, position.z, range]) {
      hash = hash * 31 + (value * 100.0).round();
    }
    if (aim != null) {
      // A thousandth rather than the centimetre above: this is a unit vector,
      // so its components are fractions, and a hundredth would call a five
      // degree turn no turn at all.
      for (final value in <double>[aim.x, aim.y, aim.z, coneAngle]) {
        hash = hash * 31 + (value * 1000.0).round();
      }
    }
    return hash;
  }

  PipelineHandle? _cubeShadowPipeline;

  /// The same fragment stage paired with the skinned vertex one.
  ///
  /// A pipeline of its own rather than a reuse of [_skinnedShadowPipeline],
  /// and the difference is the fragment half: the cascade pass records clip
  /// depth through `ShadowDepth`, this one records radial distance through
  /// `ShadowDistance`, and a pipeline is the pair. The uniform layout either
  /// stage reads is identical, which is why nothing else about the skinned
  /// path changes between the two.
  PipelineHandle? _skinnedCubeShadowPipeline;
  PipelineHandle? _instancedCubeShadowPipeline;
  PipelineHandle? _cubeShadowResetPipeline;

  /// Whether each atlas has been cleared since it was allocated.
  bool _cubeShadowCleared = false;
  bool _cubeShadowStaticCleared = false;
  TextureHandle? _cubeShadow;
  TextureHandle? _cubeShadowStatic;

  /// The depth buffer both cube atlases are drawn with. Owned for the reason
  /// [_shadowDepth] is owned.
  TextureHandle? _cubeShadowDepth;
  bool _staticShadowBaked = false;

  /// The settings the static bake was drawn with, or null before the first one.
  ///
  /// **A bake that outlives the settings that made it is a picture of a scene
  /// nobody asked for.** The static half of the cube atlas is drawn once and
  /// kept for as long as the rows do not change hands — which is the whole
  /// reason it is affordable — and until this field existed, "the rows did not
  /// change" was the *only* thing that could make it redraw. Change which side
  /// of a caster is recorded, or how far the volume is padded, and the atlas
  /// went on holding what the previous setting produced, silently, for the rest
  /// of the run.
  ///
  /// Found by measurement rather than by reading: two frames drawn with
  /// opposite `casterFaces` came back identical to the pixel — 419 pixels
  /// changed against a no-shadow frame in both, the same 419 — which is not a
  /// setting that does nothing, it is a setting that never arrived.
  ///
  /// What is *not* here is as deliberate as what is: bias, normal offset,
  /// softness and strength are all read at lookup time, so changing one of them
  /// needs no redraw. Only what the pass itself uses belongs in this key.
  StaticBakeKey? _staticBakeKey;

  /// The value of `Scene.staticShadowGeneration` the standing bake was drawn
  /// at, so a static caster that changed how it casts redraws the walls it is
  /// in. The key above answers the same question about the settings.
  int _staticBakeGeneration = 0;

  /// Which faces each static caster recorded in the standing bake, hashed —
  /// the one thing about a static caster that a material can change without
  /// the node or the generation knowing.
  int _staticBakeFaces = 0;

  int _cubeShadowTile = 0;
  final vm.Matrix4 _cubeMatrix = vm.Matrix4.identity();

  /// [_cubeMatrix] in the backend's clip space, for drawing a face with.
  final vm.Matrix4 _cubeDrawMatrix = vm.Matrix4.identity();
  Float32List get _cubeLight => _shadowLight.light;

  /// This frame's light rows, or null while the scene fits in eight slots —
  /// `gfx-74n`. See `renderer_light_list.dart`.
  TextureHandle? _lightListTexture;
  int _lightListRows = 0;

  /// `L6`: the cells of the view being drawn, and whether its draws read
  /// them. Set per view in the scene pass and cleared after it, so a pass
  /// with another camera — a probe's — never reads a view's cells.
  final LightClusters _lightClusters = LightClusters();
  bool _clustersActive = false;

  /// Where the cells' headers and entries start in [_lightListTexture].
  int _clusterHeaderRow = 0;
  int _clusterEntryRow = 0;

  /// `S4`: the light list the view's cells were written into, and its row
  /// count, kept past the scene pass for the fog's march — which runs after
  /// [_clustersActive] is cleared, and after later passes may have rebuilt
  /// the list without cells. Null when the fog is off or the view drew none.
  TextureHandle? _fogCells;
  int _fogCellRows = 0;

  /// The rows [_lightListTexture] was last uploaded with, compared against
  /// this frame's rather than trusting `SceneNode.changeEpoch`: a light's
  /// colour, intensity, range and cone are plain fields that advance no epoch,
  /// so a torch that flickers without moving kept its first frame's row.
  Float32List _lightListUploaded = Float32List(0);

  /// Where this frame's rows are written before they are compared. Grown,
  /// never shrunk, so a steady scene allocates nothing.
  Float32List _lightListScratch = Float32List(0);

  /// Staging for the per-draw list, beside every other uniform this renderer
  /// writes: arrays reused rather than allocated per draw.
  Float32List get _lightListParams => _lightListInfo.list;
  Float32List get _lightListIndices => _lightListInfo.indices;
  Float32List get _lightListScales => _lightListInfo.scales;

  /// Staging for the contact shadow's block — `gfx-76n`.
  Float32List get _contactParams => _contactShadowInfo.params;
  Float32List get _contactCamera => _contactShadowInfo.camera;
  Float32List get _contactForward => _contactShadowInfo.forward;
  Float32List get _contactLight => _contactShadowInfo.toLight;

  /// The capture being filled, or null — `gfx-70n`.
  FrameCaptureBuilder? _capture;

  /// Records the next frame pass by pass, with the pixels each one wrote.
  ///
  /// **A one-shot rather than a setting**, because that is what a capture is:
  /// something is wrong now, and the readback of every pass's output is far too
  /// expensive to leave on. The returned future answers when the frame's
  /// readbacks have, which on a hardware backend is a frame or two later.
  ///
  /// ```dart
  /// final capture = renderer.captureNextFrame();
  /// renderer.render(/* … */);
  /// final frame = await capture;
  /// print(frame.firstBlack('hdr colour')?.name);
  /// ```
  ///
  /// Asking twice before a frame runs replaces the first request: there is one
  /// next frame.
  Future<FrameCapture> captureNextFrame() {
    final completer = Completer<FrameCapture>();
    _captureWanted = completer;
    return completer.future;
  }

  Completer<FrameCapture>? _captureWanted;

  /// Hands [wanted] the capture this frame built, and clears the builder.
  ///
  /// Called on both ways out of the graph loop, because a frame that threw is
  /// exactly the frame somebody captured.
  void _completeCapture(Completer<FrameCapture>? wanted) {
    final builder = _capture;
    _capture = null;
    if (wanted == null || wanted.isCompleted) return;
    if (builder == null) {
      wanted.completeError(
        StateError('The frame ran without building a capture.'),
      );
      return;
    }
    wanted.complete(builder.build());
  }

  /// What each tile of the directional atlas currently holds, as the key
  /// that drew it — `gfx-68n`, per cascade since `S1`. Null until a first
  /// pass, and a null entry is a tile that has to be drawn.
  final List<int?> _directionalBaked = <int?>[null, null, null];

  /// Whether a frame with [settings] runs the spatial upscale — `R5`: asked
  /// for, below full size, no temporal resolve, and a bundle with the stage.
  bool _upscales(RenderSettings settings) =>
      SpatialUpscaleSettings.runsFor(settings) && shaders['Easu'] != null;

  /// What each tile of [_shadowMapStatic] holds, as the key that drew it.
  final List<int?> _directionalStaticBaked = <int?>[null, null, null];

  /// The copy from the static atlas into the frame's — `S1`.
  PipelineHandle? _shadowCopyPipeline;
  final ShadowCopyInfoBlock _shadowCopyInfo = ShadowCopyInfoBlock();
  final EvsmFilterInfoBlock _evsmFilterInfo = EvsmFilterInfoBlock();

  /// One reusable batch per mesh-and-material pair — `gfx-67n`.
  ///
  /// Held across frames on purpose: a scene whose runs are the same every frame
  /// refills the same buffers rather than allocating a node and a typed list per
  /// run per frame, which would cost more than the draw calls it saves.
  final Map<_BatchKey, InstancedMeshNode> _batchPool =
      <_BatchKey, InstancedMeshNode>{};

  /// The pool entries some view drew with this frame. What the previous frame
  /// did not use is dropped at the top of the next, so a mesh and material
  /// that left the scene — or a scene with batching switched off — stop being
  /// held by the pool.
  final Set<_BatchKey> _batchesUsed = <_BatchKey>{};

  /// How many individual draws the last frame's batching replaced.
  ///
  /// The reading the row is about: a hundred identical meshes drawn in one call
  /// and a hundred drawn in a hundred look the same, so the saving needs a
  /// number. Reset at the top of each frame.
  int _batchedDraws = 0;

  /// The volume of the cube face currently being filled — `gfx-63n`.
  ///
  /// One object reused across faces rather than one per face: there are up to
  /// thirty-six of them in a frame, and a `Frustum` is six planes with a vector
  /// each.
  final vm.Frustum _faceFrustum = vm.Frustum();

  /// How far this camera sees, for dividing between cascades.
  ///
  /// An orthographic camera has no far distance worth splitting by, and a
  /// camera with a far plane at infinity would put the first split at infinity
  /// too, so both fall back to something a level-sized scene can use.
  ///
  /// Stated as "which projections have no useful far plane" rather than as
  /// "which projection is the perspective one", which is what it used to ask.
  /// The difference shows on a projection this engine did not have when the
  /// question was written: an off-axis frustum has a far plane like any other,
  /// and under the old test it was handed 200 metres instead — cascades split
  /// for a scene of a size nobody had asked for.
  static double _cameraFar(CameraNode camera) {
    final projection = camera.projection;
    if (projection is OrthographicProjection || !projection.far.isFinite) {
      return 200.0;
    }
    return math.max(10.0, projection.far);
  }

  /// A right-handed look-at, which `vector_math` does not offer in the form the
  /// engine's `[0, 1]` depth convention needs.
  static vm.Matrix4 _lookAt(vm.Vector3 eye, vm.Vector3 target, vm.Vector3 up) {
    final forward = (target - eye)..normalize();
    final right = forward.cross(up)..normalize();
    final trueUp = right.cross(forward);

    final view = vm.Matrix4.identity();
    view.setEntry(0, 0, right.x);
    view.setEntry(0, 1, right.y);
    view.setEntry(0, 2, right.z);
    view.setEntry(1, 0, trueUp.x);
    view.setEntry(1, 1, trueUp.y);
    view.setEntry(1, 2, trueUp.z);
    // The camera looks down its own -Z, so the third row is the negated
    // forward axis.
    view.setEntry(2, 0, -forward.x);
    view.setEntry(2, 1, -forward.y);
    view.setEntry(2, 2, -forward.z);
    view.setEntry(0, 3, -right.dot(eye));
    view.setEntry(1, 3, -trueUp.dot(eye));
    view.setEntry(2, 3, forward.dot(eye));
    return view;
  }

  /// The triangle every full-screen pass is drawn with, uploaded once and
  /// wound for this backend.
  ///
  /// A triangle rather than a quad: a quad has a diagonal seam where the GPU
  /// rasterizes the 2x2 fragment quads along it twice.
  ///
  /// **The texture coordinates depend on where the backend's row zero is, and
  /// that is not a detail.** The positions are clip space directly — a
  /// full-screen pass has no projection to put a backend's convention right, so
  /// this buffer is the only place the difference can be stated. On a top-left
  /// backend clip `y = +1` and `v = 0` are both the top of the picture and the
  /// pairing below is the identity. On a bottom-left one clip `y = +1` is the
  /// *last* row of the target, so pairing it with `v = 0` reads the source's
  /// first row and writes it to the target's last: every full-screen pass turns
  /// its input upside down.
  ///
  /// A single pass that reads the frame and writes the frame survives that,
  /// because the flip on the way in cancels the flip on the way out and only
  /// the ends are ever looked at. **The bloom chain does not**: it is a
  /// threshold, a ladder down and a ladder back, an odd number of passes
  /// whichever way it is configured, so the glow arrived mirrored about the
  /// middle of the frame and was added to the scene there. A centred, symmetric
  /// subject hides it almost perfectly — which is why every synthetic probe
  /// agreed and only the recorded scene disagreed. Put the bright thing above
  /// the middle and the glow appears below it.
  GeometryBuffer get _fullscreenTriangle {
    final flip = device.framebufferOrigin == FramebufferOrigin.bottomLeft;
    final top = flip ? 2.0 : -1.0;
    final bottom = flip ? 0.0 : 1.0;
    return _fullscreenVertices ??= device.uploadGeometry(
      Float32List.fromList(<double>[
        -1.0, -1.0, 0.0, bottom, //
        3.0, -1.0, 2.0, bottom, //
        -1.0, 3.0, 0.0, top, //
      ]).buffer.asByteData(),
      GeometryUsage.vertices,
    );
  }

  /// Floats per vertex: two of clip position, three of ray, then six vec4s of
  /// preset — or one vec4 of tint for the cube.
  static const int _kSkyVertexFloats = 2 + 3 + 6 * 4;
  static const int _kSkyCubeVertexFloats = 2 + 3 + 4;

  final Float32List _skyVertexData = Float32List(3 * _kSkyVertexFloats);
  final vm.Vector3 _skyRay = vm.Vector3.zero();

  /// Pipelines for full-screen stages this class does not have a field for.
  ///
  /// The engine's own effects each keep theirs in a named field, which is fine
  /// while the set is fixed and closed. An application's stage has no field to
  /// live in, and building the pipeline per frame is the one mistake this
  /// helper exists to make impossible.
  /// The frame graph node being executed, as the label every pass it opens
  /// carries — `H2`. Null between nodes.
  String? _passLabel;

  final Map<ShaderHandle, PipelineHandle> _fullscreenPipelines =
      <ShaderHandle, PipelineHandle>{};

  @override
  void drawFullscreen(FullscreenDraw draw) {
    // One encoder per pass, because Metal allows a single encoder open at a
    // time and the encoder offers no way to end one. Passes submitted to the
    // same queue execute in submission order, which is the ordering these
    // passes need.
    final pass = device.beginRenderPass(
      RenderPassDescriptor(
        label: _passLabel,
        colors: <ColorTarget>[
          ColorTarget(texture: draw.target, loadAction: draw.loadAction),
        ],
      ),
    );

    // Off the target rather than off the frame: a half-resolution effect says
    // nothing about its size beyond which texture it draws into, and the two
    // used to be passed separately and could disagree.
    final rect = ScreenRect.of(draw.target);
    pass.setState(_kFullscreenState.copyWith(viewport: rect, scissor: rect));

    pass.bindPipeline(
      _fullscreenPipelines[draw.fragment] ??= device.createPipeline(
        fullscreenVertexShader,
        draw.fragment,
      ),
    );
    pass.bindVertexBuffer(_fullscreenTriangle, 3);
    pass.bindIndexBuffer(_identityIndices(3), IndexType.int32, 3);

    draw.textures.forEach((slot, texture) {
      pass.bindTexture(
        draw.fragment,
        slot,
        texture,
        sampler: draw.samplerFor(slot),
      );
    });
    // Before the draw's own blocks, so an application stage that happens to
    // name `FragCoordInfo` itself is the one that wins.
    _bindFragCoord(pass, draw.fragment, draw.target);
    // Through the stage's layout where it is known, like `bindBlock`: an
    // engine block handed to a stage that declares a narrower one of the same
    // name — bloom's threshold and its upsample — keeps only what that stage
    // has. An application's stage has no layout here and takes its map as it
    // is.
    draw.uniforms.forEach((block, members) {
      final layout = draw.fragment.layouts?[block];
      pass.bindUniformBlock(
        draw.fragment,
        block,
        layout == null || layout.length >= members.length
            ? members
            : <String, Float32List>{
                for (final MapEntry(:key, :value) in members.entries)
                  if (layout.containsKey(key)) key: value,
              },
      );
    });

    pass.draw();
    _frameCounters?.drawCalls++;
    pass.submit();
  }

  /// The counters of the frame currently being encoded, or null between
  /// frames — `gfx-01n`.
  ///
  /// **Not global state; the frame's own, held where the draws are.** A draw
  /// is counted by whatever encodes it, and most of them are encoded inside
  /// `encodeScene`, which is handed a `FramePassState` already. The post
  /// chain and the shadow passes are not: they draw through [drawFullscreen]
  /// and through their own passes, neither of which had anywhere to count.
  /// So the shadow map and the whole bloom ladder were drawing and reporting
  /// nothing — `FrameResult.drawCalls` was the scene and the composite, and
  /// a shadow pass that gained a cascade moved no number at all. The comment
  /// in `_renderShadowMap` even says "the draw call count is the graph's
  /// business", which was a promise nobody had kept.
  FramePassState? _frameCounters;

  /// The diagnostic overlay: lines, on top of everything.
  ///
  /// Depth compare `always` rather than merely writing nothing — a bounding box
  /// that disappears inside the very object it bounds is not much of a
  /// diagnostic. It is also why the scene pass re-establishes its own state per
  /// view: this leaves the pass drawing lines.
  static const PassState _kDebugLineState = PassState(
    primitiveType: PrimitiveType.line,
    polygonMode: PolygonMode.fill,
    cullMode: CullMode.none,
    blend: null,
    depthWrite: false,
    depthCompare: CompareFunction.always,
  );

  /// The marking draw of the x-ray stage: every fragment passes, and each
  /// one stores the reference. Paired with a depth test of `lessEqual` and
  /// no depth writes, so what is stored is one wherever a marked node is the
  /// nearest thing in the frame — its visible part, and nothing else.
  static const StencilState _kXrayMarkStencil = StencilState(
    passOp: StencilOperation.setToReferenceValue,
  );

  /// The silhouette draw: only where nothing marked is visible. Paired with
  /// a depth test of `greater`, so a fragment lands only where the node is
  /// behind what the scene drew *and* no marked node's visible part is in
  /// front of it.
  static const StencilState _kXraySilhouetteStencil = StencilState(
    compare: CompareFunction.notEqual,
  );

  /// The one reference the stage uses. A byte, so up to two hundred and
  /// fifty-five layers could be told apart; one is what a silhouette needs.
  static const int _kXrayReference = 1;

  /// What each view re-establishes at the top of the scene pass.
  ///
  /// Per view rather than once, and that is not redundancy: the debug overlay
  /// at the end of a view leaves the pass drawing lines, so the next view has
  /// to say it wants triangles again. Compare this with the overlay's own
  /// state and the reason each of these fields is here is readable in one
  /// diff.
  ///
  /// Blending is deliberately absent: it is per material, decided per mesh a
  /// few hundred lines down, and mentioning it here would be a value the next
  /// draw overwrites.
  static const PassState _kSceneViewState = PassState(
    primitiveType: PrimitiveType.triangle,
    depthWrite: true,
    depthCompare: CompareFunction.less,
  );

  /// How a caster is drawn into the cube atlas: depth on, nothing blended.
  ///
  /// [PassState.cullMode] is filled in per pass from `ShadowCasterFaces`, which
  /// is the one thing about this that a setting decides.
  static const PassState _kShadowCasterState = PassState(
    primitiveType: PrimitiveType.triangle,
    blend: null,
    depthWrite: true,
    depthCompare: CompareFunction.less,
  );

  /// Blanking one tile of the atlas by drawing over it.
  ///
  /// The pass loads rather than clears — clearing is attachment-wide and would
  /// erase every other light's tiles — so a refreshed tile is reset by drawing,
  /// and this is the state that draw needs: **depth untouched**, or the reset
  /// would occlude the casters that follow it into the same tile.
  ///
  /// Written as its own named state rather than three calls inside a loop,
  /// which is where this whole type earns its keep: the alternation between
  /// this and the caster state is now two names rather than six scattered
  /// calls, and the `depthWrite: false` that Impeller silently ignores is
  /// visible as a difference between two values instead of buried in a body.
  static const PassState _kShadowTileResetState = PassState(
    cullMode: CullMode.none,
    depthWrite: false,
    depthCompare: CompareFunction.always,
  );

  /// The static tile's copy — `S1`: no test, and depth written, since the
  /// stage writes the depth it copies and the dynamic casters that follow
  /// test against it.
  static const PassState _kShadowCopyState = PassState(
    cullMode: CullMode.none,
    depthWrite: true,
    depthCompare: CompareFunction.always,
  );

  /// What every full-screen pass sets, minus the rectangle.
  ///
  /// Depth out of the way rather than merely unused: a full-screen triangle
  /// covers everything, so a depth test it did not ask for would decide which
  /// of its own three vertices survived.
  ///
  /// Blending is *off* rather than unmentioned, which is a distinction this
  /// type exists to keep. On WebGL an unmentioned field inherits whatever the
  /// last pass left in global GL state, and the pass before a post chain is
  /// usually the scene, which blends.
  static const PassState _kFullscreenState = PassState(
    primitiveType: PrimitiveType.triangle,
    cullMode: CullMode.none,
    blend: null,
    depthWrite: false,
    depthCompare: CompareFunction.always,
  );

  /// The same, adding to the target instead of replacing it.
  ///
  /// Only the bloom upsample wants this. It used to be a second copy of the
  /// block above, and the copies had drifted: this one set blending *after*
  /// depth and the other before. Nothing depended on it — these are
  /// independent — but it is the reason the two could not be one function with
  /// a blend argument, and nothing would have noticed if they had been.
  static const PassState _kFullscreenAdditiveState = PassState(
    primitiveType: PrimitiveType.triangle,
    cullMode: CullMode.none,
    blend: BlendState.additive,
    depthWrite: false,
    depthCompare: CompareFunction.always,
  );

  /// Clamped and linear: a post pass reading outside the source would otherwise
  /// wrap the opposite edge of the screen into the glow.
  static const SamplerOptions _clampSampler = SamplerOptions.linearClamp;

  /// Material samplers with `RenderSettings.anisotropy` applied, one per
  /// distinct sampler the materials carry.
  ///
  /// A cache for the same reason the Impeller translation has one: a bind
  /// happens several times per draw and hundreds of times per frame, and
  /// `withAnisotropy` allocates. Bounded by the handful of samplers the
  /// engine's loaders ever build; an entry is replaced rather than joined
  /// when the setting changes, so a slider dragged across the range costs
  /// one allocation per stop rather than a map that grows with it.
  final Map<SamplerOptions, SamplerOptions> _anisotropicSamplers =
      <SamplerOptions, SamplerOptions>{};

  /// The device's ceiling on taps, asked for once.
  ///
  /// A property of the device, not of the frame: on Impeller the question is
  /// a call across the FFI boundary, and a bind path that asked it up to
  /// five times per draw would spend more on the question than on the map
  /// lookup the answer feeds. Lazy, so a renderer that never draws a
  /// textured mesh never asks.
  late final int _maxAnisotropy = device.maxAnisotropy;

  /// `RenderSettings.anisotropy` as this device can honour it — the level
  /// every material sampler of the frame is raised to, decided once per
  /// mesh rather than once per bind.
  int _anisotropyLevel(int requested) => math.min(requested, _maxAnisotropy);

  /// [sampler] raised to [level] taps — or [sampler] itself, which is the
  /// common case and allocates nothing.
  ///
  /// Left alone: a null sampler (the backends' linear-and-repeat default,
  /// which blends no levels), one that is not trilinear, one that already
  /// asks for taps of its own — the bridge's, sized to the device at load —
  /// and every sampler when [level] is one. [level] arrives already clamped
  /// to the device by [_anisotropyLevel], so what remains on the bind path
  /// is a handful of field comparisons and one map lookup.
  SamplerOptions? _anisotropic(SamplerOptions? sampler, int level) {
    if (sampler == null || level <= 1) return sampler;
    if (sampler.anisotropy != 1 ||
        sampler.minFilter != MinMagFilter.linear ||
        sampler.magFilter != MinMagFilter.linear ||
        sampler.mipFilter != MipFilter.linear) {
      return sampler;
    }
    final cached = _anisotropicSamplers[sampler];
    if (cached != null && cached.anisotropy == level) return cached;
    return _anisotropicSamplers[sampler] = sampler.withAnisotropy(level);
  }

  /// What an environment cube is read through: linear *between levels* as
  /// well as within one.
  ///
  /// The levels of an environment are its roughness scale, and a shader asks
  /// for one by number — `textureLod(environment, r, roughness * levels)` —
  /// so a mip filter is not a detail here. With the nearest level a surface
  /// snaps between two lobes as its roughness crosses a half; with linear it
  /// slides. And on a backend that folds the mip filter into minification, a
  /// sampler that says nothing about levels reads the base level whatever
  /// level the shader named, which is a mirror at every roughness.
  static const SamplerOptions _environmentSampler = SamplerOptions(
    minFilter: MinMagFilter.linear,
    magFilter: MinMagFilter.linear,
    mipFilter: MipFilter.linear,
    widthAddressMode: SamplerAddressMode.clampToEdge,
    heightAddressMode: SamplerAddressMode.clampToEdge,
  );

  /// Draws every visible mesh of [scene], as the world is drawn.
  ///
  /// The loop the view model pass used to own, lifted onto the plugin
  /// interface so anything wanting ordinary geometry in an unordinary place
  /// gets materials, skinning and lighting for free rather than growing a
  /// second copy of them.
  ///
  /// The whole chain is tested, not just the node: a view model hides the
  /// weapons it is not holding by switching off their shared parent, and
  /// testing only the leaf draws every weapon at once.
  @override
  void encodeScene({
    required NodeFrame frame,
    required PassEncoder encoder,
    required Scene scene,
    required vm.Matrix4 viewProjection,
    required vm.Vector3 cameraPosition,
    int casterIndex = -1,
  }) {
    // Assembled here, from what the calling node declared, rather than handed
    // in. A caller that forgot produced a pass lit as though nothing shadowed
    // it, and nothing on this side could tell the difference.
    final settings = frame.settings;
    final state = frame.state;
    final shadows = SceneShadows.from(frame, casterIndex: casterIndex);

    // Lit by the scene that was passed, not by the frame's. The frame's
    // buffer and slot table describe the world scene; a contributor handing
    // in its own scene — the view model's studio is the one that exists —
    // gets that scene's lights gathered here, and no point shadows, because
    // the atlas rows were assigned to lights this scene does not contain.
    // Before this the parameter lit nothing: the view model's two lights
    // were never gathered, and a held weapon was lit by whatever the world
    // had nearby.
    final LightBuffer passLights;
    final Float32List passShadowSlots;
    if (identical(scene, _lightsScene)) {
      passLights = lights;
      passShadowSlots = _shadowSlots;
    } else {
      _passLights.gather(scene.lights);
      if (_passLights.count == 0 && scene.defaultLightWhenUnlit) {
        _passLights.useDefaultLight();
      }
      passLights = _passLights;
      passShadowSlots = _noShadowSlots;
    }

    _cameraData[0] = cameraPosition.x;
    _cameraData[1] = cameraPosition.y;
    _cameraData[2] = cameraPosition.z;
    // Out of the matrix, because a contributor is handed one and not a camera.
    viewAxisOf(viewProjection, _forward);
    _forwardData[0] = _forward.x;
    _forwardData[1] = _forward.y;
    _forwardData[2] = _forward.z;

    for (final node in scene.meshes) {
      if (!node.visibleInHierarchy) continue;
      _encodeNode(
        encoder: encoder,
        node: node,
        scene: scene,
        settings: settings,
        viewProjection: viewProjection,
        // Whatever the caller declared and passed, unexamined. This method used
        // to decide for its caller — no directional map, and the atlas taken
        // from a renderer field — and both halves of that were wrong in the
        // same way: a node's inputs were being chosen somewhere the node could
        // not see, so no declaration could be checked against them.
        shadows: shadows,
        lights: passLights,
        shadowSlots: passShadowSlots,
        state: state,
      );
    }
  }

  /// The camera's view-projection, in the clip space this backend uses.
  ///
  /// Cameras build for [DepthRange.zeroToOne], which is what Metal and Vulkan
  /// want. A backend on OpenGL conventions gets the same matrix with
  /// depth remapped: `z' = 2z - w` turns near-at-0/far-at-1 into
  /// near-at-minus-one/far-at-1.
  ///
  /// Corrected here rather than in the camera because a camera does not know
  /// which device will draw it, and because one boundary is easier to keep
  /// right than a second projection path. Feeding the uncorrected matrix to GL
  /// draws everything, in the correct order, in the far half of the depth
  /// buffer — half the precision, no error anywhere, and z-fighting on surfaces
  /// that were fine on the other backend.
  vm.Matrix4 _viewProjection(CameraNode camera, double aspect) =>
      toDepthRange(camera.viewProjection(aspect), device.depthRange);

  /// The matrix the scene's own draws use: [_viewProjection], moved by this
  /// frame's jitter while temporal anti-aliasing is on — `R1`.
  ///
  /// Only the draws that feed the resolve take it: the meshes, the sky and
  /// the contributors in the scene pass. Everything drawn after the resolve,
  /// or read back at a pixel — picking, the debug overlay, the post passes
  /// that reconstruct positions — keeps the unjittered matrix, because the
  /// picture they work on has had the jitter averaged out of it.
  vm.Matrix4 _drawViewProjection(
    CameraNode camera,
    ScreenRect rect,
    RenderSettings settings,
  ) {
    final aspect = rect.width / rect.height;
    final temporal = settings.antiAlias.temporal;
    // No jitter where there can be no resolve: a device that opens one colour
    // attachment has no surface buffer, and a jittered picture nobody
    // averages is a picture that shakes.
    if (!temporal.enabled || device.maxColorAttachments < 2) {
      return _viewProjection(camera, aspect);
    }
    final jittered = JitteredProjection.frame(
      camera.projection,
      frame: _frameIndex,
      length: temporal.sequenceLength,
      width: rect.width,
      height: rect.height,
    );
    return toDepthRange(
      jittered.toMatrix(aspect) * camera.viewMatrix,
      device.depthRange,
    );
  }

  /// A view's rectangle in pixels of a [width] × [height] target.
  ///
  /// **Held inside the target**, which rounding each term on its own did not
  /// do: a view at `x: 0.5, width: 0.5` of a target 101 pixels wide rounded
  /// both halves up and asked for 51 + 51. A viewport the hardware clips, but
  /// a scissor outside the attachment is a validation error on Metal. Every
  /// pass that draws a view per rectangle takes it from here, so the scene,
  /// the id pass and the composite cannot disagree about where a view is.
  static ScreenRect _viewportPixels(
    ViewportRect fraction,
    int width,
    int height,
  ) {
    final x = math.min((fraction.x * width).round(), math.max(width - 1, 0));
    final y = math.min((fraction.y * height).round(), math.max(height - 1, 0));
    return ScreenRect(
      x: x,
      y: y,
      width: math.max(1, math.min((fraction.width * width).round(), width - x)),
      height: math.max(
        1,
        math.min((fraction.height * height).round(), height - y),
      ),
    );
  }

  /// Makes another finished-frame texture, at the size the targets are.
  ///
  /// Set by [_ensureTargets], because the size and the format are its business
  /// and a frame that needs one more should not have to ask twice.
  TextureHandle Function()? _makeLdrFrame;

  TextureHandle _takeLdrFrame() {
    if (_ldrFree.isNotEmpty) return _ldrFree.removeLast();
    final made = _makeLdrFrame!();
    _ldrFrames.add(made);
    return made;
  }

  /// How many finished-frame textures this machine turned out to need.
  ///
  /// One on a backend that finishes before it returns, and as many as the
  /// display and the queue between them keep in the air on one that does not.
  int get framesInFlight => _ldrFrames.length;

  /// What a frame of [scene] under [settings] would do, worked out without
  /// drawing it — `gfx-41n`.
  ///
  /// **The same nodes and the same compile as a real frame, and no device
  /// touched.** The answer comes back as a [CompiledFrameGraph]: which passes
  /// would run, in what order, and — through `skipped` — which would not and
  /// why, with the same five reasons a drawn frame reports. It is the *graph*
  /// this asks, not a second implementation of the graph's rules, which is
  /// the whole reason to trust it: a dry run computed by a copy of the
  /// scheduling logic would answer for the copy.
  ///
  /// **What it costs, and what that buys.** The plan gathers the scene's
  /// lights into a buffer of its own and runs its own shadow-slot allocator,
  /// rather than reading this renderer's. That is an allocation per call and
  /// it is the point: asking what a frame *would* do cannot be allowed to
  /// disturb what the last frame did, and an allocator shared with the real
  /// path would hand out rows to a frame that is never drawn.
  ///
  /// **What it does not promise**, said plainly because a diagnostic that
  /// overstates itself is worse than none:
  ///
  ///  * it plans no picks, so `object ids` is reported as it would be for a
  ///    frame nobody asked a question of;
  ///  * it bakes nothing, so the static atlas is planned as clean — a real
  ///    frame that decides to re-bake runs the same node either way, so the
  ///    answer about *which passes* stands;
  ///  * the auto-exposure meter is not stepped, because stepping it is a
  ///    change to the picture rather than a question about it.
  ///
  /// Where it is worth calling: before a frame, to find out whether an effect
  /// a caller switched on will actually run — and on a device that cannot draw
  /// at all, which is how an application can answer "would this scene get
  /// occlusion here" during start-up rather than after the first frame.
  CompiledFrameGraph planFrame({
    required Scene scene,
    required List<RenderView> views,
    RenderSettings settings = const RenderSettings(),
  }) {
    if (views.isEmpty) {
      throw ArgumentError('At least one RenderView is required.');
    }

    // This plan's own lights, gathered the way a frame gathers them — a
    // default light included, because a scene with none is lit by one and a
    // plan that said otherwise would be planning a different picture.
    final planLights = LightBuffer()..gather(scene.lights);
    if (planLights.count == 0 && scene.defaultLightWhenUnlit) {
      planLights.useDefaultLight();
    }
    final shadowCaster = _directionalIndexIn(planLights);

    // This plan's own allocator. A fresh one assigns rows by the same rule
    // from an empty state, which is what a plan can honestly say: how many
    // rows this scene *wants*, not which rows the running frame happens to
    // have handed out.
    final candidates = <ShadowCandidate>[];
    _collectShadowCandidates(scene, views, into: candidates);
    final assignment = ShadowSlotAllocator(
      slotCount: kShadowedLights,
    ).assign(candidates);
    var slot = 0;
    for (var row = 0; row < assignment.owners.length; row++) {
      if (assignment.owners[row] is LightNode) slot = math.max(slot, row + 1);
    }

    final ordered = List<RenderView>.of(views)
      ..sort((a, b) => a.priority.compareTo(b.priority));

    return _compileFrameGraph(
      views.first,
      settings,
      // From this plan's own buffer, not the running frame's: a plan that asked
      // the live lights whether a sun exists would answer about a different
      // scene.
      sunToLight: _toLightIn(planLights, shadowCaster),
      sunRadiance: _radianceIn(planLights, shadowCaster),
      contactToLight: _contactToLightIn(planLights, shadowCaster),
      fogToLight: _toLightIn(planLights, _airLightIn(planLights, shadowCaster)),
      fogRadiance: _radianceIn(
        planLights,
        _airLightIn(planLights, shadowCaster),
      ),
      cubeStatic: _CubeShadowStaticNode(
        this,
        scene: scene,
        settings: settings.shadows,
        slotCount: slot,
        // Nothing is baked by a plan, so the bake is planned as clean. Both
        // answers run the same node, so what passes would run is unaffected.
        staticDirty: false,
      ),
      cube: _CubeShadowNode(
        this,
        scene: scene,
        settings: settings.shadows,
        slotCount: slot,
      ),
      shadow: _ShadowMapNode(
        this,
        scene: scene,
        settings: settings.shadows,
        casterIndex: shadowCaster,
        camera: ordered.isEmpty ? null : ordered.first.camera,
      ),
      irradiance: _IrradianceUpdateNode(
        this,
        scene: scene,
        shadowCaster: shadowCaster,
        clearColor: ordered.first.clearColor,
      ),
      probes: <_ReflectionProbeNode>[
        for (var i = 0; i < scene.probes.length; i++)
          _ReflectionProbeNode(
            this,
            scene: scene,
            probe: scene.probes[i],
            index: i,
            shadowCaster: shadowCaster,
            clearColor: ordered.first.clearColor,
          ),
      ],
      scene: _SceneNode(
        this,
        scene: scene,
        ordered: ordered,
        contributors: contributors.active.toList(growable: false),
        shadowCaster: shadowCaster,
        lightOverflow: planLights.overflow,
      ),
      bloom: _BloomNode(this, settings.bloom),
      composite: _CompositeNode(this, scene, ordered, settings),
      luminance: _LuminanceNode(this, settings.autoExposure, ordered),
      // No questions, because a plan asks none — see the note above.
      objectIds: _ObjectIdNode(
        this,
        scene: scene,
        ordered: ordered,
        picks: const <_PickRequest>[],
      ),
      viewCount: ordered.length,
    );
  }

  /// Links, before the first frame, every pipeline drawing [scene] through
  /// [views] with [settings] will need — `N3`, for a loading screen.
  ///
  /// **A pipeline linked in the middle of play is a hitch.** Linking is the
  /// slowest thing a frame can ask the device to do, and a renderer links on
  /// first use: the frame a door opens on a room with a new material pays
  /// for it, and that frame is the spike a player notices. So every mesh the
  /// scene holds gets its lit pipeline here whether or not any view can see
  /// it yet, and then one frame is drawn, which links what the frame graph's
  /// passes use at these settings — shadows, the post chain, the composite.
  ///
  /// A mesh added later, or a setting switched on later, links on first use
  /// as before.
  void warmUp({
    required int width,
    required int height,
    required Scene scene,
    required List<RenderView> views,
    RenderSettings settings = const RenderSettings(),
  }) {
    for (final node in scene.meshes) {
      final skinned = node.skeleton != null;
      final instanced = node is InstancedMeshNode;
      _pipelineFor(
        node.material.lighting,
        skinned: skinned,
        instanced: instanced,
        lightmapped: node.lightmapped && !skinned && !instanced,
      );
    }
    // And what only a later frame reaches: the tile reset a kept cascade
    // atlas redraws a tile with (`S1`), and the copy a static one is read
    // through — neither runs on a first frame, which draws every tile from a
    // clear.
    final reset = shaders['ShadowTileReset'];
    final resetVertex = shaders['ShadowTileResetVertex'];
    if (reset != null && resetVertex != null) {
      _cubeShadowResetPipeline ??= device.createPipeline(resetVertex, reset);
    }
    final copy = shaders['ShadowCopy'];
    final fullscreen = shaders['FullscreenVertex'];
    if (copy != null &&
        fullscreen != null &&
        scene.meshes.any((node) => node.shadowIsStatic)) {
      _shadowCopyPipeline ??= device.createPipeline(fullscreen, copy);
    }
    render(
      width: width,
      height: height,
      scene: scene,
      views: views,
      settings: settings,
    );
  }

  FrameResult render({
    required int width,
    required int height,
    required Scene scene,
    required List<RenderView> views,
    RenderSettings settings = const RenderSettings(),
  }) {
    if (views.isEmpty) {
      throw ArgumentError('At least one RenderView is required.');
    }
    // `gfx-35n`. Applied here, once, so every target and every pass below is
    // sized from it — the scene, the surface buffer, the occlusion, the bloom
    // chain and the composite all take their size from these two numbers.
    // Clamped to at least one pixel: a viewport animating open is a real
    // state and a zero-pixel target is not.
    //
    // **Two sizes while temporal anti-aliasing is on — `R2`.** The scene and
    // everything that reads its buffers draw at the scaled size, and the
    // resolve reconstructs the asked-for size from the jittered frames, so
    // bloom, the composite and the frame are output-sized. Off, the output is
    // the scaled size too, which is the frame this setting has always
    // returned.
    final temporal = settings.antiAlias.temporal.enabled;
    final requestedWidth = width;
    final requestedHeight = height;
    final scale = settings.renderScale.clamp(0.1, 1.0);
    if (scale != 1.0) {
      width = math.max(1, (width * scale).round());
      height = math.max(1, (height * scale).round());
    }
    // `R5`: and with the spatial upscale, the composite draws small and the
    // upscale brings it to the asked-for size.
    final upscaled = temporal || _upscales(settings);
    final outputWidth = upscaled ? requestedWidth : width;
    final outputHeight = upscaled ? requestedHeight : height;
    _outputWidth = outputWidth;
    _outputHeight = outputHeight;
    // `N3`: the allowance for work that can wait, from nothing each frame.
    if (_workBudget.microseconds != settings.frameWorkBudget) {
      _workBudget = FrameWorkBudget(microseconds: settings.frameWorkBudget);
    }
    _workBudget.beginFrame();
    // `R9`: the extended output where it was asked for and the device can
    // present it; the standard frame everywhere else.
    final hdrFormats = device.hdrOutputFormats;
    _extendedOutput =
        settings.outputTransform == OutputTransform.extendedSrgb &&
        hdrFormats.isNotEmpty;
    _frameFormat = _extendedOutput
        ? hdrFormats.first
        : device.defaultColorFormat;
    // A frame drawn without the resolve leaves the history describing a
    // picture from before it; turning it back on starts again.
    if (!temporal) _historyValid = false;
    _temporalEffects = temporal && device.maxColorAttachments > 1;
    if (!_temporalEffects) {
      for (final history in _effectHistories.values) {
        history.valid = false;
      }
    }
    // Timeline markers, not print statements: the phases below are only
    // meaningful next to Flutter's own build and raster spans, and only in
    // profile or release, where the debug interpreter is not the bottleneck.
    developer.Timeline.startSync('Renderer.render');
    final frameClock = Stopwatch()..start();
    _ensureTargets(width, height, outputWidth, outputHeight);

    // A texture nothing is reading, so that what is drawn now is not what a
    // compositor is still showing — see [_ldrFrames].
    _ldrCurrent = _takeLdrFrame();

    // Rotates whatever the backend keeps per frame — on one of them, the ring
    // of uniform allocators. Before anything is encoded, and never in the
    // middle of one.
    device.beginFrame();

    // **This slot's textures were handed back a full ring ago**, so the GPU is
    // done with them; the same reasoning that governs the backend's own ring.
    //
    // That sentence was false for as long as it had been written. `_frameIndex`
    // was incremented *here*, before any pass ran — so a texture released
    // during frame N landed in slot `(N + 1) % 3`, which is the slot the top of
    // frame N + 1 retires. One frame of deferral where three were intended, and
    // one frame is not enough: the GPU is still reading a pooled target while
    // the pool hands it to the next pass. What that looks like is a draw
    // missing from a frame — a bar of a wireframe cage, a monster inside it —
    // on a scene where nothing is moving, which is where a one-frame artefact
    // stops hiding.
    //
    // The counter now advances at the *end* of the frame, so everything
    // released during frame N goes into slot `N % 3` and is retired at the top
    // of frame N + 3.
    final expired = _pendingRelease[_frameIndex % _kFramesInFlight];
    for (final texture in expired) {
      targetPool.release(texture);
    }
    expired.clear();

    // The same slot, for the targets this renderer owns rather than borrows:
    // reallocated by a resize or a settings change, and given back to the
    // device instead of to the pool. See [_destroyAfterFrame].
    final finished = _pendingDestroy[_frameIndex % _kFramesInFlight];
    for (final texture in finished) {
      device.releaseTexture(texture);
    }
    finished.clear();

    // Lights are gathered once up front now, because the shadow pass needs the
    // caster before any view is drawn — and the packed buffer is per frame, not
    // per view.
    lights.gather(scene.lights);
    if (lights.count == 0 && scene.defaultLightWhenUnlit) {
      lights.useDefaultLight();
    }
    _lightsScene = scene;
    // **What was actually lost, not what did not fit the slots — `gfx-74n`.**
    // The frame's own `gather` fills eight slots in scene order and calls the
    // rest overflow; every draw then re-selects for itself, and since this row
    // a draw carries up to `maxExtraLights` more in the light list. So a scene
    // of sixteen lamps drops nothing, and reporting eight here would tell
    // somebody their ninth lamp does nothing while it is lighting the floor.
    final lightOverflowCount = math.max(
      scene.lights.length - LightBuffer.maxLights - LightBuffer.maxExtraLights,
      0,
    );
    final shadowCaster = _firstDirectionalIndex();

    // Zeroed by the frame rather than by the pass, because the pass may not
    // run. `_renderShadowMap` cleared these on its way out of every early
    // return; a node the graph culls has no way out to clear them on, and last
    // frame's strength left standing would shadow a scene whose shadows were
    // just switched off.
    _shadowParams[3] = 0.0;
    _shadowCasters = 0;
    _batchedDraws = 0;
    _retireUnusedBatches();
    // One cascade until a pass says otherwise, so a shader reading these
    // between frames sees the arrangement it has always seen.
    _shadowCascades[2] = 1.0;

    // Which point lights get a row of the atlas, decided by relevance rather
    // than by the order they happen to sit in the scene list.
    // [kShadowedLights] is a limit on how many can be shadowed *at once*, not
    // on how many a level may contain: the seventh torch takes a row as soon as
    // it matters more than one of the six, and gives it back when it stops.
    //
    // Every row is decided before any of the atlas is drawn, because one pass
    // draws all of them: a pass per light would clear the rows already there.
    _updateAmbient(scene, settings);

    _collectShadowCandidates(scene, views);
    final assignment = _shadowSlotAllocator.assign(_shadowCandidates);
    _shadowsDenied = assignment.denied.length;

    _shadowRowOf.clear();
    var slot = 0;
    for (var row = 0; row < assignment.owners.length; row++) {
      final owner = assignment.owners[row];
      if (owner is! LightNode) continue;

      // Every assigned row is described from here down, whether or not this
      // light reached the frame's own eight slots. The loop used to stop on a
      // light the frame buffer had no room for, leaving the row drawn from
      // whatever cube data was last in it — and that is exactly the light
      // per-object selection now hands to a draw standing next to it.
      owner.readWorldPosition(_cubePosition);
      _cubeLightData[row * 4] = _cubePosition.x;
      _cubeLightData[row * 4 + 1] = _cubePosition.y;
      _cubeLightData[row * 4 + 2] = _cubePosition.z;
      _cubeLightData[row * 4 + 3] = owner.range > 0.0 ? owner.range : 20.0;

      // **A cone wider than a cube face is drawn as the cube.** One tile
      // through a frustum of half-angle θ spreads its texels over `tan θ` of
      // what a face covers, so past forty-five degrees the single tile is
      // coarser than the six faces would be, and past the clamp below it is
      // cut off: the rim of a floodlight read as lit. As a cube the row is a
      // point light's, and the cone still limits where its light falls,
      // because that is the lighting's attenuation and not the shadow's.
      final spot =
          owner.type == LightType.spot &&
          owner.outerConeAngle * _kSpotFrustumMargin <= math.pi / 4;
      // The frustum this row is drawn and read through. A cube face is ninety
      // degrees, so `tan(45°)` is exactly one; a cone opens to twice its outer
      // angle, and the margin is what keeps the very edge of the cone inside
      // the tile. Without it the shader's own `abs(ndc) > 1` bail — written to
      // catch a fragment outside the face — fires along the rim and quietly
      // returns "lit", which reads as the shadow being trimmed to a slightly
      // narrower cone than the light.
      final tanHalf = spot
          ? math.tan(
              (owner.outerConeAngle * _kSpotFrustumMargin).clamp(
                0.02,
                math.pi / 4,
              ),
            )
          : 1.0;
      if (spot) owner.readDirection(_shadowAim);
      _cubeLightAim[row * 4] = spot ? _shadowAim.x : 0.0;
      _cubeLightAim[row * 4 + 1] = spot ? _shadowAim.y : 0.0;
      _cubeLightAim[row * 4 + 2] = spot ? _shadowAim.z : 0.0;
      // Negative marks "not a spot", which is what the atlas pass branches on.
      // A tangent is never negative, so the flag and the value share a channel
      // without either being able to impersonate the other.
      _cubeLightAim[row * 4 + 3] = spot ? tanHalf : -1.0;

      // Which atlas row this light owns, said once for the frame. Which *slot*
      // reads it depends on the packing, and there is a packing per draw once
      // the scene offers more lights than a draw can carry — see
      // [_writeShadowSlots].
      _shadowRowOf[owner] = row;
      // Which shape it is: 0 a cube, 1 a single cone-shaped tile. The shader
      // needs this before it can pick a face, and it cannot be inferred from
      // the tangent beside it — a spot opening to exactly forty-five degrees
      // has a tangent of one, the same as every cube face.
      _shadowRowShape[row] = spot ? 1.0 : 0.0;
      // The tangent again, this time for the filter rather than the pass. It
      // has to be *written* rather than left at the −1 an empty slot holds,
      // because the penumbra estimate divides by it. Written next to the row
      // and not in a branch: the two are read together, and a slot with a row
      // but no angle is a black light.
      //
      // The depth bias is deliberately **not** scaled by this, and the reason
      // is a measurement rather than a preference. The argument for scaling it
      // is sound on paper — a cone's texel covers less world, so a bias fixed
      // in metres is relatively larger and should lift the shadow off its
      // caster's foot. It was probed: a post standing on a floor, lit once as a
      // point and once as a cone of 0.6 and then of 0.22 radians, put its
      // shadow in the same cells every time, contact included. A separate
      // `spotBias` would have been a knob nothing turns.
      _shadowRowTangent[row] = tanHalf;
      slot = math.max(slot, row + 1);
    }
    _writeShadowSlots(lights, _shadowSlots);
    // Which rows are occupied, and therefore whether the atlas is worth
    // drawing at all. Decided here rather than inside either atlas node,
    // because it is what the *frame* knows — both nodes are asked whether they
    // are active before either one runs.
    _cubeShadowLight = slot > 0 ? slot : -1;

    final ordered = List<RenderView>.of(views)
      ..sort((a, b) => a.priority.compareTo(b.priority));

    // The meter's adaptation, by the time since the last frame. Stepped before
    // the graph is built so the composite reads a value this frame's clock has
    // already moved, and clamped so a stall — a debugger, a tab in the
    // background — is a step rather than a jump to the target.
    _sinceLastFrame.stop();
    final dt = math.min(_sinceLastFrame.elapsedMicroseconds / 1e6, 0.25);
    _sinceLastFrame
      ..reset()
      ..start();
    if (settings.autoExposure.enabled) {
      (_autoExposure ??= ExposureAdapter(
        initial: settings.exposure,
      )).step(dt, settings.autoExposure);
      // `gfx-22n`. One adapter per view, stepped by the same clock. A view
      // that has just appeared starts at the frame's own exposure rather than
      // at the setting's, so a second player joining does not arrive to a
      // climb from a number nothing on screen was drawn with.
      if (settings.autoExposure.perView) {
        while (_viewExposure.length < views.length) {
          _viewExposure.add(
            ExposureAdapter(initial: _autoExposure?.value ?? settings.exposure),
          );
        }
        while (_viewExposure.length > views.length) {
          _viewExposure.removeLast();
        }
        for (final adapter in _viewExposure) {
          adapter.step(dt, settings.autoExposure);
        }
      } else if (_viewExposure.isNotEmpty) {
        // Switched off again: the adapters go, so switching it back on starts
        // from the frame's exposure rather than from what each view thought
        // several seconds of scene ago.
        _viewExposure.clear();
      }
    }
    _lastExposure = _exposureFor(settings);

    // This frame's questions, and none asked after this point: a pick made
    // from inside a frame callback waits for the frame after.
    final picks = List<_PickRequest>.of(_pendingPicks, growable: false);
    _pendingPicks.clear();

    // The whole frame, ordered by what each pass declares rather than by where
    // it sits in this method: the cube atlas, the shadow map, the world, the
    // application's overlays, reflections, bloom and the composite. Nothing is
    // left drawing outside the graph.
    //
    // The scene and the composite hold this frame's views the way reflections
    // holds its own, because neither the view loop nor the overlay batch after
    // the tone map can be derived from `NodeFrame`, which carries neither a
    // scene nor a viewport.
    //
    // The atlas nodes hold this frame's row count and the allocator's verdict
    // on the bake for the same reason, and they take the allocator and the
    // scheduler by reference rather than owning them: nodes are rebuilt every
    // frame, and one that owned either would forget what it had drawn and
    // re-bake for ever.
    //
    // **Built, compiled and declared inside a `try` of their own, for the sake
    // of the questions just taken.** An application node that reads a name
    // nothing writes fails in `_compileFrameGraph`, before a single pass has
    // run, and a question the frame dropped there is exactly as dropped as one
    // it dropped in a pass: off `_pendingPicks`, so no later frame sees it,
    // and not on any completer `dispose` knows about. The catch answers them
    // the way the second catch below does. Two `try`s rather than one because
    // what the second has to undo — the frame's textures — does not exist
    // until this one has finished. The two nodes that report to the frame's
    // result outlive the `try` for the same reason the graph does.
    final CompiledFrameGraph frameGraph;
    final FrameResources resources;
    final _SceneNode sceneNode;
    final _CompositeNode compositeNode;
    try {
      final cubeStaticNode = _CubeShadowStaticNode(
        this,
        scene: scene,
        settings: settings.shadows,
        slotCount: slot,
        staticDirty: assignment.staticDirty,
      );
      final cubeNode = _CubeShadowNode(
        this,
        scene: scene,
        settings: settings.shadows,
        slotCount: slot,
      );
      final shadowNode = _ShadowMapNode(
        this,
        scene: scene,
        settings: settings.shadows,
        casterIndex: shadowCaster,
        // The first view's camera, for splitting the cascades by where
        // somebody is actually looking. A second viewport is a second set of
        // splits and one map cannot serve both; the primary view wins, which
        // is the same answer reflections give.
        camera: ordered.isEmpty ? null : ordered.first.camera,
      );
      // One node per probe the scene holds, in scene order, so the name the
      // scene reads for the i-th probe is the name the i-th node provides. A
      // probe that left the scene since last frame gives its cubes back here,
      // and this frame's one whole-cube capture is up for claiming again.
      _retireProbesNotIn(scene);
      _wholeProbeCaptured = false;
      final probeNodes = <_ReflectionProbeNode>[
        for (var i = 0; i < scene.probes.length; i++)
          _ReflectionProbeNode(
            this,
            scene: scene,
            probe: scene.probes[i],
            index: i,
            shadowCaster: shadowCaster,
            clearColor: ordered.first.clearColor,
          ),
      ];
      sceneNode = _SceneNode(
        this,
        scene: scene,
        ordered: ordered,
        contributors: contributors.active.toList(growable: false),
        shadowCaster: shadowCaster,
        lightOverflow: lightOverflowCount,
      );
      final bloomNode = _BloomNode(this, settings.bloom);
      compositeNode = _CompositeNode(this, scene, ordered, settings);
      final luminanceNode = _LuminanceNode(
        this,
        settings.autoExposure,
        ordered,
      );
      final objectIdNode = _ObjectIdNode(
        this,
        scene: scene,
        ordered: ordered,
        picks: picks,
      );
      frameGraph = _compileFrameGraph(
        views.first,
        settings,
        cubeStatic: cubeStaticNode,
        cube: cubeNode,
        shadow: shadowNode,
        probes: probeNodes,
        irradiance: _IrradianceUpdateNode(
          this,
          scene: scene,
          shadowCaster: shadowCaster,
          clearColor: ordered.first.clearColor,
        ),
        scene: sceneNode,
        bloom: bloomNode,
        composite: compositeNode,
        luminance: luminanceNode,
        objectIds: objectIdNode,
        viewCount: ordered.length,
        // The same light the shadow map casts from, so the seam the march draws
        // continues the shadow the map drew rather than crossing it.
        sunToLight: _toLightIn(lights, shadowCaster),
        sunRadiance: _radianceIn(lights, shadowCaster),
        contactToLight: _contactToLightIn(lights, shadowCaster),
        fogToLight: _toLightIn(lights, _airLightIn(lights, shadowCaster)),
        fogRadiance: _radianceIn(lights, _airLightIn(lights, shadowCaster)),
      );

      // The frame's own resources: the graph names the lit scene and each
      // version of it, this holds the texture behind each. Nothing is handed
      // in here any more — the scene provides its colour and its surface
      // buffer, reflections provide the second colour, the composite provides
      // the finished image, and each of them does it from inside the node that
      // produced it. What is left in this method is the one thing the graph
      // allocates for itself.
      resources =
          FrameResources(
              source: _DeferredTextureSource(this),
              graph: frameGraph,
              frameWidth: width,
              frameHeight: height,
              alias: settings.aliasTargets,
              onRetire: debugOnTargetRetired,
            )
            // Half the frame, in the same HDR format, which is what the bloom
            // chain's top level has always been.
            // Not const any more: the format comes from the device, which is
            // the point — a description of a resource cannot be a compile-time
            // constant once it depends on which backend is drawing.
            //
            // Half the *output* while temporal anti-aliasing is on, because
            // the glow is taken from the resolved picture — `R2`.
            ..declare(
              ResourceDesc(
                id: FrameResourceIds.bloom,
                format: hdrFormat,
                size: temporal
                    ? AbsolutePixels(
                        math.max(1, outputWidth ~/ 2),
                        math.max(1, outputHeight ~/ 2),
                      )
                    : const FrameFraction(2),
              ),
            )
            // Half again, and the same format for the same reason: HDR is the
            // one format every backend here is known to render into. A single
            // channel would do — the pass writes occlusion four times over —
            // but "known to work on three backends" beats "three quarters
            // smaller" for a target that is a quarter of the frame to begin
            // with.
            ..declare(
              ResourceDesc(
                id: FrameResourceIds.ao,
                format: hdrFormat,
                size: const FrameFraction(2),
              ),
            )
            // The frame's own size, unlike the occlusion beside it: the seam a
            // contact shadow draws is a few pixels wide, and half of a few
            // pixels is a stair. Same format for the same reason as the
            // occlusion — HDR is what all three backends are known to render
            // into — and the pass writes its one number four times over.
            ..declare(
              ResourceDesc(
                id: FrameResourceIds.contactShadow,
                format: hdrFormat,
              ),
            )
            // `R7`: an eighth of the frame; the stops are blurred wide.
            ..declare(
              ResourceDesc(
                id: FrameResourceIds.localExposure,
                format: hdrFormat,
                size: const FrameFraction(8),
              ),
            )
            // The frame's size: a velocity is per pixel of the picture the
            // resolve reprojects.
            ..declare(
              ResourceDesc(id: FrameResourceIds.velocity, format: hdrFormat),
            )
            // A fixed small square of bytes, whatever the window does: the
            // meter reads it back, and sixteen kilobytes is what a readback
            // per frame may cost. Eight bits because that is what comes back
            // through `readback` on every backend, and the encoding is in
            // stops so eight bits is a sixteenth of a stop.
            ..declare(
              const ResourceDesc(
                id: FrameResourceIds.luminance,
                format: TextureFormat.r8g8b8a8UNormInt,
                size: AbsolutePixels(ExposureMeter.size, ExposureMeter.size),
              ),
            )
            // `C3`: a fixed grid the occlusion reprojects, in the bytes a
            // readback hands back. 128 KB a reading, and one in the air at a
            // time.
            ..declare(
              const ResourceDesc(
                id: FrameResourceIds.depthPyramid,
                format: TextureFormat.r8g8b8a8UNormInt,
                size: AbsolutePixels(HiZOcclusion.width, HiZOcclusion.height),
              ),
            )
            // The frame's size, because a pick is a pixel of the frame, and
            // eight bits per channel because the id is three bytes and a
            // readback hands back exactly those.
            ..declare(
              const ResourceDesc(
                id: FrameResourceIds.objectIds,
                format: TextureFormat.r8g8b8a8UNormInt,
              ),
            );
    } catch (error, stack) {
      _failPicks(picks, error, stack);
      // The same three things the catch around the passes owes, for the same
      // reasons: `_ensureTargets` and a retired probe may already have queued
      // releases into this frame's slot, the finished-frame texture taken
      // above has to go back into rotation, and the timeline block opened at
      // the top has to close.
      _abandonFrame();
      rethrow;
    }

    final passState = FramePassState();

    // A pass that throws leaves the frame's textures lent out, and the pool has
    // no other way to learn they are free — one set of targets per attempt, and
    // a frame that fails tends to fail again next frame. [releaseAll] was
    // written for this and had no caller; it has one now, and the throw the
    // resource layer raises when a node breaks its `keeps` promise is the first
    // thing likely to use it.
    final passTimings = <FramePass>[];
    _frameCounters = passState;
    // Taken at the top of the frame and cleared here, so a request made while
    // this frame is encoding is the *next* frame's — `gfx-70n`.
    final capturing = _captureWanted;
    _captureWanted = null;
    _capture = capturing == null
        ? null
        : FrameCaptureBuilder(width: width, height: height);
    try {
      for (var i = 0; i < frameGraph.order.length; i++) {
        resources.beginNode(i);
        final node = frameGraph.order[i] as RenderNode;
        // **Differenced rather than counted per node** — `gfx-01n`. The
        // counters live on `passState` because a draw is encoded deep inside
        // the mesh encoder, which has no idea which graph node called it, and
        // threading a node identity down there to be incremented would put
        // the profiler's concern into every drawing path in the engine.
        // Reading the running totals either side of `execute` asks the same
        // question from outside and costs three integers a pass.
        final drawsBefore = passState.drawCalls;
        final trianglesBefore = passState.triangles;
        final switchesBefore = passState.pipelineSwitches;
        final passClock = Stopwatch()..start();
        // One span and one pass label per node, named by the node — `H2`.
        // The label reaches every pass the node opens through this renderer,
        // so a GPU debugger and `GraphicsDevice.onGpuTimings` see the graph's
        // own names rather than a pass nobody can place.
        _passLabel = node.name;
        developer.Timeline.startSync(node.name);
        try {
          node.execute(
            NodeFrame(
              device: device,
              resources: resources,
              services: this,
              state: passState,
              settings: settings,
              // `R2`: after the temporal resolve, the output's size.
              width: _outputSized.contains(node) ? _outputWidth : width,
              height: _outputSized.contains(node) ? _outputHeight : height,
              // Only for a node that asked for it. This convenience used to
              // hand the scene colour to every node in the frame, including
              // the shadow passes that run before one exists and never wanted
              // it — a read the graph was never told about, ordered against
              // nothing. It was invisible until an undeclared read became an
              // error.
              //
              // Still `tryTexture` for the nodes that did declare it: the
              // scene runs first and a node drawing over the world has to cope
              // with there being nothing yet. The view model returns early.
              sceneColor:
                  frameGraph.readVersionOf(i, FrameResourceIds.hdrColour) ==
                      null
                  ? null
                  : resources.tryTexture(FrameResourceIds.hdrColour),
            ),
          );
        } finally {
          developer.Timeline.finishSync();
          _passLabel = null;
        }
        passTimings.add((
          name: node.name,
          active: node.isActive,
          micros: passClock.elapsedMicroseconds,
          // The last timings a measuring device reported for this node,
          // which are a frame or two old — see `_lastGpuMicros`. Null where
          // the device does not measure, or has not reported this node yet.
          gpuMicros: _lastGpuMicros[node.name],
          drawCalls: passState.drawCalls - drawsBefore,
          triangles: passState.triangles - trianglesBefore,
          pipelineSwitches: passState.pipelineSwitches - switchesBefore,
        ));
        // **Before `endNode`, which is the whole point** — `gfx-70n`. That call
        // is where a version whose last reader has passed goes back to the
        // pool, and the next pass draws over it. A capture taken after the
        // frame would hold whatever the last pass to borrow that shape left
        // there, attributed to whichever pass wrote it first.
        _capture?.record(node, device: device, lookup: resources.tryTexture);
        resources.endNode(i);
      }
    } catch (error, stack) {
      // Only on the way out. On the ordinary path every version has already
      // retired at the node that last used it, and releasing again from here
      // would hand one texture back twice.
      resources.releaseAll();

      // The frame's questions go down with the frame. They were taken off
      // `_pendingPicks` above, so no later frame will see them, and `dispose`
      // will not either; a completer nobody finishes is an editor awaiting a
      // click for ever. A question the id node had already handed to the
      // device is answered by the device — and refused here first, since the
      // frame it belongs to did not happen — which is why the readback's own
      // answer checks before it completes.
      _failPicks(picks, error, stack);

      // A capture of a frame that threw is exactly the capture somebody wanted,
      // so it is handed over rather than dropped — it holds every pass up to
      // the one that broke, which is where the reader is going to look.
      _completeCapture(capturing);

      // **And the counter has to move, or the deferral this frame just relied
      // on is a frame that never happened.** Releases go into slot
      // `_frameIndex % 3` and are retired at the top of frame N + 3; leaving
      // the counter where it is means the very next `render` drains the slot
      // these were just put in, handing pooled targets back with no deferral
      // at all — which is exactly the failure the ring exists to prevent, and
      // it happens on the path where a frame is *already* going wrong. The
      // comment beside the increment below explains why one frame is not
      // enough; zero is worse.
      _abandonFrame();
      rethrow;
    } finally {
      // Cleared whichever way the frame ended: a counter left pointing at a
      // frame that is over would be incremented by the next `drawFullscreen`
      // somebody makes outside one — `renderPost` is exactly that call — and
      // the number would land in a report nobody is reading any more.
      _frameCounters = null;
    }
    _completeCapture(capturing);

    // Out of the nodes rather than out of the calls, which is the shape of
    // every one of these: the frame reports what its passes counted. The draws
    // themselves went into `passState` where they happened.
    final scenePass = sceneNode.result!;
    final debugLines = scenePass.debugLines + compositeNode.overlayLines;

    // Out of the graph, not out of this object's field. They are the same
    // texture while the composite is the last thing that writes `frame`, and
    // the point is that nothing here should be relying on that: a pass
    // registered after it produces a newer version, and returning `_ldrColor`
    // would hand the caller the composite's output while the later pass drew
    // into a texture nobody ever looked at.
    //
    // The fallback is for a frame whose composite was culled — a graph that
    // produced no version of `frame` at all — where the engine's own target is
    // genuinely all there is.
    final frame = resources.output(FrameResourceIds.frame) ?? _ldrColor!;

    // After every pass, so that nothing drawn this frame read its own state
    // back as last frame's. The view-projections are the unjittered ones, the
    // same matrices the scene pass derived, because a reprojection has to
    // undo motion and not the jitter.
    if (settings._wantsVelocity) frameHistory.tracking = true;
    if (frameHistory.tracking) {
      frameHistory.endFrame(
        frame: _frameIndex,
        meshes: scene.meshes,
        views: <(CameraNode, vm.Matrix4)>[
          for (final view in views)
            if (_viewportPixels(view.viewportFraction, width, height)
                case final rect)
              (
                view.camera,
                view.camera.viewProjection(rect.width / rect.height),
              ),
        ],
      );
    }

    // The frame is encoded and submitted: everything it released is in this
    // slot, and the next two frames must not touch it.
    _frameIndex++;

    // And the picture goes back into rotation when the work that read it is
    // done — not a fixed number of frames later, which is a guess this engine
    // got wrong three times.
    _recycleLdrFrame();
    frameClock.stop();
    developer.Timeline.finishSync();

    // A frame that drew nothing says why, once, in debug builds. Once because
    // the cause is a standing state of the scene rather than an event: a scene
    // with nothing in it draws nothing sixty times a second, and a message per
    // frame buries the one that mattered under a thousand copies of itself.
    // The counter resets as soon as a frame draws, so the *next* black screen
    // is reported as its own.
    assert(() {
      if (passState.drawCalls > 0) {
        _emptyFrameReported = false;
        return true;
      }
      if (_emptyFrameReported) return true;
      final why = describeEmptyFrame(scene, views);
      if (why != null) {
        _emptyFrameReported = true;
        developer.log(why, name: 'flutter3d');
      }
      return true;
    }());

    return FrameResult(
      frame: frame,
      // Asked for and not given. Computed here rather than plumbed out of the
      // scene pass, because it is a fact about the settings and the device
      // rather than about anything that happened during the frame.
      wireframeDeclined: settings.wireframe && !device.supportsWireframe,
      // `gfx-20n`. Half of it comes from the scene pass, which knows what it
      // attached, and half from the graph, which knows whether the node ran.
      // Neither half can answer alone, which is why the answer is assembled
      // here rather than reported by one of them.
      antiAliasing: EffectiveAntiAliasing(
        msaaSamples: scenePass.msaaSamples,
        fxaa: passTimings.any((p) => p.name == 'antialias'),
        msaaDeclined: scenePass.msaaDeclined,
        // Whether the resolve ran, which asking the setting would not say: a
        // device with one colour attachment has no surface buffer, and the
        // node is refused there.
        temporal: passTimings.any((p) => p.name == 'temporal resolve'),
      ),
      cpuMicros: frameClock.elapsedMicroseconds,
      submitMicros: scenePass.submitMicros,
      drawCalls: passState.drawCalls,
      triangles: passState.triangles,
      instances: passState.instances,
      culled: scenePass.culled,
      pipelineSwitches: passState.pipelineSwitches,
      debugLines: debugLines,
      lights: lights.count,
      lightsDropped: scenePass.lightOverflow,
      pipelines: _pipelineCache.length,
      shadowCasters: _shadowCasters,
      shadowsDenied: _shadowsDenied,
      batchedDraws: _batchedDraws,
      skinnedDraws: passState.skinnedDraws,
      exposure: _lastExposure,
      passes: passTimings,
      // Read off the compiled graph rather than recomputed here: the reasons
      // are the compile's own answers, and a second derivation is a second
      // thing to disagree with the frame.
      skipped: frameGraph.skipped,
    );
  }

  /// Puts this frame's finished-frame texture back into rotation once the
  /// work that read it is done.
  void _recycleLdrFrame() {
    final drawnInto = _ldrCurrent;
    if (drawnInto == null) return;
    // **The membership test belongs inside the callback, not beside it.**
    // Asked here it is a question about the world at registration time, and
    // the callback runs later — on Impeller, from the command buffer's
    // completion or from the next `beginFrame`. In between, a resize can run
    // `_ensureTargets`, which empties `_ldrFrames` and `_ldrFree` because
    // every one of them is the wrong size now. The callback then pushed a
    // texture of the previous window size into the freshly emptied free
    // list, `_takeLdrFrame` popped it without rechecking, and the next
    // composite went into a target the size of the window before last.
    //
    // WebGL and the software backend never showed it: their
    // `onFrameComplete` runs synchronously, so there is no in-between. That
    // is every desktop and mobile build, on any window drag.
    device.onFrameComplete(() {
      if (_ldrFrames.contains(drawnInto)) _ldrFree.add(drawnInto);
    });
  }

  /// What a frame that threw still owes before the exception leaves [render].
  ///
  /// **The counter moves**, or the releases this frame queued are retired by
  /// the very next `render` with no deferral at all. **The finished-frame
  /// texture goes back into rotation**: it was taken off the free list at the
  /// top, and a frame that failed without returning it left it in
  /// `_ldrFrames` for ever, so every failed frame grew the ring by one
  /// full-screen texture. **And the timeline block closes**, or every later
  /// frame's markers nest inside one that never ends.
  void _abandonFrame() {
    _frameIndex++;
    _recycleLdrFrame();
    developer.Timeline.finishSync();
  }

  /// Bloom and the composite — tone map, look, debug overlay — over an
  /// already-rendered HDR colour buffer, standalone.
  ///
  /// `pro-eng-03`'s own row. [hdr] arrives from outside this method's own
  /// graph rather than from a node registered in it, so it is registered
  /// with [FrameGraph.addExternal] at version zero — the first real caller
  /// that primitive has had since the migration [_compileFrameGraph]'s own
  /// doc comment describes ("nothing is external any more"). Bloom is the
  /// one reader: it consumes `hdr_colour@0` and writes `bloom@1`, and the
  /// graph this method builds never asks for a version of `hdr_colour`
  /// past zero — nothing here registers a node that would produce one.
  /// `frame_graph_test.dart`'s own coverage is what happens when something
  /// does: a read the graph cannot trace to a producer is refused at
  /// [FrameGraph.compile], before a single pass runs.
  ///
  /// Reflections and ambient occlusion are deliberately not part of this
  /// call: both read the surface (G-)buffer the scene pass writes, which a
  /// caller handing in only a finished colour buffer has no way to supply.
  /// A scene rendered with `RenderSettings.reflections` and
  /// `.ambientOcclusion` off, and `.bloom`/composite left to this method
  /// rather than run inline, reproduces the exact picture [render] would
  /// have drawn whole for the same scene and settings with every effect
  /// on — see `renderer_post_standalone_test.dart`'s own `post-only` scene,
  /// this row's own acceptance.
  ///
  /// [keepHdr] additionally returns the bloomed-but-not-yet-tonemapped HDR
  /// buffer as [PostFrameResult.hdr], for a caller with another
  /// linear-space step still to run before display. Left null otherwise —
  /// a pooled texture nobody outside this call has a reason to hold onto.
  ///
  /// [target] is where the tonemapped result is drawn; a caller that omits
  /// it gets a freshly allocated texture in the device's own default colour
  /// format, owned by the caller from the moment this method returns — it
  /// is not pooled, the way [render]'s own `frame` is, because nothing here
  /// knows when a standalone caller is done with it. Release it with
  /// `GraphicsDevice.releaseTexture` once it is.
  PostFrameResult renderPost({
    required TextureHandle hdr,
    RenderSettings settings = const RenderSettings(),
    bool keepHdr = false,
    TextureHandle? target,
  }) {
    developer.Timeline.startSync('Renderer.renderPost');
    final clock = Stopwatch()..start();

    final bloomNode = _BloomNode(this, settings.bloom);
    final graph = FrameGraph()
      ..addExternal(FrameResourceIds.hdrColour)
      ..addNode(bloomNode);
    // The same `disabledPasses` the full frame honours, narrowed to the one
    // node this graph has. Without the narrowing a perfectly good set — the
    // one a caller uses for their full frames, naming `ssao` or `antialias` —
    // would be rejected here as a misspelling, because this graph genuinely
    // does not have those nodes. Narrowed rather than validated, then: the
    // typo check belongs to the frame that has all the names, and this path
    // deliberately has one.
    final postDisabled = settings.disabledPasses
        .where((name) => name == bloomNode.name)
        .toSet();
    final compiled = graph.compile(
      disabled: postDisabled,
      outputs: <ResourceId>[
        if (bloomNode.isActive && postDisabled.isEmpty) FrameResourceIds.bloom,
      ],
    );

    final resources =
        FrameResources(
            source: _DeferredTextureSource(this),
            graph: compiled,
            frameWidth: hdr.width,
            frameHeight: hdr.height,
          )
          // Half the frame in HDR, the same declaration `_compileFrameGraph`
          // gives it — a resource is named the same way wherever it is
          // produced.
          ..declare(
            ResourceDesc(
              id: FrameResourceIds.bloom,
              format: hdrFormat,
              size: const FrameFraction(2),
            ),
          );
    // Between nodes, which is what binds a name's version zero rather than a
    // node's own output — see `FrameResources.provide`'s own doc comment.
    resources.provide(FrameResourceIds.hdrColour, hdr);

    // Unlike `render`'s own loop, nothing here reads `bloom` back through the
    // graph — composite is called directly below rather than registered as a
    // node, precisely to avoid its own hardcoded `_ldrColor` target (see the
    // doc comment above). With no reader declared, `bloom`'s last use is its
    // own write, at this one node's own index, and `endNode` hands a
    // resource back to the pool the moment its last use has passed — so it
    // has to be read *before* `endNode` runs, not after, the one place this
    // loop cannot simply mirror `render`'s.
    TextureHandle? bloom;
    final passState = FramePassState();
    for (var i = 0; i < compiled.order.length; i++) {
      resources.beginNode(i);
      (compiled.order[i] as RenderNode).execute(
        NodeFrame(
          device: device,
          resources: resources,
          services: this,
          state: passState,
          settings: settings,
          width: hdr.width,
          height: hdr.height,
          sceneColor: hdr,
        ),
      );
      bloom = resources.tryTexture(FrameResourceIds.bloom);
      resources.endNode(i);
    }

    final output =
        target ??
        device.createTexture(
          RenderTargetSpec(
            width: hdr.width,
            height: hdr.height,
            format: device.defaultColorFormat,
            storageMode: StorageMode.devicePrivate,
          ),
        );

    _encodeComposite(
      target: output,
      scene: hdr,
      bloom: bloom,
      ao: null,
      // No scene and so no surface buffer to march through: this path composites
      // an HDR image somebody handed in, and a contact shadow is a fact about
      // geometry rather than about a picture.
      contactShadow: null,
      surface: null,
      shadowView: null,
      sceneGraph: Scene(),
      views: const <RenderView>[],
      settings: settings,
      width: hdr.width,
      height: hdr.height,
    );

    clock.stop();
    developer.Timeline.finishSync();

    return PostFrameResult(
      frame: output,
      hdr: keepHdr ? hdr : null,
      cpuMicros: clock.elapsedMicroseconds,
    );
  }

  Float32List get _ssaoParams => _ssaoInfo.params;
  Float32List get _ssaoScreen => _ssaoInfo.screen;
  Float32List get _ssaoCameraData => _ssaoInfo.camera;
  final vm.Vector3 _ssaoCamera = vm.Vector3.zero();
  Float32List get _ssaoForwardData => _ssaoInfo.forward;
  final vm.Vector3 _ssaoForward = vm.Vector3.zero();

  /// Draws into two colour attachments and reports what came back.
  ///
  /// A probe rather than a feature: `RenderTarget.colorAttachments` is a list
  /// and `setColorBlendEnable` takes an attachment index, so MRT looks supported
  /// — but "looks supported in the bindings" has been wrong twice in this
  /// project already, and the deferred-style effects that would depend on it are
  /// worth nothing if the second attachment is silently dropped.
  ///
  /// Returns a human-readable verdict. Costs two 4x4 textures, released before
  /// it returns, and one draw, and is only called when asked for.
  Future<String> probeMultipleRenderTargets() async {
    final probe = shaders['MrtProbe'];
    if (probe == null) return 'MRT probe: the bundle has no MrtProbe entry.';

    // `gfx-50n`. **This is the line the probe was missing, and its absence
    // was the joke in it**: the diagnostic that exists to find out whether a
    // second attachment works used to find out by opening one, which on the
    // backend where the answer is no ends the process. A diagnostic that
    // cannot survive its own bad news is not a diagnostic. The device is
    // asked first, and a device that says one is reported rather than tried.
    if (device.maxColorAttachments < 2) {
      return 'MRT probe: this device opens at most '
          '${device.maxColorAttachments} colour attachment, so the probe was '
          'not run — see GraphicsDevice.maxColorAttachments. Every pass that '
          'reads the surface buffer is culled on this device and reported as '
          'starved.';
    }

    const size = 4;
    TextureHandle makeTarget() => device.createTexture(
      RenderTargetSpec(
        width: size,
        height: size,
        format: device.defaultColorFormat,
      ),
    );

    final first = makeTarget();
    final second = makeTarget();

    try {
      final pass = device.beginRenderPass(
        RenderPassDescriptor(
          label: _passLabel,
          colors: <ColorTarget>[
            ColorTarget(texture: first, clearValue: vm.Vector4.zero()),
            ColorTarget(texture: second, clearValue: vm.Vector4.zero()),
          ],
        ),
      );

      final full = ScreenRect(width: size, height: size);
      pass.setState(_kFullscreenState.copyWith(viewport: full, scissor: full));
      // The second attachment, which is the whole point of this probe. One
      // `PassState` describes one attachment's blending; a second is a second
      // call, and inventing a list of them for a diagnostic nothing else needs
      // would be inventing the semantics of the general case too.
      pass.setBlend(null, attachment: 1);

      pass.bindPipeline(device.createPipeline(fullscreenVertexShader, probe));
      pass.bindVertexBuffer(_fullscreenTriangle, 3);
      pass.bindIndexBuffer(_identityIndices(3), IndexType.int32, 3);
      pass.draw();
      pass.submit();

      // asImage plus toByteData is the only readback path available: there is
      // no buffer readback on this backend at all.
      final a = await device.readPixels(first);
      final b = await device.readPixels(second);
      if (a == null || b == null) {
        return 'MRT probe: readback returned nothing.';
      }

      String describe(ByteData data) =>
          '(${data.getUint8(0)}, ${data.getUint8(1)}, ${data.getUint8(2)})';

      // The shader writes distinct constants, so equal targets mean the second
      // attachment received a copy of the first rather than its own output.
      final same =
          a.getUint8(0) == b.getUint8(0) && a.getUint8(2) == b.getUint8(2);
      return 'MRT probe: attachment 0 ${describe(a)}, attachment 1 '
          '${describe(b)} — ${same ? 'IDENTICAL, so the second output was not '
                    'honoured' : 'distinct, so MRT works'}.';
    } catch (error) {
      return 'MRT probe: threw $error';
    } finally {
      // Given back whichever way the probe ended: both readbacks have been
      // awaited, so nothing is still reading them, and on WebGL2 a texture
      // nobody releases is a driver object for the life of the context.
      device
        ..releaseTexture(first)
        ..releaseTexture(second);
    }
  }

  /// Converts a display-referred colour into the linear light the scene target
  /// holds. Alpha is coverage, not light, so it passes through.
  static vm.Vector4 _srgbToLinear(vm.Vector4 color) {
    double channel(double c) => c <= 0.04045
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    return vm.Vector4(
      channel(color.x),
      channel(color.y),
      channel(color.z),
      color.w,
    );
  }

  /// Returns a pooled texture once the GPU can no longer be reading it.
  ///
  /// `CommandBuffer.submit` is asynchronous, so a texture handed back at the end
  /// of a frame can still be in flight. Reusing it immediately produces the same
  /// class of bug the host-buffer ring exists to prevent — flicker under load,
  /// not a crash — so releases wait out the frames in flight.
  void _releaseAfterFrame(TextureHandle texture) {
    _pendingRelease[_frameIndex % _kFramesInFlight].add(texture);
  }

  final List<List<TextureHandle>> _pendingRelease =
      List<List<TextureHandle>>.generate(
        _kFramesInFlight,
        (_) => <TextureHandle>[],
      );

  /// Frees a texture this renderer owns outright, once the GPU can no longer be
  /// reading it.
  ///
  /// The twin of [_releaseAfterFrame], and the difference is who owns the
  /// texture. That one hands a *pooled* target back to the pool for reuse;
  /// this one gives a target the renderer made itself back to the device,
  /// because it is the wrong size or the wrong shape now and will never be
  /// wanted again.
  ///
  /// **Reallocation was a drop, not a free.** A resize remakes the HDR target,
  /// the surface buffer, the reflection buffer, the depth attachments and the
  /// MSAA ones — six or seven full-screen textures — and a change of
  /// `cubeResolution` remakes two shadow atlases that are 75 MB each at the
  /// default tile. Every one of those was replaced by assigning over the field.
  /// Where dropping the last reference frees, that is the whole story; on
  /// WebGL2 nothing frees a `WebGLTexture` but `gl.deleteTexture`, so a person
  /// resizing a browser window walked the tab towards a lost context.
  ///
  /// Through the same ring as the pool for the same reason: `submit` is
  /// asynchronous, and the frame that was drawn with the old target may still
  /// be reading it.
  void _destroyAfterFrame(TextureHandle? texture) {
    if (texture == null) return;
    _pendingDestroy[_frameIndex % _kFramesInFlight].add(texture);
  }

  final List<List<TextureHandle>> _pendingDestroy =
      List<List<TextureHandle>>.generate(
        _kFramesInFlight,
        (_) => <TextureHandle>[],
      );

  /// Builds and submits the debug overlay for one view. Returns false when there
  /// was nothing to draw.
  ///
  /// The whole overlay is a single `PrimitiveType.line` draw out of the
  /// per-frame host buffer, indexed through the identity sequence because the
  /// API has no unindexed draw, so switching it on costs one buffer write and
  /// one draw call no matter how much it shows.
  bool _encodeDebugLines({
    required PassEncoder encoder,
    required Scene scene,
    required RenderView view,
    required vm.Matrix4 viewProjection,
    required double aspect,
    required RenderSettings settings,
  }) {
    if (!settings.debug.anyEnabled && settings.highlighted.isEmpty) {
      return false;
    }

    developer.Timeline.startSync('DebugDraw.build');
    debugDraw.buildForScene(
      scene,
      settings.debug,
      activeCamera: view.camera,
      aspect: aspect,
      highlighted: settings.highlighted,
    );
    // Trimmed to what the camera can see before it is uploaded — see
    // [DebugDraw.clipToNearPlane]. A line list goes straight to the hardware,
    // so the near plane is the engine's to respect.
    debugDraw.clipToNearPlane(viewProjection);
    developer.Timeline.finishSync();
    if (debugDraw.isEmpty) return false;

    developer.Timeline.startSync('DebugDraw.encode');
    // The mesh draws left an index buffer bound; this draw is non-indexed, and
    // a stale index buffer would make it read triangle indices as line vertices.
    encoder.clearBindings();

    encoder.bindPipeline(
      _debugLinePipeline ??= device.createPipeline(
        debugLineVertexShader,
        debugLineFragmentShader,
      ),
    );
    encoder.setState(_kDebugLineState);

    final vertexCount = debugDraw.vertexCount;
    encoder.bindVertexData(debugDraw.vertexBytes, vertexCount);
    encoder.bindIndexBuffer(
      _identityIndices(vertexCount),
      IndexType.int32,
      vertexCount,
    );
    _lineInfo.viewProjection.setAll(0, viewProjection.storage);
    encoder.bindBlock(debugLineVertexShader, _lineInfo);

    encoder.draw();
    developer.Timeline.finishSync();
    return true;
  }

  /// A view over the identity index sequence, growing the backing buffer when
  /// the overlay outgrows it.
  GeometryBuffer _identityIndices(int count) =>
      _debugIndices.view(device, count);
}
