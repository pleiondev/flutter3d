import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart' as vm;

import 'package:flutter3d_hal/flutter3d_hal.dart';
import '../geometry/mesh_geometry.dart';
import '../scene/camera_node.dart';
import '../scene/light_buffer.dart';
import '../scene/light_node.dart';
import '../scene/mesh_node.dart';
import '../scene/scene.dart';
import '../scene/scene_node.dart';
import 'composite_mix.dart';
import 'debug_draw.dart';
import 'lighting_model.dart';
import 'material.dart';
import 'render_list.dart';
import 'frame_graph.dart';
import 'frame_plan.dart';
import 'frame_resources.dart';
import 'render_node.dart';
import 'pass_contributor.dart';
import 'render_view.dart';
import 'shadow_slots.dart';

/// Uniform-block names as seen by shader reflection.
///
/// Impeller reflects a uniform block under its struct TYPE name, so
/// `uniform FrameInfo { ... } frame_info;` is looked up as `FrameInfo`. Using
/// the variable name instead is not an error at bind time — it just reflects as
/// a missing block, which surfaces much later as "no uniform block named ...".
const String _kReflectionInfoBlock = 'ReflectionInfo';
const String _kFrameInfoBlock = 'FrameInfo';
const String _kFragInfoBlock = 'FragInfo';
const String _kFogInfoBlock = 'FogInfo';
const String _kLineInfoBlock = 'LineInfo';
const String _kSkinInfoBlock = 'SkinInfo';
const String _kBloomInfoBlock = 'BloomInfo';
const String _kCompositeInfoBlock = 'CompositeInfo';

/// Texture slots, unlike uniform blocks, are reflected under the variable name.
const String _kAlbedoTextureSlot = 'base_color_texture';
const String _kNormalTextureSlot = 'normal_texture';
const String _kMetallicRoughnessTextureSlot = 'metallic_roughness_texture';
const String _kOcclusionTextureSlot = 'occlusion_texture';
const String _kEmissiveTextureSlot = 'emissive_texture';
const String _kShadowTextureSlot = 'shadow_texture';
const String _kPostSourceSlot = 'source_texture';
const String _kSceneTextureSlot = 'scene_texture';
const String _kBloomTextureSlot = 'bloom_texture';

/// Scene-wide shading knobs that are not per-material.
/// Screen-space reflections.
///
/// Off by default: it costs a full-screen pass and the surface buffer that
/// feeds it, and a level lit by torches in a stone corridor gains less from it
/// than a wet floor would.
final class ReflectionSettings {
  const ReflectionSettings({
    this.enabled = false,
    this.steps = 24,
    this.stride = 0.18,
    this.thickness = 0.006,
    this.intensity = 0.7,
    this.debugOnly = false,
  });

  final bool enabled;

  /// March steps. The shader's loop is bounded at 64 whatever this says,
  /// because a loop a uniform can lengthen without limit is a hang.
  final int steps;

  /// World metres between samples. Longer reaches further and steps over thin
  /// geometry; shorter is accurate and stops sooner.
  final double stride;

  /// How thick a surface is assumed to be, in window depth. Without an upper
  /// bound on the depth difference, a ray passing in front of a distant wall
  /// counts as hitting it.
  final double thickness;

  final double intensity;

  /// Shows only what the march found, on black.
  ///
  /// Added because a reflection added to a lit scene is indistinguishable from
  /// a specular highlight, and I mistook one for the other: a streak on a wet
  /// floor turned out to be the point light, and the reflection was
  /// contributing nothing at all.
  final bool debugOnly;
}

/// Distance fog.
///
/// Exponential per metre, which is what the level format already stores. A
/// linear fog has a visible plane where it begins, and a dungeon corridor is
/// exactly where that shows.
final class FogSettings {
  const FogSettings({this.color, this.density = 0.0});

  /// Linear, not sRGB: it is mixed with scene light before the display
  /// transform, and an sRGB value here reads as a fog too bright at the near
  /// end and too dark at the far one.
  ///
  /// Null takes the default, which is a neutral dark grey. Neutral on
  /// purpose: fog replaces the surface colour entirely at distance, so any
  /// tint in it becomes the colour of everything far away — and a tint that
  /// looks subtle in a swatch does not look subtle when it is the whole far
  /// end of a corridor.
  final vm.Vector3? color;

  vm.Vector3 get resolvedColor => color ?? _defaultColor;

  /// Per metre. Zero is no fog, and costs a compare in the shader.
  final double density;

  bool get enabled => density > 0.0;

  static final vm.Vector3 _defaultColor = vm.Vector3(0.05, 0.05, 0.05);
}

final class RenderSettings {
  const RenderSettings({
    this.specular = 1.0,
    this.exposure = 1.6,
    this.wireframe = false,
    this.backfaceCulling = true,
    this.debug = const DebugDrawOptions(),
    this.highlighted = const <SceneNode>[],
    this.tonemap = true,
    this.bloom = const BloomSettings(),
    this.shadows = const ShadowSettings(),
    this.surfaceBuffer = false,
    this.showSurfaceBuffer = false,
    this.showShadowMap = false,
    this.showPointShadowDebug = false,
    this.reflections = const ReflectionSettings(),
    this.fog = const FogSettings(),
  });

  final double specular;

  /// Linear multiplier applied before tone mapping.
  ///
  /// The default is a demo choice, not a physical constant: with light intensity
  /// at a unitless 1.0 the scene's brightest values land around linear 0.6, so
  /// the tone mapper's shoulder would otherwise go unused and the image would
  /// read as under-exposed. A real engine derives this from photometric light
  /// units or auto-exposure.
  final double exposure;
  final bool wireframe;
  final bool backfaceCulling;

  /// Which debug overlays to draw on top of the scene.
  final DebugDrawOptions debug;

  /// Nodes to outline, typically whatever picking last selected.
  final List<SceneNode> highlighted;

  /// Whether the composite pass applies the tone curve.
  ///
  /// On for anything that renders light. Off for a debug view, where the colour
  /// is not a light value at all and a tone curve would corrupt it — a normal
  /// encoded as RGB has no business being rolled off.
  final bool tonemap;

  final BloomSettings bloom;

  final ShadowSettings shadows;

  /// Whether the scene pass writes its second attachment: world-space normal
  /// and depth, for a screen-space effect to read.
  ///
  /// Off by default because it costs a store per pixel and nothing reads it
  /// unless asked. The shaders write it either way — a pipeline may declare
  /// more outputs than its target has attachments — so this is purely whether
  /// anybody is listening.
  final bool surfaceBuffer;

  /// Composites the surface buffer instead of the scene.
  ///
  /// The only way to find out whether the normals in it are right side up
  /// before something starts reflecting off them. Tone mapping and exposure
  /// are skipped for it: a normal encoded as a colour is not a light value,
  /// and a tone curve applied to one turns a wrong answer into a plausible
  /// picture.
  ///
  /// Implies [surfaceBuffer]; asking to see a buffer nobody filled would show
  /// whatever was in the texture last.
  final bool showSurfaceBuffer;

  final ReflectionSettings reflections;

  final FogSettings fog;

  /// Composites the shadow map instead of the scene.
  ///
  /// A shadow map is the one buffer in the renderer that nothing has ever
  /// shown. It is about to hold a cube atlas, and an atlas whose contents
  /// nobody can look at is an atlas whose layout nobody can check.
  final bool showShadowMap;

  /// Paints the point shadow's penumbra estimate into the surface buffer, and
  /// shows that instead of the lit image.
  ///
  /// Red: the penumbra width, against the widest allowed. Green: how far the
  /// blocker was, against the light's range. Blue: the search found nothing.
  ///
  /// It exists because two explanations for a broken contact-hardening estimate
  /// were argued from the finished picture and both turned out wrong. The
  /// quantity that settles it never leaves the shader, and nothing displayed
  /// it — so the debugging was five runs of guessing where it should have been
  /// one run of looking.
  final bool showPointShadowDebug;

  /// Whether the scene pass should write the surface buffer at all.
  ///
  /// Three flags OR-ed by hand, which is the shape the frame graph exists to
  /// replace: it is a dependency between passes written as a boolean, and it
  /// has to be edited every time a feature learns to read the buffer. The
  /// graph answers the same question by asking whether any surviving pass
  /// declares a read — [CompiledFrameGraph.isConsumed], which the scene node
  /// now asks of the graph the frame is actually running. Kept because it is
  /// public API.
  ///
  /// It cannot be the answer the renderer uses, because a setting cannot see
  /// the frame. Whether the buffer is wanted depends on what a *node* declared
  /// — an application's own node reading it is invisible from here — and the
  /// only thing that knows is the compiled graph.
  ///
  /// So the two are allowed to disagree, and the disagreement is one-sided: an
  /// application that registers a node reading the buffer gets it, and this
  /// getter still says false. There was a test walking all sixteen combinations
  /// of the flags for agreement; it went with the frame description it was
  /// written against, because it could only ever have compared this against a
  /// model of the built-in passes, which is the half of the question that was
  /// never in doubt.
  bool get needsSurfaceBuffer =>
      surfaceBuffer ||
      showSurfaceBuffer ||
      showPointShadowDebug ||
      reflections.enabled;

  RenderSettings copyWith({
    double? specular,
    double? exposure,
    bool? wireframe,
    bool? backfaceCulling,
    DebugDrawOptions? debug,
    List<SceneNode>? highlighted,
    bool? tonemap,
    BloomSettings? bloom,
    ShadowSettings? shadows,
  }) =>
      RenderSettings(
        specular: specular ?? this.specular,
        exposure: exposure ?? this.exposure,
        wireframe: wireframe ?? this.wireframe,
        backfaceCulling: backfaceCulling ?? this.backfaceCulling,
        debug: debug ?? this.debug,
        highlighted: highlighted ?? this.highlighted,
        tonemap: tonemap ?? this.tonemap,
        bloom: bloom ?? this.bloom,
        shadows: shadows ?? this.shadows,
      );
}

/// Directional shadow mapping settings.
/// Which faces of a caster are drawn into a shadow map.
///
/// The two ways a shadow map fails are opposites, and this picks which one to
/// risk. Recording the light-facing side means a lit surface is compared
/// against its own depth and shows acne; recording the far side moves the
/// recorded surface inside the solid, which cures the acne and instead lets a
/// thin caster's shadow detach from it.
enum ShadowCasterFaces {
  /// Draw the faces turned towards the light. The general-purpose choice, and
  /// what flutter_scene defaults to; acne is held off by the biases.
  front,

  /// Draw the faces turned away — "second depth". For solid, closed geometry
  /// this removes acne outright, since the recorded distance is the far wall of
  /// the body and the bias hides inside it. This engine's cube pass has always
  /// done this without saying so, which suits a dungeon of blocky brushes.
  back,

  /// Draw both. Records the nearest surface as [front] does for closed bodies,
  /// but also catches a one-sided wall or an open shell, which the other two
  /// see straight through.
  both,
}

final class ShadowSettings {
  const ShadowSettings({
    this.enabled = true,
    this.resolution = 2048,
    this.bias = 0.0015,
    this.normalOffset = 0.02,
    this.strength = 1.0,
    this.depthPadding = 1.2,
    this.pointBias = 0.08,
    this.pointNormalOffset = 0.02,
    this.pointSoftness = 4.0,
    this.pointLightRadius = 0.0,
    this.pointMaxSoftness = 16.0,
    this.casterFaces = ShadowCasterFaces.back,
  });

  /// Distance bias for a point light's cube map, in **metres**.
  ///
  /// Metres rather than normalised depth because the cube faces store radial
  /// distance, not clip depth — see shadow_distance.frag for why they have to.
  final double pointBias;

  /// How far along the normal a cube-map sample moves before being projected,
  /// in metres, before the slope term is added.
  final double pointNormalOffset;

  /// Penumbra width for a point light, as a radius in texels of one cube face.
  ///
  /// Zero collapses the kernel to a single tap and a hard edge.
  ///
  /// Texels, not a fraction of the tile, so a penumbra keeps its width when the
  /// atlas resolution changes. The first value tried here was 0.9, which looked
  /// like a reasonable "small" default and did nothing at all: a face is 1024
  /// texels across, so every tap in the disk landed in the same texel as the
  /// centre and returned the same answer. 62 pixels of the whole frame moved.
  /// A kernel measured in texels has to be wider than one.
  ///
  /// Four is measured rather than judged: against an unfiltered edge, a radius
  /// of 2.5 texels moved 69 pixels of the frame and 20 texels moved 4861. The
  /// first is invisible and the second smears a contact shadow, so the default
  /// sits between them, at about the width flutter_scene gives a spot. This is
  /// a fixed radius, and with contact hardening on it becomes the *floor* on
  /// the width rather than the whole story: it is then only how sharp a
  /// contact edge is allowed to get.
  final double pointSoftness;

  /// The emitter's own radius, in metres. Zero uses a fixed kernel instead.
  ///
  /// **Off by default, because it does not work yet, and the cause is not yet
  /// known.** The estimate collapses to [pointSoftness] almost everywhere:
  /// raising this from 0.05 to 0.6 — twelve times — moves twenty pixels of the
  /// frame, where the width should scale with it directly.
  ///
  /// Two explanations were written down and both were measured wrong, which is
  /// worth recording so they are not proposed again:
  ///
  /// * *The blocker search finds the receiver's own floor.* No: the atlas holds
  ///   the caster only. `cube-shadow` shows one teapot silhouette and no
  ///   ground, because a single-sided floor is culled by [casterFaces].
  /// * *Second-depth recording defeats it* — PCSS wants the distance to the
  ///   near side of a blocker and [ShadowCasterFaces.back] records the far one,
  ///   which would shrink `receiver - blocker` for any thick body. Plausible,
  ///   and false: switching to [ShadowCasterFaces.front] moves 99 pixels
  ///   against the fixed kernel, the same as before.
  ///
  /// * *The ceiling pins it* — [pointMaxSoftness] clamps the estimate, so two
  ///   light radii could both be resting on the same maximum. Also false:
  ///   raising the ceiling from 16 to 64 texels moves 102 pixels.
  ///
  /// [RenderSettings.showPointShadowDebug] settled it, and the answer is that
  /// there was no collapse. Measured off the debug picture — in linear space,
  /// which is a correction in itself, since the surface buffer is linear and
  /// the composite writes sRGB — the radius spans 4 to 16 texels across the
  /// shadow, a quarter of the fragments at the floor and the rest spread above
  /// it. That is contact hardening doing its job.
  ///
  /// The premise was wrong instead. Widening the kernel in this scene moves
  /// about a hundred pixels whatever drives it: a *fixed* kernel tripled from
  /// 4 to 12 texels moves 110, contact hardening against a fixed 4 moves 96,
  /// and the ceiling raised fourfold moves 102. One early measurement said
  /// 4861 for a fixed 2.5 against 20 and every careful repeat since contradicts
  /// it; treat that number as suspect rather than as the target.
  ///
  /// `cube-shadow-gap` was then built for the one condition still missing — a
  /// caster well clear of the floor, where a penumbra has room to open — and it
  /// answers 27 pixels, less than the on-floor scene. So the premise itself was
  /// the error, and it is a matter of scale rather than of correctness: a face
  /// is 1024 texels across ninety degrees, the shadow covers a small part of
  /// the screen, and a few texels of extra blur in that map is worth about a
  /// pixel of softening on screen. Nothing was ever going to move thousands.
  ///
  /// Left off, then, because a second set of taps buys about a pixel at this
  /// map resolution — an honest cost/benefit, not a defect. It earns its place
  /// when a face covers less of the world per texel, or when the emitter is
  /// genuinely large; both are worth measuring before switching it on.
  ///
  /// This is what makes a shadow sharp where its caster meets the floor and
  /// soft a metre away, which one radius cannot be. A point light is a point
  /// only in the maths; a torch flame is about ten centimetres across, and that
  /// width is exactly what decides how fast its shadows spread.
  ///
  /// It costs a second set of taps — a search for what is blocking, before the
  /// filter that softens it — so it is a real expense rather than free realism.
  final double pointLightRadius;

  /// The widest a penumbra may get, in texels of one cube face.
  ///
  /// Two jobs: it stops a blocker close to the light from spreading a shadow
  /// across the whole room, and it sets how far the blocker search reaches,
  /// since a blocker beyond the widest allowed penumbra cannot widen anything.
  final double pointMaxSoftness;

  /// Which side of a caster the cube pass records.
  final ShadowCasterFaces casterFaces;

  final bool enabled;

  /// Edge length of the shadow map. One map, not a cascade: cascades are a
  /// second problem, and a single map fitted to the scene is enough to show
  /// whether the pass works at all.
  final int resolution;

  /// Depth bias, in the shadow camera's normalized depth. Fights the acne that
  /// comes from a surface being sampled at a slightly different depth than it
  /// was rendered at.
  final double bias;

  /// How far along the surface normal the sample point moves before being
  /// projected, in world units. Fixes the acne a depth bias cannot, because that
  /// error scales with the surface's slope rather than with depth.
  final double normalOffset;

  /// How dark a fully shadowed fragment gets, from 0 to 1.
  final double strength;

  /// How much room to leave around the scene bounds along the light's axis, as
  /// a multiplier. A caster just outside the fitted volume would otherwise be
  /// clipped out of the map and stop casting.
  final double depthPadding;

  ShadowSettings copyWith({
    bool? enabled,
    int? resolution,
    double? bias,
    double? normalOffset,
    double? strength,
    double? depthPadding,
    double? pointBias,
    double? pointNormalOffset,
    double? pointSoftness,
    double? pointLightRadius,
    double? pointMaxSoftness,
    ShadowCasterFaces? casterFaces,
  }) =>
      // Every field, and that is not bookkeeping. This method already dropped
      // the point-shadow settings on the floor: `settingsFrom` calls it once a
      // frame, so anything not listed here was silently reset to its default
      // and no amount of setting it would have had any effect. The same shape
      // of bug once meant a torch marked as a caster cast nothing.
      ShadowSettings(
        enabled: enabled ?? this.enabled,
        resolution: resolution ?? this.resolution,
        bias: bias ?? this.bias,
        normalOffset: normalOffset ?? this.normalOffset,
        strength: strength ?? this.strength,
        depthPadding: depthPadding ?? this.depthPadding,
        pointBias: pointBias ?? this.pointBias,
        pointNormalOffset: pointNormalOffset ?? this.pointNormalOffset,
        pointSoftness: pointSoftness ?? this.pointSoftness,
        pointLightRadius: pointLightRadius ?? this.pointLightRadius,
        pointMaxSoftness: pointMaxSoftness ?? this.pointMaxSoftness,
        casterFaces: casterFaces ?? this.casterFaces,
      );
}

/// How much of the frame's light spills into a glow.
final class BloomSettings {
  const BloomSettings({
    this.enabled = true,
    this.threshold = 1.0,
    this.knee = 0.5,
    this.intensity = 0.06,
    this.levels = 5,
    this.filterRadius = 1.0,
  });

  final bool enabled;

  /// Luminance above which a pixel starts to bloom. One is display white, which
  /// is the only value with a physical meaning: below it nothing is clipping,
  /// above it the display cannot show the difference and a lens would scatter.
  final double threshold;

  /// Width of the soft ramp below the threshold. A hard cut makes the glow
  /// appear along a visible contour as a highlight brightens through it.
  final double knee;

  final double intensity;

  /// How many halvings the chain does. Each one doubles the glow's reach, so
  /// this is the radius control; there is no mip pyramid to lean on because
  /// flutter_gpu has no mip levels at all.
  final int levels;

  /// Tent-filter radius, in source texels, used on the way back up.
  final double filterRadius;

  BloomSettings copyWith({
    bool? enabled,
    double? threshold,
    double? knee,
    double? intensity,
    int? levels,
    double? filterRadius,
  }) =>
      BloomSettings(
        enabled: enabled ?? this.enabled,
        threshold: threshold ?? this.threshold,
        knee: knee ?? this.knee,
        intensity: intensity ?? this.intensity,
        levels: levels ?? this.levels,
        filterRadius: filterRadius ?? this.filterRadius,
      );
}

/// One rendered frame.
final class FrameResult {
  const FrameResult({
    required this.frame,
    required this.cpuMicros,
    required this.submitMicros,
    required this.drawCalls,
    required this.culled,
    required this.pipelineSwitches,
    required this.debugLines,
    required this.lights,
    required this.lightsDropped,
    required this.pipelines,
    required this.shadowCasters,
    required this.skinnedDraws,
  });

  /// The texture the frame was drawn into.
  ///
  /// A handle and not a `ui.Image`, which is the whole of the change: an image
  /// is what *one* backend can produce for free, and asking every backend for
  /// one costs a GPU->CPU->GPU round trip on any that cannot. Show it with
  /// `GraphicsDevice.present`, read it with `GraphicsDevice.readPixels`, and
  /// let the backend decide which of those is cheap.
  ///
  /// It is the renderer's own target and is reused every frame, so it is valid
  /// until the next [Renderer.render] and not beyond.
  final TextureHandle frame;

  /// Wall-clock time spent inside [Renderer.render], submit included.
  ///
  /// This is what the renderer costs the UI thread. It is not the GPU cost: the
  /// frame is still executing when this number is taken.
  final int cpuMicros;

  /// Wall-clock time inside `CommandBuffer.submit`. Not a GPU timestamp —
  /// flutter_gpu exposes none — but enough to notice a regression.
  final int submitMicros;

  final int drawCalls;

  /// Meshes rejected by frustum culling, so the win is visible.
  final int culled;

  /// How often the pipeline changed. With sorting working this should be close
  /// to the number of distinct lighting models in view.
  final int pipelineSwitches;

  /// Line segments submitted by the debug overlay, zero when it is off.
  final int debugLines;

  /// Lights actually shaded this frame.
  final int lights;

  /// Lights that did not fit in the uniform array, so a scene that quietly
  /// stopped lighting its ninth lamp says so instead of looking wrong.
  final int lightsDropped;

  /// Pipelines the renderer has built so far.
  ///
  /// Reported per frame because it is the number that has to stay put: light
  /// count, light type and material values are all uniforms, and any of them
  /// pushing this up would mean a permutation had crept in where a uniform
  /// belonged. With no runtime shader compilation, that is not a slow path —
  /// it is a wrong one.
  final int pipelines;

  /// Meshes drawn into the shadow map, zero when the pass did not run.
  final int shadowCasters;

  /// Draws that went through the skinned vertex stage.
  final int skinnedDraws;
}

/// Draws a [Scene] through one or more [RenderView]s.
///
/// Still not a frame graph: one pass, one target, no post-processing. What it does
/// have is the structure the rest depends on — a scene it does not own, views it
/// does not assume, a culled and sorted render list, and a pipeline cache.
/// A scene drawn on top of the world, through its own camera.
///
/// The first-person weapon, and nothing else so far. It cannot simply be a
/// second [RenderView]: every view shares one depth buffer, so a weapon held
/// close to the eye would be buried the moment the player walked up to a wall.
/// Its own pass with the depth cleared is what puts it reliably in front.
///
/// A narrow field of view comes with it, and is the point rather than a detail.
/// The main camera is wide enough to see a room, and a model rendered at that
/// angle a few centimetres from the eye is grotesquely distorted at the edges.
final class Renderer implements RenderServices {
  Renderer._({
    required this.device,
    required this.vertexShader,
    required this.skinnedVertexShader,
    required this.debugLineVertexShader,
    required this.particleVertexShader,
    required this.particleFragmentShader,
    required this.debugLineFragmentShader,
    required this.fullscreenVertexShader,
    required this.bloomThresholdShader,
    required this.bloomDownsampleShader,
    required this.bloomUpsampleShader,
    required this.compositeShader,
    required this.reflectionShader,
    required this.fallbackAlbedo,
    required this.fallbackNormal,
    required this.msaaEnabled,
  }) : targetPool = RenderTargetPool(device);

  /// The backend, injected rather than reached for.
  ///
  /// The renderer names no graphics API at all: it holds one of these and hands
  /// the narrower [GraphicsDevice] view of it to every node and contributor. A
  /// second backend is a second implementation of this and nothing else, and a
  /// **fake** one is what makes a node's drawing testable off a device.
  final GraphicsDevice device;

  /// The bundle's stages, for anything looking one up by name.
  ShaderLibrary get shaders => device.shaders;

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

  T addNode<T extends RenderNode>(T node) => nodes.add(node);

  bool removeContributor(PassContributor c) => contributors.remove(c);

  bool removeNode(RenderNode node) => nodes.remove(node);

  final ShaderHandle vertexShader;

  /// The skinned vertex stage. A separate shader because joints and weights are
  /// vertex attributes, and flutter_gpu takes the layout from the `in`
  /// declarations — so a skinned mesh cannot share a shader with a static one
  /// however similar the body is.
  final ShaderHandle skinnedVertexShader;

  /// The debug overlay's own stage pair. Separate from the mesh shaders because
  /// the line buffer has a different vertex layout, and flutter_gpu takes the
  /// layout from the shader's `in` declarations.
  final ShaderHandle debugLineVertexShader;
  final ShaderHandle particleVertexShader;
  final ShaderHandle particleFragmentShader;
  final ShaderHandle debugLineFragmentShader;

  /// The post-processing stages. All of them share one vertex shader, because a
  /// full-screen pass differs only in its fragment work.
  final ShaderHandle fullscreenVertexShader;
  final ShaderHandle bloomThresholdShader;
  final ShaderHandle bloomDownsampleShader;
  final ShaderHandle bloomUpsampleShader;
  final ShaderHandle compositeShader;

  /// The screen-space reflection pass.
  final ShaderHandle reflectionShader;

  /// 1x1 opaque white, bound when a material has no base-colour texture.
  ///
  /// A shader that declares a sampler must have something bound to it, so
  /// "no texture" has to be a neutral texture rather than an absent binding.
  /// White is also neutral for the ORM, occlusion and emissive slots: it
  /// multiplies each factor by one, so the same texture serves all four.
  final TextureHandle fallbackAlbedo;

  /// 1x1 (0.5, 0.5, 1.0): the tangent-space normal that perturbs nothing.
  final TextureHandle fallbackNormal;

  final bool msaaEnabled;

  /// Which slot of the deferred-release ring this frame retires.
  ///
  /// The per-frame uniform allocators used to be rotated here too. They belong
  /// to the backend now — where a uniform's bytes live until the GPU has read
  /// them is a property of the API, not of the engine — and
  /// `GraphicsDevice.beginFrame` rotates them. The ring length is the same fact
  /// twice, which is why it is named once here and once there.
  int _frameIndex = 0;

  static const int _kFramesInFlight = 3;

  final RenderList _renderList = RenderList();

  /// Reused across frames, so a steady overlay allocates nothing.
  final DebugDraw debugDraw = DebugDraw();

  /// The scene's lights, repacked once per view.
  final LightBuffer lights = LightBuffer();

  // Uniform scratch, reused rather than rebuilt per draw. Writing a fresh
  // Float32List for every member of every draw is precisely the allocation
  // pattern the render list was shaped to avoid.
  final Float32List _fogData = Float32List(4);
  final Float32List _cameraData = Float32List(4);
  final Float32List _baseColorData = Float32List(4);
  final Float32List _emissiveData = Float32List(4);
  final Float32List _materialData = Float32List(4);
  final Float32List _material2Data = Float32List(4);
  final Float32List _frameParams = Float32List(4);

  PipelineHandle? _debugLinePipeline;

  /// A 0, 1, 2, … index buffer for the debug overlay.
  ///
  /// The overlay's vertices are already in draw order, so indices carry no
  /// information — but `draw()` submits nothing without an index buffer bound,
  /// and there is no non-indexed entry point in the API. Keeping the identity
  /// sequence in a device buffer that only grows means the cost is one upload
  /// when the overlay gets bigger, not one per frame.
  GeometryBuffer? _debugIndexBuffer;
  int _debugIndexCapacity = 0;

  /// Pipelines keyed by both stages; creating one compiles and links state on
  /// the backend, far too expensive to repeat per frame.
  ///
  /// Keyed on the pair rather than the fragment shader alone, because skinning
  /// added a second vertex stage: with only the fragment name as the key, a
  /// skinned draw would be handed the static pipeline the first PBR draw built,
  /// and the vertex layouts do not match.
  final Map<String, PipelineHandle> _pipelineCache =
      <String, PipelineHandle>{};

  final Map<String, ShaderHandle> _fragmentShaders = <String, ShaderHandle>{};

  /// Textures reused across frames and across bloom levels.
  ///
  /// The device is the allocator: one rule for every texture in the engine,
  /// and no second way to make one.
  final RenderTargetPool targetPool;

  int _targetWidth = 0;
  int _targetHeight = 0;

  /// The scene, in linear light with no upper bound. Everything post-processing
  /// does depends on values above display white surviving this far, which is
  /// exactly what the old 8-bit target threw away.
  TextureHandle? _hdrColor;
  TextureHandle? _hdrMsaa;
  TextureHandle? _ldrColor;
  PipelineHandle? _reflectionPipeline;
  final Float32List _reflectionParams = Float32List(4);
  final Float32List _reflectionScreen = Float32List(4);
  final Float32List _reflectionCameraData = Float32List(4);
  final vm.Vector3 _reflectionCamera = vm.Vector3.zero();
  TextureHandle? _reflectionColor;
  TextureHandle? _surfaceColor;
  TextureHandle? _surfaceMsaa;
  TextureHandle? _depthStencil;

  /// A one-sample depth, for the frames that switch multisampling off because
  /// they want the surface buffer. Attachments in one target must agree on
  /// sample count, so a four-sample depth cannot sit beside a resolved colour.
  TextureHandle? _depthStencilSingle;

  /// The HDR format, chosen once. Half floats rather than full: the extra range
  /// of `r32g32b32a32Float` buys nothing for light values and doubles the
  /// bandwidth of every post-processing read.
  static const TextureFormat hdrFormat = TextureFormat.r16g16b16a16Float;

  PipelineHandle? _shadowPipeline;
  PipelineHandle? _skinnedShadowPipeline;
  PipelineHandle? _bloomThresholdPipeline;
  PipelineHandle? _bloomDownsamplePipeline;
  PipelineHandle? _bloomUpsamplePipeline;
  PipelineHandle? _compositePipeline;

  /// Positions and UVs of the one triangle every full-screen pass draws.
  GeometryBuffer? _fullscreenVertices;

  /// World space to the shadow camera's clip space, rebuilt each frame the
  /// light or the scene moves.
  final vm.Matrix4 _shadowMatrix = vm.Matrix4.identity();
  final Float32List _shadowParams = Float32List(4);
  TextureHandle? _shadowMap;
  int _shadowResolution = 0;
  int _shadowCasters = 0;



  /// Depth for the view-model pass, made on demand.
  ///
  /// Lazily rather than alongside the scene's targets, because most frames of
  /// most applications never draw one and a full-size depth buffer is megabytes
  /// nobody asked for.
  final Float32List _bloomParams = Float32List(4);
  final Float32List _compositeParams = Float32List(4);

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
  factory Renderer.create({
    required GraphicsDevice device,
    required TextureHandle fallbackAlbedo,
    required TextureHandle fallbackNormal,
  }) {
    final library = device.shaders;
    ShaderHandle require(String name) {
      final shader = library[name];
      if (shader == null) {
        throw StateError(
          'The bundle has no "$name" entry. Check the backend\'s bundle '
          'manifest and rebuild it — for flutter3d_gpu that is '
          'shaders/flutter3d.shaderbundle.json and tool/build_shaders.sh.',
        );
      }
      return shader;
    }

    return Renderer._(
      device: device,
      vertexShader: require('MeshVertex'),
      skinnedVertexShader: require('MeshSkinnedVertex'),
      debugLineVertexShader: require('DebugLineVertex'),
      particleVertexShader: require('ParticleVertex'),
      particleFragmentShader: require('Particle'),
      debugLineFragmentShader: require('DebugLine'),
      fullscreenVertexShader: require('FullscreenVertex'),
      bloomThresholdShader: require('BloomThreshold'),
      bloomDownsampleShader: require('BloomDownsample'),
      bloomUpsampleShader: require('BloomUpsample'),
      compositeShader: require('Composite'),
      reflectionShader: require('Reflections'),
      fallbackAlbedo: fallbackAlbedo,
      fallbackNormal: fallbackNormal,
      msaaEnabled: device.supportsOffscreenMsaa,
    );
  }

  int get pipelineCount => _pipelineCache.length;

  ShaderHandle _fragmentShaderFor(LightingModel model) {
    return _fragmentShaders.putIfAbsent(model.shaderName, () {
      final shader = shaders[model.shaderName];
      if (shader == null) {
        throw StateError(
          'The bundle has no "${model.shaderName}" fragment shader. '
          'Rebuild it with tool/build_shaders.sh.',
        );
      }
      return shader;
    });
  }

  PipelineHandle _pipelineFor(LightingModel model, {required bool skinned}) {
    return _pipelineCache.putIfAbsent(
      skinned ? 'skinned/${model.shaderName}' : model.shaderName,
      () => device.createPipeline(
        skinned ? skinnedVertexShader : vertexShader,
        _fragmentShaderFor(model),
      ),
    );
  }

  void _ensureTargets(int width, int height) {
    if (width == _targetWidth && height == _targetHeight) return;

    final sampleCount = msaaEnabled ? 4 : 1;

    // Straight from the device rather than through the pool: these live for as
    // long as the window keeps its size, and the pool is for what is acquired
    // and released within a frame.
    TextureHandle make(
      StorageMode storageMode,
      TextureFormat format, {
      int sampleCount = 1,
    }) =>
        device.createTexture(RenderTargetSpec(
          width: width,
          height: height,
          format: format,
          sampleCount: sampleCount,
          storageMode: storageMode,
        ));

    // The scene target is sampled by the composite pass, so it has to be
    // devicePrivate rather than transient — tile memory cannot be read back.
    _hdrColor = make(StorageMode.devicePrivate, hdrFormat);

    // deviceTransient is tile memory: more bandwidth, less memory. Right for
    // intermediates like the MSAA and depth attachments, never read back.
    _hdrMsaa = msaaEnabled
        ? make(StorageMode.deviceTransient, hdrFormat, sampleCount: 4)
        : null;

    // The final image is 8-bit and display-referred; it is what becomes the
    // ui.Image, so there is nothing to gain from more precision here.
    _ldrColor = make(StorageMode.devicePrivate, device.defaultColorFormat);

    // The surface buffer: world-space normal and depth, for whatever runs after
    // the scene. Allocated with the rest rather than on demand, because a
    // resize is the only moment any of this is allowed to be reallocated and a
    // buffer that appears mid-session would be the one that is the wrong size.
    _surfaceColor = make(StorageMode.devicePrivate, hdrFormat);
    _reflectionColor = make(StorageMode.devicePrivate, hdrFormat);

    _surfaceMsaa = msaaEnabled
        ? make(StorageMode.deviceTransient, hdrFormat, sampleCount: 4)
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
  }

  /// Index of the first directional light in the packed buffer, or -1.
  ///
  /// Only a directional light casts today: it is the one whose shadow volume is
  /// a box rather than a frustum or a cube, so it needs neither cascades nor six
  /// faces to be useful.
  int _firstDirectionalIndex() {
    for (var i = 0; i < lights.count; i++) {
      if (lights.positions[i * 4 + 3] == ShaderLightType.directional) return i;
    }
    return -1;
  }

  /// Renders the scene from the light's point of view into a depth map.
  ///
  /// A shadow pass is a render view whose camera happens to be a light — which
  /// is exactly what `RenderView` was shaped for — so the only new machinery is
  /// fitting an orthographic volume to the scene and a fragment shader that
  /// writes depth and nothing else.
  ///
  /// Returns false when there is nothing to shadow, leaving [_shadowParams] at
  /// zero strength so the lighting shaders skip the lookup entirely.
  /// The six directions a cube shadow looks in, and the up vector for each.
  ///
  /// Order fixes the atlas layout, so the shader's face selection and this
  /// list are one decision written twice — which is why they are both spelled
  /// out rather than derived: +X, -X, +Y, -Y, +Z, -Z, left to right then top
  /// to bottom in a three-by-two grid.
  static final List<(vm.Vector3, vm.Vector3)> _cubeFaces =
      <(vm.Vector3, vm.Vector3)>[
    (vm.Vector3(1.0, 0.0, 0.0), vm.Vector3(0.0, 1.0, 0.0)),
    (vm.Vector3(-1.0, 0.0, 0.0), vm.Vector3(0.0, 1.0, 0.0)),
    (vm.Vector3(0.0, 1.0, 0.0), vm.Vector3(0.0, 0.0, 1.0)),
    (vm.Vector3(0.0, -1.0, 0.0), vm.Vector3(0.0, 0.0, -1.0)),
    (vm.Vector3(0.0, 0.0, 1.0), vm.Vector3(0.0, 1.0, 0.0)),
    (vm.Vector3(0.0, 0.0, -1.0), vm.Vector3(0.0, 1.0, 0.0)),
  ];

  /// Renders one point light's six faces into the cube atlas.
  ///
  /// One pass, six viewports. That is the whole reason this is affordable and
  /// it is not an assumption: setViewport is pass state on this backend, which
  /// a spike established by drawing two casters into two halves of one map.
  /// Six passes would have been six command buffers and six submissions.
  ///
  /// The faces store radial distance from the light, normalised by its range,
  /// rather than clip depth — see shadow_distance.frag for why a cube cannot
  /// use depth without showing a seam at every face boundary.
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
    final tile = settings.resolution.clamp(128, 1024);
    if (_cubeShadow != null && _cubeShadowTile == tile) return;
    // A six-by-four grid of square tiles: the face across, the light down.
    // Square because a ninety-degree frustum is square, and any other aspect
    // would stretch one axis of every face.
    final width = tile * 6;
    final height = tile * kShadowedLights;
    final spec = RenderTargetSpec(
      width: width,
      height: height,
      format: hdrFormat,
    );
    _cubeShadowStatic = device.createTexture(spec);
    _cubeShadow = device.createTexture(spec);
    _cubeShadowTile = tile;
    _staticShadowBaked = false;
    _cubeShadowCleared = false;
    _cubeShadowStaticCleared = false;
    _shadowSlotAllocator.reset();
    _shadowFaceScheduler.reset();
  }

  /// Draws [slotCount] lights' cube faces into one atlas, in one pass.
  ///
  /// Every row at once, and not one call per light, because a pass clears its
  /// whole colour attachment: viewport and scissor bound where the rasteriser
  /// may write, but the load action does not honour either. A call per light
  /// therefore wiped the rows already drawn and left only the last one — four
  /// lights rendered and one cast a shadow. The lights are read from
  /// [_cubeLightData], which the frame fills before any of the atlas is drawn.
  ///
  /// The colour attachment is a renderer field and stays one — see
  /// [_CubeShadowStaticNode] for why neither atlas can be pooled. The depth
  /// attachment is the opposite case: nothing names it, nothing reads it, and
  /// it goes through [FrameResources.transient] so the release is deferred by
  /// the frame ring. It used to go straight back to the pool after `submit`,
  /// which handed the very same texture to the *other* atlas pass while the
  /// first one's command buffer was still in flight — the two passes have
  /// identical depth specs, so the pool could not have handed back anything
  /// else.
  bool _renderCubeShadow({
    required FrameResources resources,
    required Scene scene,
    required ShadowSettings settings,
    required bool static,
    required int slotCount,
    Set<int>? tiles,
  }) {
    if (!settings.enabled || settings.strength <= 0.0) return false;
    if (slotCount <= 0) return false;

    final shader = shaders['ShadowDistance'];
    if (shader == null) return false;
    final resetShader = shaders['ShadowTileReset'];
    final resetVertexShader = shaders['ShadowTileResetVertex'];
    if (resetShader == null || resetVertexShader == null) return false;

    // Whether this atlas already holds defined pixels. False exactly once per
    // texture, right after it is allocated.
    final cleared = static ? _cubeShadowStaticCleared : _cubeShadowCleared;

    final tile = _cubeShadowTile;
    final width = tile * 6;
    final height = tile * kShadowedLights;

    final depth = resources.transient(
      RenderTargetSpec(
        width: width,
        height: height,
        format: device.defaultDepthStencilFormat,
        storageMode: StorageMode.deviceTransient,
      ),
    );

    developer.Timeline.startSync('Renderer.cubeShadow');
    final pass = device.beginRenderPass(RenderPassDescriptor(
      colors: <ColorTarget>[
        ColorTarget(
          texture: static ? _cubeShadowStatic! : _cubeShadow!,
          // Loaded, not cleared, and each tile reset by drawing over it.
          //
          // A clear covers the whole attachment however the viewport is set,
          // so a pass that clears can only ever refresh every tile — which is
          // exactly the constraint that has to go before a face can be
          // refreshed on its own schedule. A draw is bounded by the viewport;
          // a clear is not. See shadow_tile_reset.frag.
          //
          // Except once, into a freshly allocated texture, where a clear is
          // still the right tool: `devicePrivate` contents start undefined, and
          // rows nobody owns are never written by anything afterwards. Shading
          // would not care — the slot table never points at an unowned row —
          // but `showShadowMap` composites the raw atlas, so leaving them
          // undefined puts uninitialised memory in the one view used to check
          // this subsystem. That is how it was caught: `cube-shadow` has one
          // occupied row of four and 75% of its pixels changed.
          loadAction: cleared ? LoadAction.load : LoadAction.clear,
          clearValue: vm.Vector4(1.0, 1.0, 1.0, 1.0),
        ),
      ],
      depth: DepthTarget(texture: depth),
    ));

    pass.setPrimitiveType(PrimitiveType.triangle);
    pass.setDepthWrite(true);
    pass.setDepthCompare(CompareFunction.less);
    pass.setBlend(null);
    final casterCull = switch (settings.casterFaces) {
      // Culling the front faces is what leaves the back ones drawn, and the
      // other way about. The enum is named after what ends up *recorded*
      // rather than after what is culled, which is the way round that reads
      // correctly at a call site.
      ShadowCasterFaces.front => CullMode.backFace,
      ShadowCasterFaces.back => CullMode.frontFace,
      ShadowCasterFaces.both => CullMode.none,
    };
    pass.setCullMode(casterCull);

    final mvp = vm.Matrix4.identity();
    final position = vm.Vector3.zero();
    var drawn = 0;

    for (var slot = 0; slot < slotCount; slot++) {
      position.setValues(
        _cubeLightData[slot * 4],
        _cubeLightData[slot * 4 + 1],
        _cubeLightData[slot * 4 + 2],
      );
      final range = _cubeLightData[slot * 4 + 3];
      if (range <= 0.0) continue;

      _cubeLight[0] = position.x;
      _cubeLight[1] = position.y;
      _cubeLight[2] = position.z;
      _cubeLight[3] = range;

      final projection = PerspectiveProjection(
        fovYRadians: math.pi / 2,
        near: 0.05,
        far: range,
      ).toMatrix(1.0);

      for (var face = 0; face < _cubeFaces.length; face++) {
        // The matrix is recorded for every face, drawn or not: the shading
        // projects through it whatever this frame chose to redraw, and a face
        // left out of the schedule still holds a picture that has to be read
        // with the matrix that made it.
        final (faceAim, faceUp) = _cubeFaces[face];
        final faceView = _lookAt(position, position + faceAim, faceUp);
        _cubeMatrix
          ..setFrom(projection)
          ..multiply(faceView);
        final at = (slot * 6 + face) * 16;
        _cubeFaceMatrices.setRange(at, at + 16, _cubeMatrix.storage);

        if (tiles != null && !tiles.contains(slot * 6 + face)) continue;

        // A row of six per light: the face across, the light down.
        final tileRect = ScreenRect(
          x: face * tile,
          y: slot * tile,
          width: tile,
          height: tile,
        );
        pass.setViewport(tileRect);
        pass.setScissor(tileRect);

        // Blank this tile before drawing into it, since the pass no longer
        // clears. Depth is still cleared attachment-wide by the pass, so this
        // only has to write colour — and must not touch depth, or it would
        // occlude the casters that follow it.
        pass.setDepthWrite(false);
        pass.setDepthCompare(CompareFunction.always);
        pass.setCullMode(CullMode.none);
        pass.bindPipeline(_cubeShadowResetPipeline ??=
            device.createPipeline(resetVertexShader, resetShader));
        pass.bindVertexBuffer(_fullscreenTriangle, 3);
        pass.bindIndexBuffer(_identityIndices(3), IndexType.int32, 3);
        pass.draw();

        pass.setDepthWrite(true);
        pass.setDepthCompare(CompareFunction.less);
        pass.setCullMode(casterCull);

        for (final node in scene.meshes) {
          if (!node.visibleInHierarchy || !node.castsShadow) continue;
          // One atlas holds the things that never move, the other the things
          // that do. Splitting them is the whole point: the walls are baked
          // once and only a spinning pickup, a monster or a door is redrawn.
          if (node.shadowIsStatic != static) continue;
          final mesh = node.mesh;
          if (mesh is! DrawableGeometry || mesh.indexCount == 0) continue;
          // Static geometry only for now: a skinned caster needs the skinned
          // vertex stage, and a monster's shadow is worth less than getting the
          // walls right first.
          if (node.skeleton != null) continue;

          pass.bindPipeline(
            _cubeShadowPipeline ??= device.createPipeline(vertexShader, shader),
          );
          pass.setWindingOrder(
            node.worldIsMirrored
                ? WindingOrder.clockwise
                : WindingOrder.counterClockwise,
          );
          pass.bindVertexBuffer(mesh.vertices, mesh.vertexCount);
          pass.bindIndexBuffer(
            mesh.indices,
            mesh.indexType,
            mesh.indexCount,
          );

          mvp
            ..setFrom(_cubeMatrix)
            ..multiply(node.worldMatrix);
          pass.bindUniformBlock(vertexShader, _kFrameInfoBlock, {
            'mvp': mvp.storage,
            'model': node.worldMatrix.storage,
            'normal_matrix': node.worldNormalMatrix.storage,
          });
          pass.bindUniformBlock(shader, 'ShadowLight', {
            'light': _cubeLight,
          });
          pass.draw();
          drawn++;
        }
      }
    }

    pass.submit();
    if (static) {
      _cubeShadowStaticCleared = true;
    } else {
      _cubeShadowCleared = true;
    }
    developer.Timeline.finishSync();
    return drawn > 0;
  }

  /// How many point lights may have a cube map at once.
  ///
  /// Four, because the atlas is one texture and a row of six tiles per light
  /// at a usable size is already a large one.
  ///
  /// A limit on how many lights are shadowed *at the same moment*, not on how
  /// many a level may hold: [ShadowSlotAllocator] hands the rows to whichever
  /// four matter most from where the camera is, and takes them back when they
  /// stop mattering. It used to be the first four in scene order, which meant a
  /// level with five torches had one that could never cast a shadow anywhere.
  static const int kShadowedLights = 4;

  final Float32List _cubeFaceMatrices = Float32List(16 * 6 * kShadowedLights);
  final Float32List _cubeLightData = Float32List(4 * kShadowedLights);

  /// One vec4 per light the shading knows about; x is its atlas row or -1.
  final Float32List _shadowSlots = Float32List(4 * LightBuffer.maxLights);

  final Float32List _pointShadowParams = Float32List(4);
  final Float32List _pointShadowParams2 = Float32List(4);

  /// Number of atlas rows in use, or -1 when none are.
  int _cubeShadowLight = -1;

  final vm.Vector3 _cubePosition = vm.Vector3.zero();

  final ShadowSlotAllocator _shadowSlotAllocator =
      ShadowSlotAllocator(slotCount: kShadowedLights);
  final ShadowFaceScheduler _shadowFaceScheduler =
      ShadowFaceScheduler(tileCount: kShadowedLights * 6);
  final List<ShadowCandidate> _shadowCandidates = <ShadowCandidate>[];
  final vm.Vector3 _shadowEye = vm.Vector3.zero();

  /// Builds this frame's list of lights asking for an atlas row.
  ///
  /// Relevance is measured from the view drawn first — the main camera. A row
  /// chosen for a rear-view mirror would be a row spent on a shadow nobody is
  /// looking at.
  void _collectShadowCandidates(Scene scene, List<RenderView> views) {
    _shadowCandidates.clear();
    if (views.isEmpty) return;

    var primary = views.first;
    for (final view in views) {
      if (view.priority < primary.priority) primary = view;
    }
    primary.camera.readWorldPosition(_shadowEye);

    for (final light in scene.lights) {
      if (light.type != LightType.point || !light.castsShadow) continue;
      if (!light.visibleInHierarchy || light.intensity <= 0.0) continue;

      light.readWorldPosition(_cubePosition);
      final range = light.range > 0.0 ? light.range : 20.0;
      final distance = _cubePosition.distanceTo(_shadowEye);

      // Angular size: how large the lit sphere looks from the camera. The same
      // rule PlayCanvas sorts by, and the reason a torch at the far end of a
      // corridor yields to one in this room. Clamped away from zero so a light
      // the camera is standing inside scores high rather than dividing by it.
      final priority = range / math.max(distance, 0.05);

      _shadowCandidates.add(ShadowCandidate(
        light: light,
        priority: priority,
        bakeKey: _bakeKeyFor(_cubePosition, range),
      ));
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
  List<int?> _computeFaceSignatures(Scene scene, int slotCount) {
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
      // The light's own placement is part of every one of its faces: move the
      // light and every face of that row draws something different.
      final base = _bakeKeyFor(_cubePosition, range);
      for (var face = 0; face < faces; face++) {
        _faceSignatures[slot * faces + face] = base;
      }

      for (final node in scene.meshes) {
        if (!node.visibleInHierarchy || !node.castsShadow) continue;
        if (node.shadowIsStatic) continue;
        final mesh = node.mesh;
        if (mesh is! DrawableGeometry || mesh.indexCount == 0) continue;
        if (node.skeleton != null) continue;

        final radius = node.worldBoundsRadius;
        _shadowToCaster
          ..setFrom(node.worldBoundsCentre)
          ..sub(_cubePosition);
        final distance = _shadowToCaster.length;
        if (distance - radius > range) continue;

        final hash = _casterKeyFor(node);
        if (distance <= radius || distance < 1e-6) {
          // The light is inside the caster's sphere, so it may show on any
          // face. No direction to test against.
          for (var face = 0; face < faces; face++) {
            final at = slot * faces + face;
            _faceSignatures[at] = _mix(_faceSignatures[at]!, hash);
          }
          continue;
        }

        _shadowToCaster.scale(1.0 / distance);
        final limit =
            faceHalfAngle + math.asin((radius / distance).clamp(0.0, 1.0));
        final cosLimit = limit >= math.pi ? -1.0 : math.cos(limit);
        for (var face = 0; face < faces; face++) {
          final (aim, _) = _cubeFaces[face];
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
  static int _casterKeyFor(MeshNode node) {
    var hash = identityHashCode(node);
    final m = node.worldMatrix.storage;
    for (var i = 0; i < 16; i++) {
      hash = _mix(hash, (m[i] * 1000.0).round());
    }
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
    required _SceneNode scene,
    required _BloomNode bloom,
    required _CompositeNode composite,
  }) {
    final graph = FrameGraph()
      // The atlas before the directional map, which is the order they were
      // submitted in before either was a node. Nothing derives it — they write
      // different textures and neither reads the other — so registration order
      // decides, and keeping the old one is what makes this step a pure
      // restructuring with nothing left to explain if a golden moves.
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
      ..addNode(scene);

    for (final node in nodes.all) {
      graph.addNode(node);
    }
    if (s.reflections.enabled) {
      graph.addNode(_ReflectionsNode(this, view));
    }
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
    graph
      ..addNode(bloom)
      ..addNode(composite);

    return graph.compile(outputs: <ResourceId>[
      FrameResourceIds.frame,
      // An application that asked for the surface buffer is a consumer no node
      // declares, so it is a frame output. Without this, `surfaceBuffer` on its
      // own would leave the buffer unread, the scene would not attach it, and
      // the application would read whatever the texture held last.
      if (s.surfaceBuffer) FrameResourceIds.surfaceBuffer,
    ]);
  }

  /// A signature of what a static bake of this light would capture.
  ///
  /// Quantised to a centimetre, because a light that drifts by a hair has not
  /// invalidated its view of the walls and re-baking on floating-point noise
  /// would mean re-baking every frame — which is the whole cost the split
  /// exists to avoid.
  static int _bakeKeyFor(vm.Vector3 position, double range) {
    var hash = 17;
    for (final value in <double>[position.x, position.y, position.z, range]) {
      hash = hash * 31 + (value * 100.0).round();
    }
    return hash;
  }

  PipelineHandle? _cubeShadowPipeline;
  PipelineHandle? _cubeShadowResetPipeline;

  /// Whether each atlas has been cleared since it was allocated.
  bool _cubeShadowCleared = false;
  bool _cubeShadowStaticCleared = false;
  TextureHandle? _cubeShadow;
  TextureHandle? _cubeShadowStatic;
  bool _staticShadowBaked = false;
  int _cubeShadowTile = 0;
  final vm.Matrix4 _cubeMatrix = vm.Matrix4.identity();
  final Float32List _cubeLight = Float32List(4);

  /// Draws the directional light's shadow map, and says whether it drew one.
  ///
  /// The frame's own resources are handed in for the depth attachment, which is
  /// scratch: no other pass names it, it must not go back to the pool while the
  /// command buffer that wrote it is in flight, and [FrameResources.transient]
  /// is where that deferral is now automatic rather than remembered at each
  /// call site. The colour target is the opposite case and stays a renderer
  /// field — see [_ShadowMapNode].
  ///
  /// [_shadowParams] and [_shadowCasters] are zeroed by the frame rather than
  /// here, because a pass the graph culled never runs and would otherwise leave
  /// last frame's numbers standing.
  bool _renderShadowMap({
    required FrameResources resources,
    required Scene scene,
    required ShadowSettings settings,
    required int casterIndex,
  }) {
    if (!settings.enabled || settings.strength <= 0.0) return false;
    if (casterIndex < 0) return false;

    final bounds = scene.computeBounds();
    if (!bounds.min.x.isFinite) return false;

    final centre = (bounds.min + bounds.max)..scale(0.5);
    final radius = ((bounds.max - bounds.min)..scale(0.5)).length;
    if (radius <= 0.0) return false;

    // The light's aim, taken from the packed buffer so the pass sees the same
    // direction the shading does.
    final aim = vm.Vector3(
      lights.directions[casterIndex * 4],
      lights.directions[casterIndex * 4 + 1],
      lights.directions[casterIndex * 4 + 2],
    );
    if (aim.length2 < 1e-12) return false;
    aim.normalize();

    // Back the camera off along the light's axis by the scene radius, then give
    // the volume the same depth again on the far side. An ortho volume fitted
    // exactly to the bounds would clip the casters at its own near plane.
    final padding = math.max(settings.depthPadding, 1.0);
    final distance = radius * padding;
    final eye = centre - aim.scaled(distance);

    // Any up vector that is not parallel to the aim will do; the choice only
    // rotates the map, and a rotated map shadows identically.
    final up = aim.y.abs() > 0.99
        ? vm.Vector3(0.0, 0.0, 1.0)
        : vm.Vector3(0.0, 1.0, 0.0);
    final view = _lookAt(eye, centre, up);

    final projection = OrthographicProjection(
      height: radius * 2.0 * padding,
      near: 0.01,
      far: distance + radius * padding,
    ).toMatrix(1.0);

    _shadowMatrix
      ..setFrom(projection)
      ..multiply(view);

    final resolution = settings.resolution.clamp(256, 4096);
    if (_shadowMap == null || _shadowResolution != resolution) {
      // Sampled by the lighting pass, so devicePrivate rather than transient.
      _shadowMap = device.createTexture(RenderTargetSpec(
        width: resolution,
        height: resolution,
        format: hdrFormat,
      ));
      _shadowResolution = resolution;
    }

    final depth = resources.transient(
      RenderTargetSpec(
        width: resolution,
        height: resolution,
        format: device.defaultDepthStencilFormat,
        storageMode: StorageMode.deviceTransient,
      ),
    );

    developer.Timeline.startSync('Renderer.shadowPass');
    final pass = device.beginRenderPass(RenderPassDescriptor(
      colors: <ColorTarget>[
        ColorTarget(
          texture: _shadowMap!,
          // Cleared to the far plane, so anything the pass does not draw reads
          // as "nothing between here and the light".
          clearValue: vm.Vector4(1.0, 1.0, 1.0, 1.0),
        ),
      ],
      depth: DepthTarget(texture: depth),
    ));

    final full = ScreenRect(width: resolution, height: resolution);
    pass.setViewport(full);
    pass.setScissor(full);
    pass.setPrimitiveType(PrimitiveType.triangle);
    pass.setDepthWrite(true);
    pass.setDepthCompare(CompareFunction.less);
    pass.setBlend(null);
    // Front faces culled, so the depth stored is the back of each caster. That
    // moves the comparison surface away from the lit face and removes most of
    // the acne before bias and normal offset have to deal with any.
    pass.setCullMode(CullMode.frontFace);

    final shadowShader = shaders['ShadowDepth'];
    if (shadowShader == null) {
      developer.Timeline.finishSync();
      return false;
    }
    // Two pipelines, for the same reason the main pass has two: a skinned mesh
    // has a different vertex layout, so it needs the skinned stage here too.
    // Drawing it with the static one would read joints and weights as position
    // and normal — and skipping skinned casters instead would mean a character
    // that walks around without a shadow.
    bool? boundSkinned;

    _shadowCasters = 0;
    final meshes = scene.meshes;
    final mvp = vm.Matrix4.identity();

    for (var i = 0; i < meshes.length; i++) {
      final node = meshes[i];
      if (!node.visibleInHierarchy) continue;
      if (!node.castsShadow) continue;
      final mesh = node.mesh;
      if (mesh is! DrawableGeometry || mesh.indexCount == 0) continue;

      final skeleton = node.skeleton;
      final skinned = skeleton != null;
      if (boundSkinned != skinned) {
        pass.bindPipeline(
          skinned
              ? (_skinnedShadowPipeline ??= device.createPipeline(
                  skinnedVertexShader,
                  shadowShader,
                ))
              : (_shadowPipeline ??= device.createPipeline(
                  vertexShader,
                  shadowShader,
                )),
        );
        boundSkinned = skinned;
      }

      pass.setWindingOrder(
        node.worldIsMirrored
            ? WindingOrder.clockwise
            : WindingOrder.counterClockwise,
      );
      pass.bindVertexBuffer(mesh.vertices, mesh.vertexCount);
      pass.bindIndexBuffer(
        mesh.indices,
        mesh.indexType,
        mesh.indexCount,
      );

      mvp
        ..setFrom(_shadowMatrix)
        ..multiply(node.worldMatrix);
      final stage = skinned ? skinnedVertexShader : vertexShader;
      pass.bindUniformBlock(stage, _kFrameInfoBlock, {
        'mvp': mvp.storage,
        'model': node.worldMatrix.storage,
        'normal_matrix': node.worldNormalMatrix.storage,
      });
      if (skeleton != null) {
        skeleton.update(node.worldMatrix);
        pass.bindUniformBlock(skinnedVertexShader, _kSkinInfoBlock, {
          'joint_matrices': skeleton.matrices,
        });
      }
      pass.draw();
      _shadowCasters++;
    }

    pass.submit();
    developer.Timeline.finishSync();

    _shadowParams[0] = 1.0 / resolution;
    _shadowParams[1] = settings.bias;
    _shadowParams[2] = settings.normalOffset;
    _shadowParams[3] = settings.strength.clamp(0.0, 1.0);
    return true;
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

  /// The one triangle every full-screen pass draws, uploaded once.
  ///
  /// A triangle rather than a quad: a quad has a diagonal seam where the GPU
  /// rasterizes the 2x2 fragment quads along it twice. The UVs are authored so
  /// that NDC +1 in Y maps to texture row zero, matching where Metal puts the
  /// origin of a render target.
  GeometryBuffer get _fullscreenTriangle => _fullscreenVertices ??=
      device.uploadGeometry(
        Float32List.fromList(<double>[
          -1.0, -1.0, 0.0, 1.0, //
          3.0, -1.0, 2.0, 1.0, //
          -1.0, 3.0, 0.0, -1.0, //
        ]).buffer.asByteData(),
        GeometryUsage.vertices,
      );

  PipelineHandle _postPipeline(
    PipelineHandle? cached,
    ShaderHandle fragment,
    void Function(PipelineHandle) store,
  ) {
    if (cached != null) return cached;
    final pipeline = device.createPipeline(fullscreenVertexShader, fragment);
    store(pipeline);
    return pipeline;
  }

  /// Runs one full-screen pass into [target].
  ///
  /// Every post stage is the same shape — bind the triangle, bind a source
  /// texture, write a small uniform block, draw three vertices — so it is
  /// written once and parameterized.
  void _drawFullscreen({
    required TextureHandle target,
    required PipelineHandle pipeline,
    required ShaderHandle fragment,
    required Map<String, TextureHandle> textures,
    required String uniformBlock,
    required Float32List uniformData,
    required String uniformMember,
  }) {
    // One encoder per pass, because Metal allows a single encoder open at a
    // time and flutter_gpu offers no way to end one. Passes submitted to the
    // same queue execute in submission order, which is the ordering these
    // passes need.
    final pass = device.beginRenderPass(RenderPassDescriptor(
      colors: <ColorTarget>[
        ColorTarget(
          texture: target,
          // Nothing under a full-screen pass survives it, so discarding what
          // was there is both correct and cheaper than loading it.
          loadAction: LoadAction.dontCare,
        ),
      ],
    ));

    final full = ScreenRect.of(target);
    pass.setViewport(full);
    pass.setScissor(full);
    pass.setPrimitiveType(PrimitiveType.triangle);
    pass.setCullMode(CullMode.none);
    pass.setBlend(null);
    pass.setDepthWrite(false);
    pass.setDepthCompare(CompareFunction.always);

    pass.bindPipeline(pipeline);
    pass.bindVertexBuffer(_fullscreenTriangle, 3);
    pass.bindIndexBuffer(_identityIndices(3), IndexType.int32, 3);

    textures.forEach((slot, texture) {
      pass.bindTexture(fragment, slot, texture, sampler: _clampSampler);
    });

    pass.bindUniformBlock(fragment, uniformBlock, {
      uniformMember: uniformData,
    });

    pass.draw();
    pass.submit();
  }

  /// Clamped and linear: a post pass reading outside the source would otherwise
  /// wrap the opposite edge of the screen into the glow.
  static const SamplerOptions _clampSampler = SamplerOptions.linearClamp;

  /// Builds the bloom chain into [top], the texture the graph allocated for
  /// `FrameResourceIds.bloom`.
  ///
  /// Everything below the top is scratch that no other pass will ever name, so
  /// it comes from [FrameResources.transient] rather than from the pool
  /// directly. That is not tidiness: the upsample command buffers that read
  /// those levels are still in flight when this method returns, and handing
  /// them straight back let the pool lend one out while the GPU was reading it.
  void _renderBloom({
    required FrameResources resources,
    required TextureHandle scene,
    required TextureHandle top,
    required BloomSettings settings,
  }) {
    final levels = settings.levels.clamp(1, 8);
    final chain = <TextureHandle>[];

    var sourceWidth = scene.width;
    var sourceHeight = scene.height;
    TextureHandle source = scene;

    developer.Timeline.startSync('Bloom.downsample');
    for (var level = 0; level < levels; level++) {
      final spec = RenderTargetSpec(
        width: math.max(1, sourceWidth ~/ 2),
        height: math.max(1, sourceHeight ~/ 2),
        format: hdrFormat,
      );
      // Once a level is a single pixel there is nothing left to halve, and
      // continuing would just re-blur one texel.
      if (level > 0 && spec.width == sourceWidth && spec.height == sourceHeight) {
        break;
      }

      final target = level == 0 ? top : resources.transient(spec);
      _bloomParams[0] = 1.0 / sourceWidth;
      _bloomParams[1] = 1.0 / sourceHeight;
      _bloomParams[2] = level == 0 ? settings.threshold : 0.0;
      _bloomParams[3] = level == 0 ? settings.knee : 0.0;

      final isFirst = level == 0;
      _drawFullscreen(
        target: target,
        pipeline: isFirst
            ? _postPipeline(_bloomThresholdPipeline, bloomThresholdShader,
                (p) => _bloomThresholdPipeline = p)
            : _postPipeline(_bloomDownsamplePipeline, bloomDownsampleShader,
                (p) => _bloomDownsamplePipeline = p),
        fragment: isFirst ? bloomThresholdShader : bloomDownsampleShader,
        textures: <String, TextureHandle>{_kPostSourceSlot: source},
        uniformBlock: _kBloomInfoBlock,
        uniformData: _bloomParams,
        uniformMember: 'params',
      );

      chain.add(target);
      source = target;
      sourceWidth = spec.width;
      sourceHeight = spec.height;
    }
    developer.Timeline.finishSync();

    // Back up the chain, each level's blur added into the one above it. The
    // widest level supplies the broad glow and the narrowest the tight core.
    developer.Timeline.startSync('Bloom.upsample');
    for (var level = chain.length - 1; level > 0; level--) {
      final from = chain[level];
      final into = chain[level - 1];

      _bloomParams[0] = 1.0 / from.width;
      _bloomParams[1] = 1.0 / from.height;
      _bloomParams[2] = settings.filterRadius;
      _bloomParams[3] = 0.0;

      _drawFullscreenAdditive(target: into, source: from);
    }
    developer.Timeline.finishSync();
  }

  /// The upsample step, which differs from every other post pass by blending
  /// rather than replacing.
  void _drawFullscreenAdditive({
    required TextureHandle target,
    required TextureHandle source,
  }) {
    final pass = device.beginRenderPass(RenderPassDescriptor(
      colors: <ColorTarget>[
        ColorTarget(
          texture: target,
          // Load, not clear: the point is to add to what the downsample left.
          loadAction: LoadAction.load,
        ),
      ],
    ));

    final full = ScreenRect.of(target);
    pass.setViewport(full);
    pass.setScissor(full);
    pass.setPrimitiveType(PrimitiveType.triangle);
    pass.setCullMode(CullMode.none);
    pass.setDepthWrite(false);
    pass.setDepthCompare(CompareFunction.always);
    pass.setBlend(BlendState.additive);

    pass.bindPipeline(
      _postPipeline(_bloomUpsamplePipeline, bloomUpsampleShader,
          (p) => _bloomUpsamplePipeline = p),
    );
    pass.bindVertexBuffer(_fullscreenTriangle, 3);
    pass.bindIndexBuffer(_identityIndices(3), IndexType.int32, 3);
    pass.bindTexture(
      bloomUpsampleShader,
      _kPostSourceSlot,
      source,
      sampler: _clampSampler,
    );
    pass.bindUniformBlock(bloomUpsampleShader, _kBloomInfoBlock, {
      'params': _bloomParams,
    });
    pass.draw();
    pass.submit();
  }

  /// Renders every view into one target and returns the composited image.
  ///
  /// Views share a single render pass and clear: viewports do not overlap in the
  /// split-screen case, and one pass is both cheaper and simpler than a pass per
  /// view. Views are drawn in ascending priority, as in PlayCanvas.
  /// Encodes one mesh node into an open pass.
  ///
  /// Extracted so the view-model pass draws through exactly the same code as
  /// the scene. The alternative was a second copy of the material binding, and
  /// that binding is where the phantom-sampler trap lives: a shader that never
  /// reads a texture has no slot for it, and binding one anyway is a native
  /// crash rather than a no-op. Two copies of that would eventually disagree,
  /// and the disagreement would arrive as a segfault with no Dart stack.
  void _encodeNode({
    required PassEncoder encoder,
    required MeshNode node,
    required Scene scene,
    required RenderSettings settings,
    required vm.Matrix4 viewProjection,
    required SceneShadows shadows,
    required FramePassState state,
  }) {
      final mesh = node.mesh;
      // The scene deals in MeshGeometry so that culling and picking need no
      // device; only here does it matter that the geometry actually reached
      // the GPU. A CPU-only mesh in a drawn scene is a bug in the caller,
      // not something to skip quietly.
      if (mesh is! DrawableGeometry) {
        throw StateError(
          'MeshNode "${node.name}" holds ${mesh.runtimeType}, which has no '
          'GPU buffers. Upload it with DeviceMesh.upload before drawing it.',
        );
      }
      final material = node.material;

      final skeleton = node.skeleton;
      final skinned = skeleton != null;
      if (state.boundPipeline != material.lighting || state.boundSkinned != skinned) {
        encoder.bindPipeline(
          _pipelineFor(material.lighting, skinned: skinned),
        );
        state.boundPipeline = material.lighting;
        state.boundSkinned = skinned;
        state.pipelineSwitches++;
      }

      // Both matrices are cached on the node and keyed on its transform
      // version, so a static object costs nothing here.
      final modelMatrix = node.worldMatrix;
      final normalMatrix = node.worldNormalMatrix;

      encoder.setWindingOrder(
        node.worldIsMirrored
            ? WindingOrder.clockwise
            : WindingOrder.counterClockwise,
      );
      final cull = settings.backfaceCulling &&
          !settings.wireframe &&
          !material.doubleSided;
      encoder.setCullMode(cull ? CullMode.backFace : CullMode.none);

      final blend = material.alphaMode == MaterialAlphaMode.blend;
      encoder.setBlend(blend ? BlendState.alphaBlend : null);
      // Transparent surfaces must not occlude what is behind them.
      encoder.setDepthWrite(!blend);

      encoder.bindVertexBuffer(mesh.vertices, mesh.vertexCount);
      encoder.bindIndexBuffer(
        mesh.indices,
        mesh.indexType,
        mesh.indexCount,
      );

      final activeVertexShader =
          skinned ? skinnedVertexShader : vertexShader;
      encoder.bindUniformBlock(activeVertexShader, _kFrameInfoBlock, {
        'mvp': (viewProjection * modelMatrix).storage,
        'model': modelMatrix.storage,
        'normal_matrix': normalMatrix.storage,
      });

      if (skeleton != null) {
        // Recomputed here rather than by the caller: the matrices depend on
        // the mesh node's own world transform, which is exactly what the
        // renderer is holding at this point.
        skeleton.update(modelMatrix);
        encoder.bindUniformBlock(
          skinnedVertexShader,
          _kSkinInfoBlock,
          {'joint_matrices': skeleton.matrices},
        );
        state.skinnedDraws++;
      }

      final fragmentShader = _fragmentShaderFor(material.lighting);

      // Gated on model metadata, not reflection: a shader that only DECLARES
      // FragInfo still reports it with a non-zero size while the compiled
      // function binds no buffer, and binding that segfaults inside Metal.
      if (material.lighting.usesFragInfo) {
        _baseColorData[0] = material.baseColor.x;
        _baseColorData[1] = material.baseColor.y;
        _baseColorData[2] = material.baseColor.z;
        _baseColorData[3] = material.baseColor.w;

        _emissiveData[0] = material.emissive.x;
        _emissiveData[1] = material.emissive.y;
        _emissiveData[2] = material.emissive.z;

        _materialData[0] = material.metallic;
        _materialData[1] = material.roughness;
        _materialData[2] = scene.ambientIntensity;
        _materialData[3] = settings.specular;

        // A negative cutoff means "not masked". The shader compares against
        // it directly, so encoding the mode in the value keeps a branch and
        // a separate flag out of the uniform block.
        _material2Data[0] = material.alphaMode == MaterialAlphaMode.mask
            ? material.alphaCutoff
            : -1.0;
        _material2Data[1] = material.normalScale;
        _material2Data[2] = material.occlusionStrength;
        _material2Data[3] = material.emissiveStrength;

        _frameParams[0] = settings.exposure;
        _frameParams[1] = lights.count.toDouble();
        _frameParams[2] =
            shadows.directional == null ? -1.0 : shadows.casterIndex.toDouble();

      // Its own block, bound beside FragInfo rather than folded into it. See
      // the note in color.glsl: appending to a block six shaders share moves
      // offsets nobody expected to move.
      final fog = settings.fog;
      _fogData[0] = fog.resolvedColor.x;
      _fogData[1] = fog.resolvedColor.y;
      _fogData[2] = fog.resolvedColor.z;
      _fogData[3] = fog.density;
      // Gated on the model, like every other block and sampler here. Unlit
      // declares FragInfo but reaches no lighting loop, so the compiler drops
      // all three of these — and binding a block the compiled shader does not
      // have is a native failure, not a no-op.
      if (material.lighting.usesPointShadow) {
        // Half a texel, in tile-local uv: what every tap is held inside its
        // tile by, so none of them can reach the next face along.
        final texel = _cubeShadowTile > 0 ? 1.0 / _cubeShadowTile : 0.0;
        _pointShadowParams[0] = texel * 0.5;
        _pointShadowParams[1] = settings.shadows.pointBias;
        _pointShadowParams[2] =
            _cubeShadowLight < 0 ? 0.0 : settings.shadows.strength;
        _pointShadowParams[3] = settings.shadows.pointNormalOffset;
        // Softness is authored in texels and spent in tile-local uv, so a
        // penumbra keeps its width when the atlas resolution changes.
        _pointShadowParams2[0] =
            math.max(settings.shadows.pointSoftness, 0.0) * texel;
        _pointShadowParams2[1] =
            math.max(settings.shadows.pointLightRadius, 0.0);
        _pointShadowParams2[2] =
            math.max(settings.shadows.pointMaxSoftness, 0.0) * texel;
        _pointShadowParams2[3] = settings.showPointShadowDebug ? 1.0 : 0.0;
        encoder.bindUniformBlock(fragmentShader, 'PointShadow', {
          'faces': _cubeFaceMatrices,
          'lights': _cubeLightData,
          'slots': _shadowSlots,
          'params': _pointShadowParams,
          'params2': _pointShadowParams2,
        });
        encoder.bindTexture(
          fragmentShader,
          'point_shadow_texture',
          // Whatever the caller was given by the frame, not the renderer's own
          // field. Two nodes reach this code — the scene and the view model,
          // through `encodeScene` — so there is no single node whose
          // `tryTexture` could be asked *here*; each of them declares its own
          // read and answers with [SceneShadows], which is why that type exists.
          //
          // White where there is no atlas, which reads as "nothing between here
          // and the light", the same answer an unoccupied row gives.
          shadows.point ?? fallbackAlbedo,
          sampler: _clampSampler,
        );
        encoder.bindTexture(
          fragmentShader,
          'point_shadow_static_texture',
          shadows.pointStatic ?? fallbackAlbedo,
          sampler: _clampSampler,
        );
      }

      encoder.bindUniformBlock(fragmentShader, _kFogInfoBlock, {
        'fog': _fogData,
        'eye': _cameraData,
      });

        encoder.bindUniformBlock(fragmentShader, _kFragInfoBlock, {
          // Whole arrays written from their reflected base offset. Impeller
          // reflects the array, not its elements — `lights[0]` comes back
          // null — but the std140 stride for a vec4 array is a flat 16
          // bytes, so a contiguous write lands each element correctly.
          'light_position': lights.positions,
          'light_color': lights.colors,
          'light_direction': lights.directions,
          'light_cone': lights.cones,
          'base_color': _baseColorData,
          'emissive': _emissiveData,
          'camera_position': _cameraData,
          'material': _materialData,
          'material2': _material2Data,
          'frame_params': _frameParams,
          'shadow_params': _shadowParams,
          'shadow_matrix': _shadowMatrix.storage,
        });
      }

      // Bound strictly according to the model's declared slots. The
      // compiler drops a sampler the shader never reads, and binding one
      // Metal does not have is a native crash rather than a no-op.
      if (material.lighting.usesAlbedoTexture) {
        encoder.bindTexture(
          fragmentShader,
          _kAlbedoTextureSlot,
          material.albedo ?? fallbackAlbedo,
          sampler: material.albedoSampler,
        );
      }
      if (material.lighting.usesMaterialMaps) {
        encoder.bindTexture(
          fragmentShader,
          _kNormalTextureSlot,
          material.normal ?? fallbackNormal,
          sampler: material.normalSampler,
        );
        encoder.bindTexture(
          fragmentShader,
          _kOcclusionTextureSlot,
          material.occlusion ?? fallbackAlbedo,
          sampler: material.occlusionSampler,
        );
        encoder.bindTexture(
          fragmentShader,
          _kEmissiveTextureSlot,
          material.emissiveTexture ?? fallbackAlbedo,
          sampler: material.emissiveSampler,
        );
      }
      if (material.lighting.usesShadowMap) {
        encoder.bindTexture(
          fragmentShader,
          _kShadowTextureSlot,
          // With shadows off the slot still has to be satisfied, and a white
          // texture reads as "nothing between here and the light" — which is
          // also what the zero strength above already guarantees.
          shadows.directional ?? fallbackAlbedo,
          sampler: _clampSampler,
        );
      }
      if (material.lighting.usesMetallicRoughnessMap) {
        encoder.bindTexture(
          fragmentShader,
          _kMetallicRoughnessTextureSlot,
          material.metallicRoughness ?? fallbackAlbedo,
          sampler: material.metallicRoughnessSampler,
        );
      }

      encoder.draw();
      state.drawCalls++;
  }

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
    required PassEncoder encoder,
    required Scene scene,
    required vm.Matrix4 viewProjection,
    required vm.Vector3 cameraPosition,
    required RenderSettings settings,
    required FramePassState state,
    required SceneShadows shadows,
  }) {
    _cameraData[0] = cameraPosition.x;
    _cameraData[1] = cameraPosition.y;
    _cameraData[2] = cameraPosition.z;

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
        state: state,
      );
    }
  }

  /// Draws the world into the HDR target, and submits it.
  ///
  /// The body of [_SceneNode], extracted before the node existed so that the
  /// move was verifiable on its own: it changed no behaviour, so the goldens had
  /// to match byte for byte, and a refactor that moves the picture moved
  /// something else too.
  ///
  /// It owns the render target, the command buffer and the pass, which is what
  /// a node has to own. Ordering against the shadow passes is by *submission* —
  /// they build and submit their own command buffers before this one, and the
  /// queue runs buffers in the order they were submitted. That is the fact that
  /// makes the graph cheap to adopt here: it has to derive a submission order,
  /// not take over how passes are built.
  ///
  /// [surfaceIsRead] is the graph's answer about the frame that is running, not
  /// a setting: it decides both whether the second attachment is present and
  /// whether the pass may multisample, and those two must agree.
  ///
  /// [shadows] is the same shape of answer: every map this pass samples, taken
  /// from the frame by the node that declared it and handed down rather than
  /// looked up here. The atlases used to be the exception — bound deep in
  /// [_encodeNode] straight out of a renderer field, because the view model
  /// reaches that same code through [RenderServices.encodeScene] and only one
  /// of the two callers declared the read. Two nodes and one binding site is
  /// still true; what changed is that each of them now answers for itself.
  ///
  /// [contributors] are handed in rather than looked up. A node that reaches
  /// into a global registry cannot be a node somebody else supplies, which is
  /// the whole point of the extension model — and the distinction it makes is
  /// the one the migration keeps running into: a contributor draws *into* this
  /// pass, so it takes the pass as an argument, while a node *owns* one and
  /// therefore cannot be handed one. That is why there are two contexts:
  /// `ContributorFrame` carries a pass and `NodeFrame` does not.
  _ScenePass _encodeScene({
    required Scene scene,
    required List<RenderView> ordered,
    required RenderSettings settings,
    required int width,
    required int height,
    required SceneShadows shadows,
    required FramePassState passState,
    required int lightOverflowCount,
    required List<PassContributor> contributors,
    required bool surfaceIsRead,
  }) {
    final hdr = _hdrColor!;
    var culled = 0;
    var debugLines = 0;
    var lightOverflow = 0;
    // No multisampling while the surface buffer is wanted, and that is a
    // correctness matter rather than a budget one. Attachments in one target
    // must agree on sample count, so the surface buffer would be resolved by
    // averaging — and the average of two octahedrally encoded normals is not
    // the encoding of any normal. Every silhouette pixel would decode to a
    // direction belonging to neither face, which a reflection shows as a
    // fringe of wrong angles along every edge.
    //
    // A golden caught this before any reflection did: surface-buffer sat just
    // outside its tolerance, every differing pixel on an edge, and which
    // pixels differed changed between runs.
    final msaa = surfaceIsRead ? null : _hdrMsaa;
    // The clear colour is authored the way a colour picker shows it, but the
    // scene target holds linear light and the composite pass encodes on the way
    // out. Clearing with the sRGB value directly would send it through the
    // encode twice and wash the background out.
    final clear = _srgbToLinear(ordered.first.clearColor);

    final colorAttachment = msaa == null
        ? ColorTarget(texture: hdr, clearValue: clear)
        : ColorTarget(
            texture: msaa,
            resolveTexture: hdr,
            storeAction: StoreAction.multisampleResolve,
            clearValue: clear,
          );

    // Attached only when something wants it. A pipeline may declare more
    // outputs than the target has attachments — the extra is discarded — so
    // the shaders write the surface unconditionally and this decides whether
    // anyone is listening. See RESEARCH.md.
    final surface = surfaceIsRead ? _surfaceColor : null;
    final surfaceAttachment = surface == null
        ? null
        : (msaa == null
            ? ColorTarget(
                texture: surface,
                clearValue: vm.Vector4.zero(),
              )
            : ColorTarget(
                texture: _surfaceMsaa!,
                resolveTexture: surface,
                storeAction: StoreAction.multisampleResolve,
                clearValue: vm.Vector4.zero(),
              ));

    final pass = device.beginRenderPass(RenderPassDescriptor(
      colors: <ColorTarget>[colorAttachment, ?surfaceAttachment],
      // Standard depth: clear to the far plane, nearer fragments win.
      depth: DepthTarget(
        texture: msaa == null
            ? (_depthStencilSingle ?? _depthStencil!)
            : _depthStencil!,
      ),
    ));

    final cameraPosition = vm.Vector3.zero();

    for (final view in ordered) {
      // Per view rather than once: the debug overlay at the end of each view
      // leaves the pass in line-drawing state, so the next view has to
      // re-establish its own.
      //
      // Viewport and scissor are set explicitly because both default to a
      // zero-sized rect, and nothing in the API complains about drawing into one.
      pass.setDepthWrite(true);
      pass.setDepthCompare(CompareFunction.less);
      pass.setPrimitiveType(PrimitiveType.triangle);
      pass.setPolygonMode(
        settings.wireframe ? PolygonMode.line : PolygonMode.fill,
      );

      final fraction = view.viewportFraction;
      final vx = (fraction.x * width).round();
      final vy = (fraction.y * height).round();
      final vw = math.max(1, (fraction.width * width).round());
      final vh = math.max(1, (fraction.height * height).round());

      final viewRect = ScreenRect(x: vx, y: vy, width: vw, height: vh);
      pass.setViewport(viewRect);
      pass.setScissor(viewRect);

      final camera = view.camera;
      final aspect = vw / vh;
      final viewMatrix = camera.viewMatrix;
      final viewProjection = camera.viewProjection(aspect);

      // Before the render list is built, because choosing a level changes which
      // nodes are visible and the list is built from what is.
      //
      // Driven here rather than left to the application, which is the fix for a
      // feature that was written, tested and then never actually ran: nothing
      // called select(), so every LOD group sat on its finest level for ever
      // and the whole thing was decoration.
      developer.Timeline.startSync('LodGroup.select');
      for (final group in scene.lodGroups) {
        group.select(camera);
      }
      developer.Timeline.finishSync();
      final frustum = vm.Frustum.matrix(viewProjection);

      final visibleBefore = scene.meshes.length;
      developer.Timeline.startSync('RenderList.build');
      _renderList.build(
        scene,
        view,
        viewMatrix: viewMatrix,
        frustum: frustum,
      );
      developer.Timeline.finishSync();

      developer.Timeline.startSync('RenderList.sort');
      _renderList.sort(view);
      developer.Timeline.finishSync();
      culled += visibleBefore - _renderList.length;

      camera.readWorldPosition(cameraPosition);

      lightOverflow = lightOverflowCount;

      _cameraData[0] = cameraPosition.x;
      _cameraData[1] = cameraPosition.y;
      _cameraData[2] = cameraPosition.z;

      developer.Timeline.startSync('Renderer.encodeDraws');
      for (final indices in <List<int>>[
        _renderList.opaque,
        _renderList.transparent,
      ]) {
        for (var i = 0; i < indices.length; i++) {
          final node = _renderList.itemAt(indices[i]).requireNode;
          _encodeNode(
            encoder: pass,
            node: node,
            scene: scene,
            settings: settings,
            viewProjection: viewProjection,
            shadows: shadows,
            state: passState,
          );
        }
      }
      developer.Timeline.finishSync();

      for (final plugin in contributors) {
        plugin.encode(
          ContributorFrame(
            encoder: pass,
            device: device,
            services: this,
            state: passState,
            settings: settings,
            width: width,
            height: height,
            view: view,
            viewProjection: viewProjection,
          ),
        );
      }

      // The debug overlay is deliberately NOT drawn here. Anything written into
      // the HDR target is scene light: it would be tone mapped, and a bright
      // enough gizmo would bleed into the bloom. The overlay belongs on top of
      // the finished image, so it is drawn in the composite pass below.
    }

    // Submitted before the post passes: they sample this target, and the queue
    // orders command buffers by submission.
    developer.Timeline.startSync('CommandBuffer.submit');
    final stopwatch = Stopwatch()..start();
    pass.submit();
    stopwatch.stop();
    developer.Timeline.finishSync();

    return _ScenePass(
      culled: culled,
      debugLines: debugLines,
      lightOverflow: lightOverflow,
      submitMicros: stopwatch.elapsedMicroseconds,
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
    // Timeline markers, not print statements: the phases below are only
    // meaningful next to Flutter's own build and raster spans, and only in
    // profile or release, where the debug interpreter is not the bottleneck.
    developer.Timeline.startSync('Renderer.render');
    final frameClock = Stopwatch()..start();
    _ensureTargets(width, height);

    // Rotates whatever the backend keeps per frame — on flutter_gpu, the ring
    // of uniform allocators. Before anything is encoded, and never in the
    // middle of one.
    device.beginFrame();

    // This slot's textures were handed back a full ring ago, so the GPU is done
    // with them; the same reasoning that governs the backend's own ring.
    final expired = _pendingRelease[_frameIndex % _kFramesInFlight];
    for (final texture in expired) {
      targetPool.release(texture);
    }
    expired.clear();
    _frameIndex++;


    // Lights are gathered once up front now, because the shadow pass needs the
    // caster before any view is drawn — and the packed buffer is per frame, not
    // per view.
    lights.gather(scene.lights);
    if (lights.count == 0) lights.useDefaultLight();
    final lightOverflowCount = lights.overflow;
    final shadowCaster = _firstDirectionalIndex();

    // Zeroed by the frame rather than by the pass, because the pass may not
    // run. `_renderShadowMap` cleared these on its way out of every early
    // return; a node the graph culls has no way out to clear them on, and last
    // frame's strength left standing would shadow a scene whose shadows were
    // just switched off.
    _shadowParams[3] = 0.0;
    _shadowCasters = 0;

    // Which point lights get a row of the atlas, decided by relevance rather
    // than by the order they happen to sit in the scene list. Four is now a
    // limit on how many can be shadowed *at once*, not on how many a level may
    // contain: a fifth torch takes a row as soon as it matters more than one of
    // the four, and gives it back when it stops.
    //
    // Every row is decided before any of the atlas is drawn, because one pass
    // draws all of them: a pass per light would clear the rows already there.
    _collectShadowCandidates(scene, views);
    final assignment = _shadowSlotAllocator.assign(_shadowCandidates);

    for (var i = 0; i < _shadowSlots.length; i++) {
      _shadowSlots[i] = -1.0;
    }
    var slot = 0;
    for (var row = 0; row < assignment.owners.length; row++) {
      final owner = assignment.owners[row];
      if (owner is! LightNode) continue;
      final index = lights.packed.indexOf(owner);
      if (index < 0) continue;

      owner.readWorldPosition(_cubePosition);
      _cubeLightData[row * 4] = _cubePosition.x;
      _cubeLightData[row * 4 + 1] = _cubePosition.y;
      _cubeLightData[row * 4 + 2] = _cubePosition.z;
      _cubeLightData[row * 4 + 3] = owner.range > 0.0 ? owner.range : 20.0;
      // Which atlas row this light's shader index should read.
      _shadowSlots[index * 4] = row.toDouble();
      slot = math.max(slot, row + 1);
    }
    // Which rows are occupied, and therefore whether the atlas is worth
    // drawing at all. Decided here rather than inside either atlas node,
    // because it is what the *frame* knows — both nodes are asked whether they
    // are active before either one runs.
    _cubeShadowLight = slot > 0 ? slot : -1;

    final ordered = List<RenderView>.of(views)
      ..sort((a, b) => a.priority.compareTo(b.priority));

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
    );
    final sceneNode = _SceneNode(
      this,
      scene: scene,
      ordered: ordered,
      contributors: contributors.active.toList(growable: false),
      shadowCaster: shadowCaster,
      lightOverflow: lightOverflowCount,
    );
    final bloomNode = _BloomNode(this, settings.bloom);
    final compositeNode = _CompositeNode(this, scene, ordered, settings);
    final frameGraph = _compileFrameGraph(
      views.first,
      settings,
      cubeStatic: cubeStaticNode,
      cube: cubeNode,
      shadow: shadowNode,
      scene: sceneNode,
      bloom: bloomNode,
      composite: compositeNode,
    );

    final passState = FramePassState();

    // The frame's own resources: the graph names the lit scene and each version
    // of it, this holds the texture behind each. Nothing is handed in here any
    // more — the scene provides its colour and its surface buffer, reflections
    // provide the second colour, the composite provides the finished image, and
    // each of them does it from inside the node that produced it. What is left
    // in this method is the one thing the graph allocates for itself.
    final resources = FrameResources(
      source: _DeferredTextureSource(this),
      graph: frameGraph,
      frameWidth: width,
      frameHeight: height,
    )
      // Half the frame, in the same HDR format, which is what the bloom chain's
      // top level has always been.
      ..declare(const ResourceDesc(
        id: FrameResourceIds.bloom,
        format: hdrFormat,
        size: FrameFraction(2),
      ));

    // A pass that throws leaves the frame's textures lent out, and the pool has
    // no other way to learn they are free — one set of targets per attempt, and
    // a frame that fails tends to fail again next frame. [releaseAll] was
    // written for this and had no caller; it has one now, and the throw the
    // resource layer raises when a node breaks its `keeps` promise is the first
    // thing likely to use it.
    try {
      for (var i = 0; i < frameGraph.order.length; i++) {
        resources.beginNode(i);
        (frameGraph.order[i] as RenderNode).execute(
          NodeFrame(
            device: device,
            resources: resources,
            services: this,
            state: passState,
            settings: settings,
            width: width,
            height: height,
            // `tryTexture`, because the scene runs first and there is no scene
            // colour until it has drawn one. A node that draws over the world
            // already has to handle that — the view model returns early — and
            // asking for a texture nobody has produced would allocate one from
            // a description that does not exist.
            sceneColor: resources.tryTexture(FrameResourceIds.hdrColour),
          ),
        );
        resources.endNode(i);
      }
    } catch (_) {
      // Only on the way out. On the ordinary path every version has already
      // retired at the node that last used it, and releasing again from here
      // would hand one texture back twice.
      resources.releaseAll();
      rethrow;
    }

    // Out of the nodes rather than out of the calls, which is the shape of
    // every one of these: the frame reports what its passes counted. The draws
    // themselves went into `passState` where they happened.
    final scenePass = sceneNode.result!;
    final debugLines = scenePass.debugLines + compositeNode.overlayLines;

    final frame = _ldrColor!;
    frameClock.stop();
    developer.Timeline.finishSync();

    return FrameResult(
      frame: frame,
      cpuMicros: frameClock.elapsedMicroseconds,
      submitMicros: scenePass.submitMicros,
      drawCalls: passState.drawCalls,
      culled: scenePass.culled,
      pipelineSwitches: passState.pipelineSwitches,
      debugLines: debugLines,
      lights: lights.count,
      lightsDropped: scenePass.lightOverflow,
      pipelines: _pipelineCache.length,
      shadowCasters: _shadowCasters,
      skinnedDraws: passState.skinnedDraws,
    );
  }

  /// Adds screen-space reflections, returning the texture the rest of the
  /// chain should treat as the scene.
  ///
  /// Its own target rather than in place: the pass samples the scene while it
  /// writes, and a texture cannot be both. Returns [scene] untouched when the
  /// effect is off, so the chain downstream never branches.
  TextureHandle _encodeReflections({
    required TextureHandle scene,
    required RenderSettings settings,
    required RenderView view,
    required int width,
    required int height,
  }) {
    final surface = _surfaceColor;
    if (!settings.reflections.enabled || surface == null) return scene;
    developer.Timeline.startSync('Renderer.reflections');

    final target = _reflectionColor!;
    final pass = device.beginRenderPass(RenderPassDescriptor(
      colors: <ColorTarget>[
        ColorTarget(texture: target, loadAction: LoadAction.dontCare),
      ],
    ));

    final full = ScreenRect(width: width, height: height);
    pass.setViewport(full);
    pass.setScissor(full);
    pass.setPrimitiveType(PrimitiveType.triangle);
    pass.setCullMode(CullMode.none);
    pass.setBlend(null);
    pass.setDepthWrite(false);
    pass.setDepthCompare(CompareFunction.always);
    pass.bindPipeline(
      _postPipeline(_reflectionPipeline, reflectionShader,
          (p) => _reflectionPipeline = p),
    );
    pass.bindVertexBuffer(_fullscreenTriangle, 3);
    pass.bindIndexBuffer(_identityIndices(3), IndexType.int32, 3);

    final aspect = height == 0 ? 1.0 : width / height;
    final viewProjection = view.camera.viewProjection(aspect);
    final inverse = vm.Matrix4.copy(viewProjection)..invert();
    view.camera.readWorldPosition(_reflectionCamera);

    final options = settings.reflections;
    _reflectionParams[0] = options.steps.toDouble();
    _reflectionParams[1] = options.stride;
    _reflectionParams[2] = options.thickness;
    _reflectionParams[3] = options.intensity;
    _reflectionScreen[0] = 1.0 / width;
    _reflectionScreen[1] = 1.0 / height;
    _reflectionScreen[3] = options.debugOnly ? 1.0 : 0.0;

    _reflectionCameraData[0] = _reflectionCamera.x;
    _reflectionCameraData[1] = _reflectionCamera.y;
    _reflectionCameraData[2] = _reflectionCamera.z;

    pass.bindUniformBlock(reflectionShader, _kReflectionInfoBlock, {
      'view_projection': viewProjection.storage,
      'inverse_view_projection': inverse.storage,
      'camera': _reflectionCameraData,
      'params': _reflectionParams,
      'screen': _reflectionScreen,
    });
    pass.bindTexture(reflectionShader, 'scene_texture', scene,
        sampler: _clampSampler);
    pass.bindTexture(reflectionShader, 'surface_texture', surface,
        sampler: _clampSampler);

    pass.draw();
    pass.submit();
    developer.Timeline.finishSync();
    return target;
  }

  /// The final pass: bloom in, tone map, sRGB, then the debug overlay on top.
  ///
  /// One pass for both because the overlay has to land on the finished image
  /// but must not be a separate render target — and because keeping the pass
  /// open is free, while a second one would reload the attachment.
  ///
  /// Returns the number of overlay line segments drawn.
  int _encodeComposite({
    required TextureHandle target,
    required TextureHandle scene,
    required TextureHandle? bloom,
    required TextureHandle? surface,
    required TextureHandle? shadowView,
    required Scene sceneGraph,
    required List<RenderView> views,
    required RenderSettings settings,
    required int width,
    required int height,
  }) {
    final pass = device.beginRenderPass(RenderPassDescriptor(
      colors: <ColorTarget>[
        ColorTarget(texture: target, loadAction: LoadAction.dontCare),
      ],
    ));

    final full = ScreenRect(width: width, height: height);
    pass.setViewport(full);
    pass.setScissor(full);
    pass.setPrimitiveType(PrimitiveType.triangle);
    pass.setCullMode(CullMode.none);
    pass.setBlend(null);
    pass.setDepthWrite(false);
    pass.setDepthCompare(CompareFunction.always);

    final mix = CompositeMix(
      showSurfaceBuffer: settings.showSurfaceBuffer,
      showPointShadowDebug: settings.showPointShadowDebug,
      showShadowMap: settings.showShadowMap,
      hasShadowView: shadowView != null,
      hasGlow: bloom != null,
      exposure: settings.exposure,
      bloomIntensity: settings.bloom.intensity,
      tonemap: settings.tonemap,
    );
    _compositeParams[0] = mix.exposure;
    _compositeParams[1] = mix.bloomIntensity;
    _compositeParams[2] = mix.tonemap;

    pass.bindPipeline(
      _postPipeline(_compositePipeline, compositeShader,
          (p) => _compositePipeline = p),
    );
    pass.bindVertexBuffer(_fullscreenTriangle, 3);
    pass.bindIndexBuffer(_identityIndices(3), IndexType.int32, 3);
    pass.bindTexture(
      compositeShader,
      _kSceneTextureSlot,
      switch (mix.view) {
        // Non-null by construction: [CompositeMix] only picks these when it was
        // told the texture exists.
        CompositeView.shadowMap => shadowView!,
        CompositeView.surfaceBuffer => surface ?? scene,
        CompositeView.scene => scene,
      },
      sampler: _clampSampler,
    );
    // With bloom culled there is still a sampler to satisfy, and the scene
    // itself is the cheapest texture to hand it — [CompositeMix] set the
    // intensity to zero for exactly this case, so its contribution is
    // multiplied out. The two knobs come from one object because nothing in the
    // shader would notice them disagreeing.
    pass.bindTexture(
      compositeShader,
      _kBloomTextureSlot,
      mix.usesGlow ? bloom! : scene,
      sampler: _clampSampler,
    );
    pass.bindUniformBlock(compositeShader, _kCompositeInfoBlock, {
      'params': _compositeParams,
    });
    pass.draw();

    if (!settings.debug.anyEnabled && settings.highlighted.isEmpty) {
      pass.submit();
      return 0;
    }

    var lines = 0;
    for (final view in views) {
      final fraction = view.viewportFraction;
      final vw = math.max(1, (fraction.width * width).round());
      final vh = math.max(1, (fraction.height * height).round());
      // The viewport alone, inside a scissor that already covers the whole
      // frame: the overlay is clipped by the pass, not by the view.
      pass.setViewport(
        ScreenRect(
          x: (fraction.x * width).round(),
          y: (fraction.y * height).round(),
          width: vw,
          height: vh,
        ),
      );

      if (_encodeDebugLines(
        encoder: pass,
        scene: sceneGraph,
        view: view,
        viewProjection: view.camera.viewProjection(vw / vh),
        aspect: vw / vh,
        settings: settings,
      )) {
        lines += debugDraw.lineCount;
      }
    }
    pass.submit();
    return lines;
  }

  /// Draws into two colour attachments and reports what came back.
  ///
  /// A probe rather than a feature: `RenderTarget.colorAttachments` is a list
  /// and `setColorBlendEnable` takes an attachment index, so MRT looks supported
  /// — but "looks supported in the bindings" has been wrong twice in this
  /// project already, and the deferred-style effects that would depend on it are
  /// worth nothing if the second attachment is silently dropped.
  ///
  /// Returns a human-readable verdict. Costs two 4x4 textures and one draw, and
  /// is only called when asked for.
  Future<String> probeMultipleRenderTargets() async {
    final probe = shaders['MrtProbe'];
    if (probe == null) return 'MRT probe: the bundle has no MrtProbe entry.';

    const size = 4;
    TextureHandle makeTarget() => device.createTexture(RenderTargetSpec(
          width: size,
          height: size,
          format: device.defaultColorFormat,
        ));

    final first = makeTarget();
    final second = makeTarget();

    try {
      final pass = device.beginRenderPass(RenderPassDescriptor(
        colors: <ColorTarget>[
          ColorTarget(texture: first, clearValue: vm.Vector4.zero()),
          ColorTarget(texture: second, clearValue: vm.Vector4.zero()),
        ],
      ));

      final full = ScreenRect(width: size, height: size);
      pass.setViewport(full);
      pass.setScissor(full);
      pass.setPrimitiveType(PrimitiveType.triangle);
      pass.setCullMode(CullMode.none);
      pass.setBlend(null);
      pass.setBlend(null, attachment: 1);
      pass.setDepthWrite(false);
      pass.setDepthCompare(CompareFunction.always);

      pass.bindPipeline(device.createPipeline(fullscreenVertexShader, probe));
      pass.bindVertexBuffer(_fullscreenTriangle, 3);
      pass.bindIndexBuffer(_identityIndices(3), IndexType.int32, 3);
      pass.draw();
      pass.submit();

      // asImage plus toByteData is the only readback path available: there is
      // no buffer readback in flutter_gpu at all.
      final a = await device.readPixels(first);
      final b = await device.readPixels(second);
      if (a == null || b == null) return 'MRT probe: readback returned nothing.';

      String describe(ByteData data) =>
          '(${data.getUint8(0)}, ${data.getUint8(1)}, ${data.getUint8(2)})';

      // The shader writes distinct constants, so equal targets mean the second
      // attachment received a copy of the first rather than its own output.
      final same = a.getUint8(0) == b.getUint8(0) &&
          a.getUint8(2) == b.getUint8(2);
      return 'MRT probe: attachment 0 ${describe(a)}, attachment 1 '
          '${describe(b)} — ${same ? 'IDENTICAL, so the second output was not '
              'honoured' : 'distinct, so MRT works'}.';
    } catch (error) {
      return 'MRT probe: threw $error';
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

  final List<List<TextureHandle>> _pendingRelease = List<List<TextureHandle>>
      .generate(_kFramesInFlight, (_) => <TextureHandle>[]);

  /// Builds and submits the debug overlay for one view. Returns false when there
  /// was nothing to draw.
  ///
  /// The whole overlay is a single non-indexed `PrimitiveType.line` draw out of
  /// the per-frame host buffer, so switching it on costs one buffer write and one
  /// draw call no matter how much it shows.
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
    encoder.setPrimitiveType(PrimitiveType.line);
    encoder.setPolygonMode(PolygonMode.fill);
    encoder.setCullMode(CullMode.none);
    encoder.setBlend(null);
    // Drawn on top of the scene: a bounding box that disappears inside the very
    // object it bounds is not much of a diagnostic.
    encoder.setDepthWrite(false);
    encoder.setDepthCompare(CompareFunction.always);

    final vertexCount = debugDraw.vertexCount;
    encoder.bindVertexData(debugDraw.vertexBytes, vertexCount);
    encoder.bindIndexBuffer(
      _identityIndices(vertexCount),
      IndexType.int32,
      vertexCount,
    );
    encoder.bindUniformBlock(debugLineVertexShader, _kLineInfoBlock, {
      'view_projection': viewProjection.storage,
    });

    encoder.draw();
    developer.Timeline.finishSync();
    return true;
  }

  /// A view over the identity index sequence, growing the backing buffer when
  /// the overlay outgrows it.
  GeometryBuffer _identityIndices(int count) {
    if (count > _debugIndexCapacity) {
      var capacity = math.max(_debugIndexCapacity * 2, 1024);
      while (capacity < count) {
        capacity *= 2;
      }
      final indices = Uint32List(capacity);
      for (var i = 0; i < capacity; i++) {
        indices[i] = i;
      }
      _debugIndexBuffer = device.uploadGeometry(
          indices.buffer.asByteData(), GeometryUsage.indices);
      _debugIndexCapacity = capacity;
    }
    return _debugIndexBuffer!.slice(length: count * 4);
  }
}

/// Textures for a frame, from the pool, released a ring of frames later.
///
/// The deferring is the point — see [FrameTextureSource]. Handing a texture
/// straight back while the GPU is still reading it is a defect that shows up
/// as an intermittent wrong picture and never as an error.
final class _DeferredTextureSource implements FrameTextureSource {
  const _DeferredTextureSource(this._renderer);

  final Renderer _renderer;

  @override
  TextureHandle acquire(RenderTargetSpec spec) =>
      _renderer.targetPool.acquire(spec);

  @override
  void release(TextureHandle texture) => _renderer._releaseAfterFrame(texture);
}

/// The baked half of the point-light atlas, as a graph node.
///
/// The hardest client the graph has, and the pair of nodes the core API was
/// meant to be judged against. Four things about them are unlike every other
/// pass in the frame, and each is what a mechanical migration would have got
/// wrong.
///
/// **Both atlases are external and must stay external.** `cube_shadow_static`
/// is written once and read for many frames; a pooled texture handed back at
/// the end of this node would be lent to somebody else and
/// [ShadowSlotAllocator]'s record of which lights it holds would be an
/// assertion about a picture that no longer exists. `cube_shadow` is worse: it
/// is *loaded* rather than cleared, tiles are blanked by drawing over them, and
/// a tile the scheduler left out deliberately keeps last frame's pixels.
/// [ShadowFaceScheduler] makes a claim per tile about one specific texture.
///
/// **Neither node owns the allocator or the scheduler.** They are renderer
/// fields taken by reference. Nodes are rebuilt every frame — a node that owned
/// either would come into every frame having drawn nothing and never stop
/// re-baking.
///
/// **The atlas is declared as [FrameGraphNode.keeps] rather than as a write**,
/// which is the opposite of [_ShadowMapNode] and the reason that distinction
/// exists at all. The directional map is redrawn from nothing every frame, so a
/// frame that did not draw has no map and a reader must be told so. An atlas is
/// a running total: most frames it draws nothing and the pixels still stand for
/// exactly what the scene is about to sample. Declared as a write that was a
/// half-truth on every frame the pass skipped — and versioning cannot mend it,
/// because versions chain within a frame and this resource is read-modify-write
/// across them. The texture is therefore provided whether or not this frame
/// drew into it, and the graph now holds the node to that rather than trusting
/// this paragraph.
///
/// **[Renderer._ensureCubeAtlas] is called from here rather than from the
/// frame**, and from the dynamic node too. It is idempotent, so the second call
/// costs a comparison; what it buys is that neither node has to assume the
/// other ran. The one thing the graph could not express in this step is that
/// two nodes share a prologue: there is no word for "before either of these",
/// so it is written twice and made cheap instead.
final class _CubeShadowStaticNode extends RenderNode {
  _CubeShadowStaticNode(
    this._renderer, {
    required this.scene,
    required this.settings,
    required this.slotCount,
    required this.staticDirty,
  });

  final Renderer _renderer;
  final Scene scene;
  final ShadowSettings settings;

  /// How many atlas rows are occupied this frame; zero for none.
  final int slotCount;

  /// The allocator's verdict: a row changed hands, or its owner moved far
  /// enough that the walls baked for it are walls seen from somewhere else.
  final bool staticDirty;

  @override
  String get name => 'point shadows (static)';

  @override
  bool get isActive =>
      settings.enabled && settings.strength > 0.0 && slotCount > 0;

  /// Maintained, not written: the bake is valid for many frames and this node
  /// runs on most of them without touching a pixel.
  @override
  List<ResourceId> get keeps =>
      const <ResourceId>[FrameResourceIds.cubeShadowStatic];

  @override
  void execute(NodeFrame frame) {
    _renderer._ensureCubeAtlas(settings);

    // Every occupied row, not just the one that changed hands — a pass clears
    // its whole colour attachment, so redrawing one row erases the rest. The
    // allocator earns this back by changing at most one row per frame and only
    // for a light that clearly deserves it.
    //
    // `!_staticShadowBaked` is the other half, and it is how a reallocated
    // atlas gets its walls back: `_ensureCubeAtlas` clears the flag, so the
    // very next run of this node bakes whatever the new texture needs.
    if (staticDirty || !_renderer._staticShadowBaked) {
      _renderer._renderCubeShadow(
        resources: frame.resources,
        scene: scene,
        settings: settings,
        static: true,
        slotCount: slotCount,
      );
      _renderer._staticShadowBaked = true;
      // After drawing, not after deciding: a flag cleared by the decision would
      // promise walls that a skipped pass never drew.
      _renderer._shadowSlotAllocator.recordStaticBake();
    }

    // Non-null: `_ensureCubeAtlas` above allocated it if it did not exist.
    frame.resources.provide(
      FrameResourceIds.cubeShadowStatic,
      _renderer._cubeShadowStatic!,
    );
  }
}

/// The moving half of the point-light atlas, as a graph node.
///
/// Everything on [_CubeShadowStaticNode] applies here; this is the one that
/// actually carries pixels between frames. It redraws only the tiles whose
/// contents would come out different, and a tile it leaves alone keeps what it
/// held — which is only safe because a tile is blanked by *drawing* over it
/// rather than by clearing an attachment the viewport does not bound.
///
/// A separate node from the bake rather than one node writing both names,
/// because they run on completely different schedules: the bake fires when a
/// row changes hands, and this one fires when something moves. One node would
/// have had to be active whenever either was, and the profiler would have shown
/// one pass where the frame has two.
///
/// The schedule is chosen *inside* [execute] and not by the frame, and the
/// order matters: `_ensureCubeAtlas` may have thrown the texture away and reset
/// the scheduler, and a selection made before that would be a list of tiles
/// chosen against a texture that no longer exists.
final class _CubeShadowNode extends RenderNode {
  _CubeShadowNode(
    this._renderer, {
    required this.scene,
    required this.settings,
    required this.slotCount,
  });

  final Renderer _renderer;
  final Scene scene;
  final ShadowSettings settings;
  final int slotCount;

  @override
  String get name => 'point shadows';

  @override
  bool get isActive =>
      settings.enabled && settings.strength > 0.0 && slotCount > 0;

  /// The one resource in the frame that literally carries pixels between
  /// frames, and the reason [FrameGraphNode.keeps] exists.
  @override
  List<ResourceId> get keeps =>
      const <ResourceId>[FrameResourceIds.cubeShadow];

  @override
  void execute(NodeFrame frame) {
    _renderer._ensureCubeAtlas(settings);

    // Only the faces where what moves has actually changed. Most frames most
    // casters are standing still, and a face whose picture would come out the
    // same is a face worth leaving alone.
    final scheduled = _renderer._shadowFaceScheduler
        .select(_renderer._computeFaceSignatures(scene, slotCount))
        .toSet();
    if (scheduled.isNotEmpty) {
      _renderer._renderCubeShadow(
        resources: frame.resources,
        scene: scene,
        settings: settings,
        static: false,
        slotCount: slotCount,
        tiles: scheduled,
      );
      _renderer._shadowFaceScheduler.recordDrawn();
    }

    // Even when nothing was drawn. The tiles hold the pictures earlier frames
    // put there, and `_cubeFaceMatrices` holds the matrices that drew them —
    // the two are kept in step precisely so that a frame which draws nothing
    // still has an atlas worth sampling.
    frame.resources.provide(
      FrameResourceIds.cubeShadow,
      _renderer._cubeShadow!,
    );
  }
}

/// The directional light's shadow map, as a graph node.
///
/// The pass that had to move first, and the reason the scene moved with it:
/// a shadow map must be drawn before the scene that samples it, and until the
/// scene was a node there was nothing for the graph to order it against.
///
/// `shadow_map` is **external, not pooled**, and that is deliberate rather than
/// unfinished. [Renderer._shadowMap] outlives the frame and is `devicePrivate`
/// because the lighting pass samples it from a *later* command buffer; a pooled
/// target handed back at the end of this node would be lent to somebody else
/// while the scene was still reading it. So the node declares the write and
/// [FrameResources.provide]s the renderer's own texture, exactly as the
/// composite does with the finished image. What it does allocate — the depth
/// attachment — is scratch, and goes through [FrameResources.transient].
///
/// It is registered whether or not it will draw, and switched off through
/// [isActive]. Leaving it out would make `shadow_map` an unknown name and the
/// scene's optional read of it a compile error, which is the branch moved
/// rather than deleted — the same shape as bloom.
///
/// It **writes**, where the atlas nodes beside it keep, and that is the whole
/// content of the distinction: the map is redrawn from nothing every frame, so
/// the texture is provided only when the pass actually drew and the scene finds
/// out by asking. `_renderShadowMap` gives up on a scene with no bounds or a
/// missing shader, and neither of those is knowable at compile; a node that
/// provided regardless would tell the scene there was a shadow map when the
/// texture still held the last frame that had one. That the texture is
/// long-lived is a fact about who allocates it and says nothing about whose
/// frame the pixels belong to — the two questions are orthogonal, and only the
/// second one is [FrameGraphNode.keeps].
final class _ShadowMapNode extends RenderNode {
  _ShadowMapNode(
    this._renderer, {
    required this.scene,
    required this.settings,
    required this.casterIndex,
  });

  final Renderer _renderer;
  final Scene scene;
  final ShadowSettings settings;

  /// Which light in the packed buffer casts, or -1 for none.
  final int casterIndex;

  @override
  String get name => 'directional shadows';

  @override
  bool get isActive =>
      settings.enabled && settings.strength > 0.0 && casterIndex >= 0;

  @override
  List<ResourceId> get writes =>
      const <ResourceId>[FrameResourceIds.shadowMap];

  @override
  void execute(NodeFrame frame) {
    final drew = _renderer._renderShadowMap(
      resources: frame.resources,
      scene: scene,
      settings: settings,
      casterIndex: casterIndex,
    );
    if (!drew) return;
    frame.resources.provide(
      FrameResourceIds.shadowMap,
      // Non-null once the pass has drawn: it allocates the map before it opens
      // the render target.
      _renderer._shadowMap!,
    );
  }
}

/// The world, as a graph node — the pass everything else is ordered around.
///
/// It writes `hdr_colour` and `surface_buffer`, which is what took those two
/// names off [FrameGraph.addExternal]: the frame no longer hands the graph a
/// lit scene produced by code beside it. And it *optionally* reads the three
/// shadow maps, which is what lets anything be ordered before it at all.
///
/// Optional rather than hard, and the distinction is the whole reason
/// [FrameGraphNode.optionalReads] exists: a hard read would cull the scene the
/// moment shadows were switched off, and no read at all would cull the shadow
/// passes instead, since nothing would want what they produce.
///
/// All three shadow textures are now written by nodes: `shadow_map` by
/// [_ShadowMapNode] and the two atlases by [_CubeShadowStaticNode] and
/// [_CubeShadowNode]. Nothing about this node changed when they arrived, which
/// is the argument for the socket having been the right shape.
///
/// Unlike [_ReflectionsNode], which is single-view by construction, this draws
/// **every** ordered view in one pass. A viewport per view, one command buffer,
/// one submit — which is why the views are held here rather than derived from
/// [NodeFrame], and why the node cannot be split per view without splitting the
/// pass with it.
final class _SceneNode extends RenderNode {
  _SceneNode(
    this._renderer, {
    required this.scene,
    required this.ordered,
    required this.contributors,
    required this.shadowCaster,
    required this.lightOverflow,
  });

  final Renderer _renderer;
  final Scene scene;

  /// Every view, by priority — all of them drawn by this one pass.
  final List<RenderView> ordered;

  /// Handed in rather than looked up, so a node somebody else supplies can be
  /// given its own set. See [Renderer._encodeScene].
  final List<PassContributor> contributors;

  final int shadowCaster;
  final int lightOverflow;

  /// What the pass counted, for the frame's own report.
  _ScenePass? result;

  @override
  String get name => 'scene';

  @override
  List<ResourceId> get optionalReads => const <ResourceId>[
        FrameResourceIds.shadowMap,
        FrameResourceIds.cubeShadow,
        FrameResourceIds.cubeShadowStatic,
      ];

  @override
  List<ResourceId> get writes => const <ResourceId>[
        FrameResourceIds.hdrColour,
        FrameResourceIds.surfaceBuffer,
      ];

  @override
  void execute(NodeFrame frame) {
    final resources = frame.resources;

    // Asked of the frame that is running, not of a description of one, and not
    // of a setting: whether the buffer is wanted depends on what some *node*
    // declared, and an application's own node reading it is invisible to
    // `RenderSettings`. It decides both whether the second attachment is
    // present and whether the pass may multisample — attachments in one target
    // must agree on sample count — so a wrong answer here is silent.
    final surfaceIsRead =
        resources.graph.isConsumed(FrameResourceIds.surfaceBuffer);

    // Every map this pass samples, taken from the frame rather than from the
    // renderer, and every one of them is declared above. The directional map is
    // null when the shadow node was culled *and* when it ran and gave up — an
    // absent texture is a fact the graph derived, not a flag this pass was
    // handed. The two atlases are maintained rather than drawn, so a texture
    // here is valid to sample whether or not this frame touched a pixel of it;
    // that difference is now in their declaration and not in a comment.
    final shadows = SceneShadows(
      // Only a map this frame drew, and the asymmetry with the two atlases
      // below is the point of asking. The matrix a directional map is sampled
      // through is [Renderer._shadowMatrix], one field rewritten every frame —
      // so pixels from an earlier frame would be projected through this frame's
      // matrix and land somewhere else entirely. The atlas has no such problem
      // because `_cubeFaceMatrices` is deliberately kept in step with its tiles,
      // which is exactly what lets it be kept and this not be.
      directional:
          resources.originOf(FrameResourceIds.shadowMap) == ResourceOrigin.drawn
              ? resources.tryTexture(FrameResourceIds.shadowMap)
              : null,
      casterIndex: shadowCaster,
      point: resources.tryTexture(FrameResourceIds.cubeShadow),
      pointStatic: resources.tryTexture(FrameResourceIds.cubeShadowStatic),
    );

    // Before the draw, and in place: the pass writes into the renderer's own
    // targets rather than into anything the pool lent it, so the version it
    // produces stands on a texture nobody may hand back.
    final hdr = _renderer._hdrColor!;
    resources.provide(FrameResourceIds.hdrColour, hdr);
    if (surfaceIsRead) {
      // Only when it was attached. Binding the texture behind the name when
      // nothing filled it would offer a reader last frame's picture, which is
      // exactly the failure `showSurfaceBuffer` was written to catch.
      resources.provide(
        FrameResourceIds.surfaceBuffer,
        _renderer._surfaceColor ?? hdr,
      );
    }

    result = _renderer._encodeScene(
      scene: scene,
      ordered: ordered,
      settings: frame.settings,
      width: frame.width,
      height: frame.height,
      shadows: shadows,
      passState: frame.state,
      lightOverflowCount: lightOverflow,
      contributors: contributors,
      surfaceIsRead: surfaceIsRead,
    );
  }
}

/// Screen-space reflections, as a graph node.
///
/// Internal rather than something an application registers: it is one of the
/// engine's own passes, and the migration is moving them onto the same
/// interface an extension uses. If the interface cannot carry the engine's own
/// work it will not carry anybody else's either.
///
/// It reads the lit scene and writes it back — a link in the chain, not a
/// consumer of one — and it reads the surface buffer, which is what makes the
/// buffer get attached at all. That read is the whole of what
/// `RenderSettings.needsSurfaceBuffer` used to compute by hand.
final class _ReflectionsNode extends RenderNode {
  _ReflectionsNode(this._renderer, this._view);

  final Renderer _renderer;
  final RenderView _view;

  @override
  String get name => 'reflections';

  @override
  List<ResourceId> get reads => const <ResourceId>[
        FrameResourceIds.hdrColour,
        FrameResourceIds.surfaceBuffer,
      ];

  @override
  List<ResourceId> get writes =>
      const <ResourceId>[FrameResourceIds.hdrColour];

  @override
  void execute(NodeFrame frame) {
    final lit = _renderer._encodeReflections(
      scene: frame.resources.texture(FrameResourceIds.hdrColour),
      settings: frame.settings,
      view: _view,
      width: frame.width,
      height: frame.height,
    );
    // The pass produced a *different* texture rather than editing the one it
    // was given — it samples the scene while it writes, and a texture cannot be
    // both — so the version it wrote has to be told which texture it is. The
    // one it read keeps its own, and every reader registered after this point
    // is already bound to the new one.
    frame.resources.provide(FrameResourceIds.hdrColour, lit);
  }
}

/// The bloom pyramid, as a graph node.
///
/// The first pass in the frame whose output the graph **allocates**: everything
/// before it was handed a texture the renderer already owned. `bloom` is
/// declared as half the frame in the HDR format, the chain's top level is that
/// texture, and the levels below it are scratch — see
/// [FrameResources.transient].
///
/// Switching bloom off is [isActive], not a null return: nothing produces the
/// glow, so the node is culled and costs no pass, no texture and no branch.
final class _BloomNode extends RenderNode {
  _BloomNode(this._renderer, this._settings);

  final Renderer _renderer;
  final BloomSettings _settings;

  @override
  String get name => 'bloom';

  @override
  bool get isActive => _settings.enabled && _settings.intensity > 0.0;

  @override
  List<ResourceId> get reads => const <ResourceId>[FrameResourceIds.hdrColour];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.bloom];

  @override
  void execute(NodeFrame frame) {
    _renderer._renderBloom(
      resources: frame.resources,
      scene: frame.resources.texture(FrameResourceIds.hdrColour),
      top: frame.resources.texture(FrameResourceIds.bloom),
      settings: _settings,
    );
  }
}

/// Tone map, sRGB and the debug overlay, as a graph node — the end of the post
/// chain and the only pass that writes what is shown.
///
/// It reads the lit scene, which is a hard read: a composite with no colour has
/// nothing to say. The glow and the surface buffer are **optional**, and that
/// is what this step was for. Bloom switched off is a culled node whose output
/// nobody produced, so [FrameResources.tryTexture] answers null and the pass
/// binds its stand-in — which is a fact the graph derived rather than a flag
/// the composite was handed.
///
/// `frame` is external: the finished image goes into the renderer's own
/// `_ldrColor`, which outlives the frame and is what becomes the `ui.Image`. So
/// the node [FrameResources.provide]s its output instead of allocating one,
/// exactly as reflections does with its own target.
///
/// It holds the frame's scene and views the way [_ReflectionsNode] holds its
/// view. The overlay batch after the tone map needs both, it draws into the
/// same open pass — a second pass would reload the attachment — and [NodeFrame]
/// carries neither.
final class _CompositeNode extends RenderNode {
  _CompositeNode(this._renderer, this._scene, this._views, this._settings);

  final Renderer _renderer;
  final Scene _scene;
  final List<RenderView> _views;
  final RenderSettings _settings;

  /// How many overlay line segments the pass drew, for the frame's counters.
  int overlayLines = 0;

  @override
  String get name => 'composite';

  @override
  List<ResourceId> get reads => const <ResourceId>[FrameResourceIds.hdrColour];

  @override
  List<ResourceId> get optionalReads => <ResourceId>[
        FrameResourceIds.bloom,
        // Only when it is going to show it. An unconditional read would make
        // the buffer look wanted on every frame, and what wants it is what
        // decides whether the scene pass attaches it at all.
        if (_settings.showSurfaceBuffer || _settings.showPointShadowDebug)
          FrameResourceIds.surfaceBuffer,
        // The same rule for the shadow view. This pass can put a shadow map on
        // the screen instead of the lit image, and it used to reach into the
        // renderer's own fields for it — the second half of the hole the view
        // model had, and the same fix: declare the read, then ask the frame.
        // The atlas is preferred where there is one, because that is the map
        // anybody debugging shadows wants to see.
        if (_settings.showShadowMap) ...<ResourceId>[
          FrameResourceIds.cubeShadow,
          FrameResourceIds.shadowMap,
        ],
      ];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.frame];

  @override
  void execute(NodeFrame frame) {
    developer.Timeline.startSync('Renderer.composite');
    final target = _renderer._ldrColor!;
    // The renderer's texture, not the pool's, so the name is bound rather than
    // allocated. Before the draw, so anything reading `frame` after this node
    // finds the picture rather than nothing.
    frame.resources.provide(FrameResourceIds.frame, target);
    overlayLines = _renderer._encodeComposite(
      target: target,
      scene: frame.resources.texture(FrameResourceIds.hdrColour),
      bloom: frame.resources.tryTexture(FrameResourceIds.bloom),
      surface: frame.resources.tryTexture(FrameResourceIds.surfaceBuffer),
      // Null unless this frame declared the read above, which is what makes
      // `showShadowMap` fall back to the lit image rather than to whatever a
      // renderer field happened to be holding.
      shadowView: frame.resources.tryTexture(FrameResourceIds.cubeShadow) ??
          frame.resources.tryTexture(FrameResourceIds.shadowMap),
      sceneGraph: _scene,
      views: _views,
      settings: frame.settings,
      width: frame.width,
      height: frame.height,
    );
    // The composite is a draw, and so is the overlay batch.
    frame.state.drawCalls += 1 + (overlayLines > 0 ? 1 : 0);
    developer.Timeline.finishSync();
  }
}

/// What [Renderer._encodeScene] hands back to the frame.
final class _ScenePass {
  const _ScenePass({
    required this.culled,
    required this.debugLines,
    required this.lightOverflow,
    required this.submitMicros,
  });

  final int culled;
  final int debugLines;
  final int lightOverflow;
  final int submitMicros;
}
