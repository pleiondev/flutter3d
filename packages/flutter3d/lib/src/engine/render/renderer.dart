import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vm;

import '../gpu/gpu_mesh.dart';
import '../gpu/render_target_pool.dart';
import '../scene/camera_node.dart';
import '../scene/light_buffer.dart';
import '../scene/light_node.dart';
import '../scene/mesh_node.dart';
import '../scene/scene.dart';
import '../scene/scene_node.dart';
import 'debug_draw.dart';
import 'lighting_model.dart';
import 'material.dart';
import 'render_list.dart';
import 'render_plugin.dart';
import 'render_view.dart';

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

  /// Whether the scene pass should write the surface buffer at all.
  bool get needsSurfaceBuffer =>
      surfaceBuffer || showSurfaceBuffer || reflections.enabled;

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
final class ShadowSettings {
  const ShadowSettings({
    this.enabled = true,
    this.resolution = 2048,
    this.bias = 0.0015,
    this.normalOffset = 0.02,
    this.strength = 1.0,
    this.depthPadding = 1.2,
  });

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
  }) =>
      ShadowSettings(
        enabled: enabled ?? this.enabled,
        resolution: resolution ?? this.resolution,
        bias: bias ?? this.bias,
        normalOffset: normalOffset ?? this.normalOffset,
        strength: strength ?? this.strength,
        depthPadding: depthPadding ?? this.depthPadding,
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
    required this.image,
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

  final ui.Image image;

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
final class Renderer implements PluginServices {
  Renderer._({
    required this.library,
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
    required this.transients,
    required this.msaaEnabled,
  });

  @override
  final gpu.ShaderLibrary library;

  /// What draws alongside the world.
  ///
  /// A registry rather than a parameter per feature. `render()` grew one for
  /// the weapon view model and another for the particles, and fog, decals and
  /// a debug overlay would each have added a third — a parameter list is a
  /// registry with no ordering and nothing an application can add to.
  final PluginRegistry plugins = PluginRegistry();

  T addPlugin<T extends RenderPlugin>(T plugin) => plugins.add(plugin);

  bool removePlugin(RenderPlugin plugin) => plugins.remove(plugin);

  final gpu.Shader vertexShader;

  /// The skinned vertex stage. A separate shader because joints and weights are
  /// vertex attributes, and flutter_gpu takes the layout from the `in`
  /// declarations — so a skinned mesh cannot share a shader with a static one
  /// however similar the body is.
  final gpu.Shader skinnedVertexShader;

  /// The debug overlay's own stage pair. Separate from the mesh shaders because
  /// the line buffer has a different vertex layout, and flutter_gpu takes the
  /// layout from the shader's `in` declarations.
  final gpu.Shader debugLineVertexShader;
  final gpu.Shader particleVertexShader;
  final gpu.Shader particleFragmentShader;
  final gpu.Shader debugLineFragmentShader;

  /// The post-processing stages. All of them share one vertex shader, because a
  /// full-screen pass differs only in its fragment work.
  final gpu.Shader fullscreenVertexShader;
  final gpu.Shader bloomThresholdShader;
  final gpu.Shader bloomDownsampleShader;
  final gpu.Shader bloomUpsampleShader;
  final gpu.Shader compositeShader;

  /// The screen-space reflection pass.
  final gpu.Shader reflectionShader;

  /// 1x1 opaque white, bound when a material has no base-colour texture.
  ///
  /// A shader that declares a sampler must have something bound to it, so
  /// "no texture" has to be a neutral texture rather than an absent binding.
  /// White is also neutral for the ORM, occlusion and emissive slots: it
  /// multiplies each factor by one, so the same texture serves all four.
  final gpu.Texture fallbackAlbedo;

  /// 1x1 (0.5, 0.5, 1.0): the tangent-space normal that perturbs nothing.
  final gpu.Texture fallbackNormal;

  final bool msaaEnabled;

  /// Per-frame uniform allocators, rotated rather than reset in place.
  ///
  /// `CommandBuffer.submit` is asynchronous. Resetting a [gpu.HostBuffer] right
  /// after submit rewinds a bump allocator the GPU may still be reading, so the
  /// next frame overwrites live uniforms. The symptom is flickering under load,
  /// not a crash, which makes it hard to attribute.
  final List<gpu.HostBuffer> transients;
  int _frameIndex = 0;

  static const int _kFramesInFlight = 3;

  /// Package-qualified, because the bundle belongs to `flutter3d` rather than
  /// to whichever application is running. The prefix is how Flutter addresses a
  /// dependency's assets, and it is the same string from inside this package's
  /// own example as from an application that merely depends on it.
  static const String bundleAsset =
      'packages/flutter3d/assets/shaders/flutter3d.shaderbundle';

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

  gpu.RenderPipeline? _debugLinePipeline;

  /// A 0, 1, 2, … index buffer for the debug overlay.
  ///
  /// The overlay's vertices are already in draw order, so indices carry no
  /// information — but `draw()` submits nothing without an index buffer bound,
  /// and there is no non-indexed entry point in the API. Keeping the identity
  /// sequence in a device buffer that only grows means the cost is one upload
  /// when the overlay gets bigger, not one per frame.
  gpu.DeviceBuffer? _debugIndexBuffer;
  int _debugIndexCapacity = 0;

  /// Pipelines keyed by both stages; creating one compiles and links state on
  /// the backend, far too expensive to repeat per frame.
  ///
  /// Keyed on the pair rather than the fragment shader alone, because skinning
  /// added a second vertex stage: with only the fragment name as the key, a
  /// skinned draw would be handed the static pipeline the first PBR draw built,
  /// and the vertex layouts do not match.
  final Map<String, gpu.RenderPipeline> _pipelineCache =
      <String, gpu.RenderPipeline>{};

  final Map<String, gpu.Shader> _fragmentShaders = <String, gpu.Shader>{};

  /// Textures reused across frames and across bloom levels.
  final RenderTargetPool targetPool = RenderTargetPool();

  int _targetWidth = 0;
  int _targetHeight = 0;

  /// The scene, in linear light with no upper bound. Everything post-processing
  /// does depends on values above display white surviving this far, which is
  /// exactly what the old 8-bit target threw away.
  gpu.Texture? _hdrColor;
  gpu.Texture? _hdrMsaa;
  gpu.Texture? _ldrColor;
  gpu.RenderPipeline? _reflectionPipeline;
  final Float32List _reflectionParams = Float32List(4);
  final Float32List _reflectionScreen = Float32List(4);
  final Float32List _reflectionCameraData = Float32List(4);
  final vm.Vector3 _reflectionCamera = vm.Vector3.zero();
  gpu.Texture? _reflectionColor;
  gpu.Texture? _surfaceColor;
  gpu.Texture? _surfaceMsaa;
  gpu.Texture? _depthStencil;

  /// A one-sample depth, for the frames that switch multisampling off because
  /// they want the surface buffer. Attachments in one target must agree on
  /// sample count, so a four-sample depth cannot sit beside a resolved colour.
  gpu.Texture? _depthStencilSingle;

  /// The HDR format, chosen once. Half floats rather than full: the extra range
  /// of `r32g32b32a32Float` buys nothing for light values and doubles the
  /// bandwidth of every post-processing read.
  static const gpu.PixelFormat hdrFormat = gpu.PixelFormat.r16g16b16a16Float;

  gpu.RenderPipeline? _shadowPipeline;
  gpu.RenderPipeline? _skinnedShadowPipeline;
  gpu.RenderPipeline? _bloomThresholdPipeline;
  gpu.RenderPipeline? _bloomDownsamplePipeline;
  gpu.RenderPipeline? _bloomUpsamplePipeline;
  gpu.RenderPipeline? _compositePipeline;

  /// Positions and UVs of the one triangle every full-screen pass draws.
  gpu.DeviceBuffer? _fullscreenVertices;

  /// World space to the shadow camera's clip space, rebuilt each frame the
  /// light or the scene moves.
  final vm.Matrix4 _shadowMatrix = vm.Matrix4.identity();
  final Float32List _shadowParams = Float32List(4);
  gpu.Texture? _shadowMap;
  int _shadowResolution = 0;
  int _shadowCasters = 0;



  /// Depth for the view-model pass, made on demand.
  ///
  /// Lazily rather than alongside the scene's targets, because most frames of
  /// most applications never draw one and a full-size depth buffer is megabytes
  /// nobody asked for.
  final Float32List _bloomParams = Float32List(4);
  final Float32List _compositeParams = Float32List(4);

  factory Renderer.create({
    required gpu.Texture fallbackAlbedo,
    required gpu.Texture fallbackNormal,
  }) {
    final library = gpu.ShaderLibrary.fromAsset(bundleAsset);
    if (library == null) {
      throw StateError('Failed to load the shader bundle: $bundleAsset');
    }
    gpu.Shader require(String name) {
      final shader = library[name];
      if (shader == null) {
        throw StateError(
          'The bundle has no "$name" entry. Check '
          'shaders/flutter3d.shaderbundle.json and rebuild with '
          'tool/build_shaders.sh.',
        );
      }
      return shader;
    }

    return Renderer._(
      library: library,
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
      transients: List<gpu.HostBuffer>.generate(
        _kFramesInFlight,
        (_) => gpu.gpuContext.createHostBuffer(),
      ),
      msaaEnabled: gpu.gpuContext.doesSupportOffscreenMSAA,
    );
  }

  int get pipelineCount => _pipelineCache.length;

  gpu.Shader _fragmentShaderFor(LightingModel model) {
    return _fragmentShaders.putIfAbsent(model.shaderName, () {
      final shader = library[model.shaderName];
      if (shader == null) {
        throw StateError(
          'The bundle has no "${model.shaderName}" fragment shader. '
          'Rebuild it with tool/build_shaders.sh.',
        );
      }
      return shader;
    });
  }

  gpu.RenderPipeline _pipelineFor(LightingModel model, {required bool skinned}) {
    return _pipelineCache.putIfAbsent(
      skinned ? 'skinned/${model.shaderName}' : model.shaderName,
      () => gpu.gpuContext.createRenderPipeline(
        skinned ? skinnedVertexShader : vertexShader,
        _fragmentShaderFor(model),
      ),
    );
  }

  void _ensureTargets(int width, int height) {
    if (width == _targetWidth && height == _targetHeight) return;

    final sampleCount = msaaEnabled ? 4 : 1;

    // The scene target is sampled by the composite pass, so it has to be
    // devicePrivate rather than transient — tile memory cannot be read back.
    _hdrColor = gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      width,
      height,
      format: hdrFormat,
      enableRenderTargetUsage: true,
      enableShaderReadUsage: true,
    );

    if (msaaEnabled) {
      // deviceTransient is tile memory: more bandwidth, less memory. Right for
      // intermediates like the MSAA and depth attachments, never read back.
      _hdrMsaa = gpu.gpuContext.createTexture(
        gpu.StorageMode.deviceTransient,
        width,
        height,
        format: hdrFormat,
        sampleCount: 4,
      );
    } else {
      _hdrMsaa = null;
    }

    // The final image is 8-bit and display-referred; it is what becomes the
    // ui.Image, so there is nothing to gain from more precision here.
    _ldrColor = gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      width,
      height,
      format: gpu.gpuContext.defaultColorFormat,
      enableRenderTargetUsage: true,
      enableShaderReadUsage: true,
    );

    // The surface buffer: world-space normal and depth, for whatever runs after
    // the scene. Allocated with the rest rather than on demand, because a
    // resize is the only moment any of this is allowed to be reallocated and a
    // buffer that appears mid-session would be the one that is the wrong size.
    _surfaceColor = gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      width,
      height,
      format: hdrFormat,
      enableRenderTargetUsage: true,
      enableShaderReadUsage: true,
    );
    _reflectionColor = gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      width,
      height,
      format: hdrFormat,
      enableRenderTargetUsage: true,
      enableShaderReadUsage: true,
    );

    _surfaceMsaa = msaaEnabled
        ? gpu.gpuContext.createTexture(
            gpu.StorageMode.deviceTransient,
            width,
            height,
            format: hdrFormat,
            sampleCount: 4,
          )
        : null;

    _depthStencil = gpu.gpuContext.createTexture(
      gpu.StorageMode.deviceTransient,
      width,
      height,
      format: gpu.gpuContext.defaultDepthStencilFormat,
      sampleCount: sampleCount,
    );

    _depthStencilSingle = msaaEnabled
        ? gpu.gpuContext.createTexture(
            gpu.StorageMode.deviceTransient,
            width,
            height,
            format: gpu.gpuContext.defaultDepthStencilFormat,
          )
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
  bool _renderCubeShadow({
    required gpu.HostBuffer host,
    required Scene scene,
    required ShadowSettings settings,
    required vm.Vector3 position,
    required double range,
    required bool static,
    required int slot,
  }) {
    if (!settings.enabled || settings.strength <= 0.0) return false;
    if (range <= 0.0) return false;

    final shader = library['ShadowDistance'];
    if (shader == null) return false;

    // A three-by-two grid of square tiles. Square because a ninety-degree
    // frustum is square, and any other aspect would stretch one axis of every
    // face.
    final tile = settings.resolution.clamp(128, 1024);
    final width = tile * 6;
    final height = tile * kShadowedLights;
    if (_cubeShadow == null || _cubeShadowTile != tile) {
      _cubeShadowStatic = gpu.gpuContext.createTexture(
        gpu.StorageMode.devicePrivate,
        width,
        height,
        format: hdrFormat,
        enableRenderTargetUsage: true,
        enableShaderReadUsage: true,
      );
      _cubeShadow = gpu.gpuContext.createTexture(
        gpu.StorageMode.devicePrivate,
        width,
        height,
        format: hdrFormat,
        enableRenderTargetUsage: true,
        enableShaderReadUsage: true,
      );
      _cubeShadowTile = tile;
      _staticShadowBaked = false;
    }

    final depth = targetPool.acquire(
      RenderTargetSpec(
        width: width,
        height: height,
        format: gpu.gpuContext.defaultDepthStencilFormat,
        storageMode: gpu.StorageMode.deviceTransient,
      ),
    );

    developer.Timeline.startSync('Renderer.cubeShadow');
    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final pass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(
          texture: static ? _cubeShadowStatic! : _cubeShadow!,
          // Cleared to the far end: anything no face drew reads as "nothing
          // between the light and the range", which is the right default for
          // a direction with no caster in it.
          clearValue: vm.Vector4(1.0, 1.0, 1.0, 1.0),
          storeAction: gpu.StoreAction.store,
        ),
        depthStencilAttachment: gpu.DepthStencilAttachment(
          texture: depth,
          depthClearValue: 1.0,
        ),
      ),
    );

    pass.setPrimitiveType(gpu.PrimitiveType.triangle);
    pass.setDepthWriteEnable(true);
    pass.setDepthCompareOperation(gpu.CompareFunction.less);
    pass.setColorBlendEnable(false);
    pass.setCullMode(gpu.CullMode.frontFace);

    _cubeLight[0] = position.x;
    _cubeLight[1] = position.y;
    _cubeLight[2] = position.z;
    _cubeLight[3] = range;

    final projection = PerspectiveProjection(
      fovYRadians: math.pi / 2,
      near: 0.05,
      far: range,
    ).toMatrix(1.0);
    final mvp = vm.Matrix4.identity();
    var drawn = 0;

    for (var face = 0; face < _cubeFaces.length; face++) {
      // A row of six per light: the face across, the light down.
      pass.setViewport(gpu.Viewport(
        x: face * tile,
        y: slot * tile,
        width: tile,
        height: tile,
      ));
      pass.setScissor(gpu.Scissor(
        x: face * tile,
        y: slot * tile,
        width: tile,
        height: tile,
      ));

      final (aim, up) = _cubeFaces[face];
      final view = _lookAt(position, position + aim, up);
      _cubeMatrix
        ..setFrom(projection)
        ..multiply(view);
      // Kept so the lighting projects with exactly what drew the face. See the
      // note in surface.glsl: deriving cube coordinates there instead would be
      // the same decision made twice, and the two would disagree on one face.
      final at = (slot * 6 + face) * 16;
      _cubeFaceMatrices.setRange(at, at + 16, _cubeMatrix.storage);

      for (final node in scene.meshes) {
        if (!node.visibleInHierarchy || !node.castsShadow) continue;
        // One pass draws the things that never move, the other the things that
        // do. Splitting them is the whole point: the walls are baked once and
        // only a spinning pickup, a monster or a door is redrawn.
        if (node.shadowIsStatic != static) continue;
        final mesh = node.mesh;
        if (mesh is! GpuMesh || mesh.indexCount == 0) continue;
        // Static geometry only for now: a skinned caster needs the skinned
        // vertex stage, and a monster's shadow is worth less than getting the
        // walls right first.
        if (node.skeleton != null) continue;

        pass.bindPipeline(
          _cubeShadowPipeline ??=
              gpu.gpuContext.createRenderPipeline(vertexShader, shader),
        );
        pass.setWindingOrder(
          node.worldIsMirrored
              ? gpu.WindingOrder.clockwise
              : gpu.WindingOrder.counterClockwise,
        );
        pass.bindVertexBuffer(mesh.vertexView, mesh.vertexCount);
        pass.bindIndexBuffer(mesh.indexView, mesh.indexType, mesh.indexCount);

        mvp
          ..setFrom(_cubeMatrix)
          ..multiply(node.worldMatrix);
        bindUniformBlock(pass, host, vertexShader, _kFrameInfoBlock, {
          'mvp': mvp.storage,
          'model': node.worldMatrix.storage,
          'normal_matrix': node.worldNormalMatrix.storage,
        });
        bindUniformBlock(pass, host, shader, 'ShadowLight', {
          'light': _cubeLight,
        });
        pass.draw();
        drawn++;
      }
    }

    commandBuffer.submit();
    targetPool.release(depth);
    developer.Timeline.finishSync();
    return drawn > 0;
  }

  /// How many point lights may have a cube map at once.
  ///
  /// Four, because the atlas is one texture and a row of six tiles per light
  /// at a usable size is already a large one. A fifth torch in a room goes
  /// unshadowed rather than evicting one that might be nearer — which torch
  /// matters is a level's judgement, not the renderer's.
  static const int kShadowedLights = 4;

  final Float32List _cubeFaceMatrices = Float32List(16 * 6 * kShadowedLights);
  final Float32List _cubeLightData = Float32List(4 * kShadowedLights);

  /// One vec4 per light the shading knows about; x is its atlas row or -1.
  final Float32List _shadowSlots = Float32List(4 * LightBuffer.maxLights);

  final Float32List _pointShadowParams = Float32List(4);

  /// Number of atlas rows in use, or -1 when none are.
  int _cubeShadowLight = -1;

  final vm.Vector3 _cubePosition = vm.Vector3.zero();

  gpu.RenderPipeline? _cubeShadowPipeline;
  gpu.Texture? _cubeShadow;
  gpu.Texture? _cubeShadowStatic;
  bool _staticShadowBaked = false;
  int _cubeShadowTile = 0;
  final vm.Matrix4 _cubeMatrix = vm.Matrix4.identity();
  final Float32List _cubeLight = Float32List(4);

  bool _renderShadowMap({
    required gpu.HostBuffer host,
    required Scene scene,
    required ShadowSettings settings,
    required int casterIndex,
  }) {
    _shadowParams[3] = 0.0;
    _shadowCasters = 0;
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
      _shadowMap = gpu.gpuContext.createTexture(
        gpu.StorageMode.devicePrivate,
        resolution,
        resolution,
        format: hdrFormat,
        enableRenderTargetUsage: true,
        enableShaderReadUsage: true,
      );
      _shadowResolution = resolution;
    }

    final depth = targetPool.acquire(
      RenderTargetSpec(
        width: resolution,
        height: resolution,
        format: gpu.gpuContext.defaultDepthStencilFormat,
        storageMode: gpu.StorageMode.deviceTransient,
      ),
    );

    developer.Timeline.startSync('Renderer.shadowPass');
    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final pass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(
          texture: _shadowMap!,
          // Cleared to the far plane, so anything the pass does not draw reads
          // as "nothing between here and the light".
          clearValue: vm.Vector4(1.0, 1.0, 1.0, 1.0),
          storeAction: gpu.StoreAction.store,
        ),
        depthStencilAttachment: gpu.DepthStencilAttachment(
          texture: depth,
          depthClearValue: 1.0,
        ),
      ),
    );

    pass.setViewport(
      gpu.Viewport(x: 0, y: 0, width: resolution, height: resolution),
    );
    pass.setScissor(
      gpu.Scissor(x: 0, y: 0, width: resolution, height: resolution),
    );
    pass.setPrimitiveType(gpu.PrimitiveType.triangle);
    pass.setDepthWriteEnable(true);
    pass.setDepthCompareOperation(gpu.CompareFunction.less);
    pass.setColorBlendEnable(false);
    // Front faces culled, so the depth stored is the back of each caster. That
    // moves the comparison surface away from the lit face and removes most of
    // the acne before bias and normal offset have to deal with any.
    pass.setCullMode(gpu.CullMode.frontFace);

    final shadowShader = library['ShadowDepth'];
    if (shadowShader == null) {
      developer.Timeline.finishSync();
      targetPool.release(depth);
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
      if (mesh is! GpuMesh || mesh.indexCount == 0) continue;

      final skeleton = node.skeleton;
      final skinned = skeleton != null;
      if (boundSkinned != skinned) {
        pass.bindPipeline(
          skinned
              ? (_skinnedShadowPipeline ??= gpu.gpuContext.createRenderPipeline(
                  skinnedVertexShader,
                  shadowShader,
                ))
              : (_shadowPipeline ??= gpu.gpuContext.createRenderPipeline(
                  vertexShader,
                  shadowShader,
                )),
        );
        boundSkinned = skinned;
      }

      pass.setWindingOrder(
        node.worldIsMirrored
            ? gpu.WindingOrder.clockwise
            : gpu.WindingOrder.counterClockwise,
      );
      pass.bindVertexBuffer(mesh.vertexView, mesh.vertexCount);
      pass.bindIndexBuffer(mesh.indexView, mesh.indexType, mesh.indexCount);

      mvp
        ..setFrom(_shadowMatrix)
        ..multiply(node.worldMatrix);
      final stage = skinned ? skinnedVertexShader : vertexShader;
      bindUniformBlock(pass, host, stage, _kFrameInfoBlock, {
        'mvp': mvp.storage,
        'model': node.worldMatrix.storage,
        'normal_matrix': node.worldNormalMatrix.storage,
      });
      if (skeleton != null) {
        skeleton.update(node.worldMatrix);
        bindUniformBlock(pass, host, skinnedVertexShader, _kSkinInfoBlock, {
          'joint_matrices': skeleton.matrices,
        });
      }
      pass.draw();
      _shadowCasters++;
    }

    commandBuffer.submit();
    developer.Timeline.finishSync();

    _releaseAfterFrame(depth);

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
  gpu.BufferView get _fullscreenTriangle {
    final buffer = _fullscreenVertices ??=
        gpu.gpuContext.createDeviceBufferWithCopy(
      Float32List.fromList(<double>[
        -1.0, -1.0, 0.0, 1.0, //
        3.0, -1.0, 2.0, 1.0, //
        -1.0, 3.0, 0.0, -1.0, //
      ]).buffer.asByteData(),
    );
    return gpu.BufferView(
      buffer,
      offsetInBytes: 0,
      lengthInBytes: buffer.sizeInBytes,
    );
  }

  gpu.RenderPipeline _postPipeline(
    gpu.RenderPipeline? cached,
    gpu.Shader fragment,
    void Function(gpu.RenderPipeline) store,
  ) {
    if (cached != null) return cached;
    final pipeline =
        gpu.gpuContext.createRenderPipeline(fullscreenVertexShader, fragment);
    store(pipeline);
    return pipeline;
  }

  /// Runs one full-screen pass into [target].
  ///
  /// Every post stage is the same shape — bind the triangle, bind a source
  /// texture, write a small uniform block, draw three vertices — so it is
  /// written once and parameterized.
  void _drawFullscreen({
    required gpu.HostBuffer host,
    required gpu.Texture target,
    required gpu.RenderPipeline pipeline,
    required gpu.Shader fragment,
    required Map<String, gpu.Texture> textures,
    required String uniformBlock,
    required Float32List uniformData,
    required String uniformMember,
  }) {
    // One command buffer per pass, because Metal allows a single encoder open
    // at a time and flutter_gpu offers no way to end one. Buffers submitted to
    // the same queue execute in submission order, which is the ordering these
    // passes need.
    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final pass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(
          texture: target,
          // Nothing under a full-screen pass survives it, so clearing is both
          // correct and cheaper than loading the previous contents.
          loadAction: gpu.LoadAction.dontCare,
          storeAction: gpu.StoreAction.store,
        ),
      ),
    );

    pass.setViewport(
      gpu.Viewport(x: 0, y: 0, width: target.width, height: target.height),
    );
    pass.setScissor(
      gpu.Scissor(x: 0, y: 0, width: target.width, height: target.height),
    );
    pass.setPrimitiveType(gpu.PrimitiveType.triangle);
    pass.setCullMode(gpu.CullMode.none);
    pass.setColorBlendEnable(false);
    pass.setDepthWriteEnable(false);
    pass.setDepthCompareOperation(gpu.CompareFunction.always);

    pass.bindPipeline(pipeline);
    pass.bindVertexBuffer(_fullscreenTriangle, 3);
    pass.bindIndexBuffer(_identityIndices(3), gpu.IndexType.int32, 3);

    textures.forEach((slot, texture) {
      _bindTexture(pass, fragment, slot, texture, _clampSampler);
    });

    bindUniformBlock(pass, host, fragment, uniformBlock, {
      uniformMember: uniformData,
    });

    pass.draw();
    commandBuffer.submit();
  }

  /// Clamped and linear: a post pass reading outside the source would otherwise
  /// wrap the opposite edge of the screen into the glow.
  static final gpu.SamplerOptions _clampSampler = gpu.SamplerOptions(
    minFilter: gpu.MinMagFilter.linear,
    magFilter: gpu.MinMagFilter.linear,
    widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
    heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
  );

  /// Builds the bloom chain and returns its top level, or null when bloom is
  /// off. Any intermediate levels are returned to the pool.
  gpu.Texture? _renderBloom({
    required gpu.HostBuffer host,
    required gpu.Texture scene,
    required BloomSettings settings,
  }) {
    if (!settings.enabled || settings.intensity <= 0.0) return null;

    final levels = settings.levels.clamp(1, 8);
    final chain = <gpu.Texture>[];

    var sourceWidth = scene.width;
    var sourceHeight = scene.height;
    gpu.Texture source = scene;

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

      final target = targetPool.acquire(spec);
      _bloomParams[0] = 1.0 / sourceWidth;
      _bloomParams[1] = 1.0 / sourceHeight;
      _bloomParams[2] = level == 0 ? settings.threshold : 0.0;
      _bloomParams[3] = level == 0 ? settings.knee : 0.0;

      final isFirst = level == 0;
      _drawFullscreen(
        host: host,
        target: target,
        pipeline: isFirst
            ? _postPipeline(_bloomThresholdPipeline, bloomThresholdShader,
                (p) => _bloomThresholdPipeline = p)
            : _postPipeline(_bloomDownsamplePipeline, bloomDownsampleShader,
                (p) => _bloomDownsamplePipeline = p),
        fragment: isFirst ? bloomThresholdShader : bloomDownsampleShader,
        textures: <String, gpu.Texture>{_kPostSourceSlot: source},
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

      _drawFullscreenAdditive(
        host: host,
        target: into,
        source: from,
      );
    }
    developer.Timeline.finishSync();

    // Everything below the top is scratch.
    for (var level = 1; level < chain.length; level++) {
      targetPool.release(chain[level]);
    }
    return chain.isEmpty ? null : chain.first;
  }

  /// The upsample step, which differs from every other post pass by blending
  /// rather than replacing.
  void _drawFullscreenAdditive({
    required gpu.HostBuffer host,
    required gpu.Texture target,
    required gpu.Texture source,
  }) {
    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final pass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(
          texture: target,
          // Load, not clear: the point is to add to what the downsample left.
          loadAction: gpu.LoadAction.load,
          storeAction: gpu.StoreAction.store,
        ),
      ),
    );

    pass.setViewport(
      gpu.Viewport(x: 0, y: 0, width: target.width, height: target.height),
    );
    pass.setScissor(
      gpu.Scissor(x: 0, y: 0, width: target.width, height: target.height),
    );
    pass.setPrimitiveType(gpu.PrimitiveType.triangle);
    pass.setCullMode(gpu.CullMode.none);
    pass.setDepthWriteEnable(false);
    pass.setDepthCompareOperation(gpu.CompareFunction.always);
    pass.setColorBlendEnable(true);
    pass.setColorBlendEquation(
      gpu.ColorBlendEquation(
        sourceColorBlendFactor: gpu.BlendFactor.one,
        destinationColorBlendFactor: gpu.BlendFactor.one,
        sourceAlphaBlendFactor: gpu.BlendFactor.one,
        destinationAlphaBlendFactor: gpu.BlendFactor.one,
      ),
    );

    pass.bindPipeline(
      _postPipeline(_bloomUpsamplePipeline, bloomUpsampleShader,
          (p) => _bloomUpsamplePipeline = p),
    );
    pass.bindVertexBuffer(_fullscreenTriangle, 3);
    pass.bindIndexBuffer(_identityIndices(3), gpu.IndexType.int32, 3);
    _bindTexture(
      pass,
      bloomUpsampleShader,
      _kPostSourceSlot,
      source,
      _clampSampler,
    );
    bindUniformBlock(pass, host, bloomUpsampleShader, _kBloomInfoBlock, {
      'params': _bloomParams,
    });
    pass.draw();
    commandBuffer.submit();
  }

  /// Writes a uniform block using shader reflection, then binds it. Returns false
  /// when the shader has no such block.
  ///
  /// Members the shader never reads are dropped from the reflected block, so they
  /// are skipped rather than treated as errors: the unlit model legitimately has
  /// no `light_direction`.
  @override
  bool bindUniformBlock(
    gpu.RenderPass pass,
    gpu.HostBuffer host,
    gpu.Shader shader,
    String blockName,
    Map<String, Float32List> members,
  ) {
    final slot = shader.getUniformSlot(blockName);
    final size = slot.sizeInBytes;
    if (size == null || size == 0) return false;

    final data = ByteData(size);
    members.forEach((name, values) {
      final offset = slot.getMemberOffsetInBytes(name);
      if (offset == null) return;
      for (var i = 0; i < values.length; i++) {
        data.setFloat32(offset + i * 4, values[i], Endian.host);
      }
    });

    pass.bindUniform(slot, host.emplace(data));
    return true;
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
    required gpu.RenderPass pass,
    required gpu.HostBuffer host,
    required MeshNode node,
    required Scene scene,
    required RenderSettings settings,
    required vm.Matrix4 viewProjection,
    required bool hasShadows,
    required int shadowCaster,
    required FramePassState state,
  }) {
      final mesh = node.mesh;
      // The scene deals in MeshGeometry so that culling and picking need no
      // device; only here does it matter that the geometry actually reached
      // the GPU. A CPU-only mesh in a drawn scene is a bug in the caller,
      // not something to skip quietly.
      if (mesh is! GpuMesh) {
        throw StateError(
          'MeshNode "${node.name}" holds ${mesh.runtimeType}, which has no '
          'GPU buffers. Upload it with GpuMesh.upload before drawing it.',
        );
      }
      final material = node.material;

      final skeleton = node.skeleton;
      final skinned = skeleton != null;
      if (state.boundPipeline != material.lighting || state.boundSkinned != skinned) {
        pass.bindPipeline(
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

      pass.setWindingOrder(
        node.worldIsMirrored
            ? gpu.WindingOrder.clockwise
            : gpu.WindingOrder.counterClockwise,
      );
      final cull = settings.backfaceCulling &&
          !settings.wireframe &&
          !material.doubleSided;
      pass.setCullMode(cull ? gpu.CullMode.backFace : gpu.CullMode.none);

      final blend = material.alphaMode == MaterialAlphaMode.blend;
      pass.setColorBlendEnable(blend);
      if (blend) {
        pass.setColorBlendEquation(gpu.ColorBlendEquation());
        // Transparent surfaces must not occlude what is behind them.
        pass.setDepthWriteEnable(false);
      } else {
        pass.setDepthWriteEnable(true);
      }

      pass.bindVertexBuffer(mesh.vertexView, mesh.vertexCount);
      pass.bindIndexBuffer(
        mesh.indexView,
        mesh.indexType,
        mesh.indexCount,
      );

      final activeVertexShader =
          skinned ? skinnedVertexShader : vertexShader;
      bindUniformBlock(pass, host, activeVertexShader, _kFrameInfoBlock, {
        'mvp': (viewProjection * modelMatrix).storage,
        'model': modelMatrix.storage,
        'normal_matrix': normalMatrix.storage,
      });

      if (skeleton != null) {
        // Recomputed here rather than by the caller: the matrices depend on
        // the mesh node's own world transform, which is exactly what the
        // renderer is holding at this point.
        skeleton.update(modelMatrix);
        bindUniformBlock(
          pass,
          host,
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
        _frameParams[2] = hasShadows ? shadowCaster.toDouble() : -1.0;

      // Its own block, bound beside FragInfo rather than folded into it. See
      // the note in color.glsl: appending to a block six shaders share moves
      // offsets nobody expected to move.
      final fog = settings.fog;
      _fogData[0] = fog.resolvedColor.x;
      _fogData[1] = fog.resolvedColor.y;
      _fogData[2] = fog.resolvedColor.z;
      _fogData[3] = fog.density;
      _pointShadowParams[0] = _cubeShadowLight.toDouble();
      _pointShadowParams[1] = 0.08;
      _pointShadowParams[2] =
          _cubeShadowLight < 0 ? 0.0 : settings.shadows.strength;
      bindUniformBlock(pass, host, fragmentShader, 'PointShadow', {
        'faces': _cubeFaceMatrices,
        'lights': _cubeLightData,
        'slots': _shadowSlots,
        'params': _pointShadowParams,
      });
      _bindTexture(
        pass,
        fragmentShader,
        'point_shadow_texture',
        _cubeShadow ?? fallbackAlbedo,
        _clampSampler,
      );
      _bindTexture(
        pass,
        fragmentShader,
        'point_shadow_static_texture',
        _cubeShadowStatic ?? fallbackAlbedo,
        _clampSampler,
      );

      bindUniformBlock(pass, host, fragmentShader, _kFogInfoBlock, {
        'fog': _fogData,
        'eye': _cameraData,
      });

        bindUniformBlock(pass, host, fragmentShader, _kFragInfoBlock, {
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
        _bindTexture(
          pass,
          fragmentShader,
          _kAlbedoTextureSlot,
          material.albedo ?? fallbackAlbedo,
          material.albedoSampler,
        );
      }
      if (material.lighting.usesMaterialMaps) {
        _bindTexture(
          pass,
          fragmentShader,
          _kNormalTextureSlot,
          material.normal ?? fallbackNormal,
          material.normalSampler,
        );
        _bindTexture(
          pass,
          fragmentShader,
          _kOcclusionTextureSlot,
          material.occlusion ?? fallbackAlbedo,
          material.occlusionSampler,
        );
        _bindTexture(
          pass,
          fragmentShader,
          _kEmissiveTextureSlot,
          material.emissiveTexture ?? fallbackAlbedo,
          material.emissiveSampler,
        );
      }
      if (material.lighting.usesShadowMap) {
        _bindTexture(
          pass,
          fragmentShader,
          _kShadowTextureSlot,
          // With shadows off the slot still has to be satisfied, and a white
          // texture reads as "nothing between here and the light" — which is
          // also what the zero strength above already guarantees.
          hasShadows ? _shadowMap! : fallbackAlbedo,
          _clampSampler,
        );
      }
      if (material.lighting.usesMetallicRoughnessMap) {
        _bindTexture(
          pass,
          fragmentShader,
          _kMetallicRoughnessTextureSlot,
          material.metallicRoughness ?? fallbackAlbedo,
          material.metallicRoughnessSampler,
        );
      }

      pass.draw();
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
    required gpu.RenderPass pass,
    required gpu.HostBuffer host,
    required Scene scene,
    required vm.Matrix4 viewProjection,
    required vm.Vector3 cameraPosition,
    required RenderSettings settings,
    required FramePassState state,
  }) {
    _cameraData[0] = cameraPosition.x;
    _cameraData[1] = cameraPosition.y;
    _cameraData[2] = cameraPosition.z;

    for (final node in scene.meshes) {
      if (!node.visibleInHierarchy) continue;
      _encodeNode(
        pass: pass,
        host: host,
        node: node,
        scene: scene,
        settings: settings,
        viewProjection: viewProjection,
        // No shadow map: geometry lit by the world's sun through a shadow
        // matrix built for the world's camera would be shadowed by things it
        // is nowhere near.
        hasShadows: false,
        shadowCaster: -1,
        state: state,
      );
    }
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

    final hdr = _hdrColor!;

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
    final msaa = settings.needsSurfaceBuffer ? null : _hdrMsaa;
    // The clear colour is authored the way a colour picker shows it, but the
    // scene target holds linear light and the composite pass encodes on the way
    // out. Clearing with the sRGB value directly would send it through the
    // encode twice and wash the background out.
    final clear = _srgbToLinear(views.first.clearColor);

    final colorAttachment = msaa == null
        ? gpu.ColorAttachment(texture: hdr, clearValue: clear)
        : gpu.ColorAttachment(
            texture: msaa,
            resolveTexture: hdr,
            storeAction: gpu.StoreAction.multisampleResolve,
            clearValue: clear,
          );

    // Attached only when something wants it. A pipeline may declare more
    // outputs than the target has attachments — the extra is discarded — so
    // the shaders write the surface unconditionally and this decides whether
    // anyone is listening. See RESEARCH.md.
    final surface = settings.needsSurfaceBuffer ? _surfaceColor : null;
    final surfaceAttachment = surface == null
        ? null
        : (msaa == null
            ? gpu.ColorAttachment(
                texture: surface,
                clearValue: vm.Vector4.zero(),
              )
            : gpu.ColorAttachment(
                texture: _surfaceMsaa!,
                resolveTexture: surface,
                storeAction: gpu.StoreAction.multisampleResolve,
                clearValue: vm.Vector4.zero(),
              ));

    final renderTarget = gpu.RenderTarget(
      colorAttachments: <gpu.ColorAttachment>[
        colorAttachment,
        ?surfaceAttachment,
      ],
      depthStencilAttachment: gpu.DepthStencilAttachment(
        texture: msaa == null ? (_depthStencilSingle ?? _depthStencil!)
            : _depthStencil!,
        // Standard depth: clear to the far plane, nearer fragments win.
        depthClearValue: 1.0,
      ),
    );

    final host = transients[_frameIndex % _kFramesInFlight];
    // This slot's textures were handed back a full ring ago, so the GPU is done
    // with them; the same reasoning that governs the host buffers.
    final expired = _pendingRelease[_frameIndex % _kFramesInFlight];
    for (final texture in expired) {
      targetPool.release(texture);
    }
    expired.clear();
    _frameIndex++;
    host.reset();

    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final pass = commandBuffer.createRenderPass(renderTarget);

    // Lights are gathered once up front now, because the shadow pass needs the
    // caster before any view is drawn — and the packed buffer is per frame, not
    // per view.
    lights.gather(scene.lights);
    if (lights.count == 0) lights.useDefaultLight();
    final lightOverflowCount = lights.overflow;
    final shadowCaster = _firstDirectionalIndex();
    final hasShadows = _renderShadowMap(
      host: host,
      scene: scene,
      settings: settings.shadows,
      casterIndex: shadowCaster,
    );

    // Up to four point lights get a row of the atlas each, in the order they
    // appear. In order rather than by importance because "which torch matters
    // most" is a level's judgement, not the renderer's, and a fifth simply
    // goes unshadowed rather than evicting one.
    for (var i = 0; i < _shadowSlots.length; i++) {
      _shadowSlots[i] = -1.0;
    }
    var slot = 0;
    for (final light in scene.lights) {
      if (slot >= kShadowedLights) break;
      if (light.type != LightType.point || !light.castsShadow) continue;
      final index = lights.packed.indexOf(light);
      if (index < 0) continue;

      light.readWorldPosition(_cubePosition);
      final range = light.range > 0.0 ? light.range : 20.0;

      // The walls once. Six views of the level's geometry is a load-time cost.
      if (!_staticShadowBaked) {
        _renderCubeShadow(
          host: host,
          scene: scene,
          settings: settings.shadows,
          position: _cubePosition,
          range: range,
          static: true,
          slot: slot,
        );
      }

      // And everything that moves, every frame. A pickup that spins would
      // otherwise leave its shadow behind in the pose it was baked in.
      _renderCubeShadow(
        host: host,
        scene: scene,
        settings: settings.shadows,
        position: _cubePosition,
        range: range,
        static: false,
        slot: slot,
      );

      _cubeLightData[slot * 4] = _cubePosition.x;
      _cubeLightData[slot * 4 + 1] = _cubePosition.y;
      _cubeLightData[slot * 4 + 2] = _cubePosition.z;
      _cubeLightData[slot * 4 + 3] = range;
      // Which atlas row this light's shader index should read.
      _shadowSlots[index * 4] = slot.toDouble();
      slot++;
    }
    _staticShadowBaked = _staticShadowBaked || slot > 0;
    _cubeShadowLight = slot > 0 ? 0 : -1;

    final ordered = List<RenderView>.of(views)
      ..sort((a, b) => a.priority.compareTo(b.priority));

    final passState = FramePassState();
    var culled = 0;
    var debugLines = 0;
    var lightOverflow = 0;

    final cameraPosition = vm.Vector3.zero();

    for (final view in ordered) {
      // Per view rather than once: the debug overlay at the end of each view
      // leaves the pass in line-drawing state, so the next view has to
      // re-establish its own.
      //
      // Viewport and scissor are set explicitly because both default to a
      // zero-sized rect, and nothing in the API complains about drawing into one.
      pass.setDepthWriteEnable(true);
      pass.setDepthCompareOperation(gpu.CompareFunction.less);
      pass.setPrimitiveType(gpu.PrimitiveType.triangle);
      pass.setPolygonMode(
        settings.wireframe ? gpu.PolygonMode.line : gpu.PolygonMode.fill,
      );

      final fraction = view.viewportFraction;
      final vx = (fraction.x * width).round();
      final vy = (fraction.y * height).round();
      final vw = math.max(1, (fraction.width * width).round());
      final vh = math.max(1, (fraction.height * height).round());

      pass.setViewport(gpu.Viewport(x: vx, y: vy, width: vw, height: vh));
      pass.setScissor(gpu.Scissor(x: vx, y: vy, width: vw, height: vh));

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
            pass: pass,
            host: host,
            node: node,
            scene: scene,
            settings: settings,
            viewProjection: viewProjection,
            hasShadows: hasShadows,
            shadowCaster: shadowCaster,
            state: passState,
          );
        }
      }
      developer.Timeline.finishSync();

      for (final plugin in plugins.forStage(RenderStage.inScene)) {
        plugin.encode(
          PluginFrame(
            pass: pass,
            host: host,
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
    commandBuffer.submit();
    stopwatch.stop();
    developer.Timeline.finishSync();

    for (final plugin in plugins.forStage(RenderStage.overlayScene)) {
      plugin.encode(
        PluginFrame(
          // A stage that owns its pass builds its own; this is the scene pass
          // it draws over, handed on so a plugin that only wants to append to
          // the world's pass still can.
          pass: pass,
          host: host,
          services: this,
          state: passState,
          settings: settings,
          width: width,
          height: height,
          sceneColor: hdr,
        ),
      );
    }

    // Before bloom, because a reflection is scene light and the bloom should
    // pick up a bright one — a reflected torch that does not glow reads as a
    // sticker on the floor.
    final lit = _encodeReflections(
      host: host,
      scene: hdr,
      settings: settings,
      view: views.first,
      width: width,
      height: height,
    );

    final bloom = _renderBloom(
      host: host,
      scene: lit,
      settings: settings.bloom,
    );

    developer.Timeline.startSync('Renderer.composite');
    final ldr = _ldrColor!;
    final overlayLines = _encodeComposite(
      host: host,
      target: ldr,
      scene: lit,
      bloom: bloom,
      sceneGraph: scene,
      views: ordered,
      settings: settings,
      width: width,
      height: height,
    );
    developer.Timeline.finishSync();

    debugLines += overlayLines;
    // The composite is a draw, and so is each overlay batch.
    passState.drawCalls += 1 + (overlayLines > 0 ? 1 : 0);

    if (bloom != null) _releaseAfterFrame(bloom);

    final image = ldr.asImage();
    frameClock.stop();
    developer.Timeline.finishSync();

    return FrameResult(
      image: image,
      cpuMicros: frameClock.elapsedMicroseconds,
      submitMicros: stopwatch.elapsedMicroseconds,
      drawCalls: passState.drawCalls,
      culled: culled,
      pipelineSwitches: passState.pipelineSwitches,
      debugLines: debugLines,
      lights: lights.count,
      lightsDropped: lightOverflow,
      pipelines: _pipelineCache.length,
      shadowCasters: _shadowCasters,
      skinnedDraws: passState.skinnedDraws,
    );
  }

  /// The final pass: bloom in, tone map, sRGB, then the debug overlay on top.
  ///
  /// One pass for both because the overlay has to land on the finished image
  /// but must not be a separate render target — and because keeping the pass
  /// open is free, while a second one would reload the attachment.
  ///
  /// Returns the number of overlay line segments drawn.
  /// Adds screen-space reflections, returning the texture the rest of the
  /// chain should treat as the scene.
  ///
  /// Its own target rather than in place: the pass samples the scene while it
  /// writes, and a texture cannot be both. Returns [scene] untouched when the
  /// effect is off, so the chain downstream never branches.
  gpu.Texture _encodeReflections({
    required gpu.HostBuffer host,
    required gpu.Texture scene,
    required RenderSettings settings,
    required RenderView view,
    required int width,
    required int height,
  }) {
    final surface = _surfaceColor;
    if (!settings.reflections.enabled || surface == null) return scene;
    developer.Timeline.startSync('Renderer.reflections');

    final target = _reflectionColor!;
    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final pass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(
          texture: target,
          loadAction: gpu.LoadAction.dontCare,
          storeAction: gpu.StoreAction.store,
        ),
      ),
    );

    pass.setViewport(gpu.Viewport(x: 0, y: 0, width: width, height: height));
    pass.setScissor(gpu.Scissor(x: 0, y: 0, width: width, height: height));
    pass.setPrimitiveType(gpu.PrimitiveType.triangle);
    pass.setCullMode(gpu.CullMode.none);
    pass.setColorBlendEnable(false);
    pass.setDepthWriteEnable(false);
    pass.setDepthCompareOperation(gpu.CompareFunction.always);
    pass.bindPipeline(
      _postPipeline(_reflectionPipeline, reflectionShader,
          (p) => _reflectionPipeline = p),
    );
    pass.bindVertexBuffer(_fullscreenTriangle, 3);
    pass.bindIndexBuffer(_identityIndices(3), gpu.IndexType.int32, 3);

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

    bindUniformBlock(pass, host, reflectionShader, _kReflectionInfoBlock, {
      'view_projection': viewProjection.storage,
      'inverse_view_projection': inverse.storage,
      'camera': _reflectionCameraData,
      'params': _reflectionParams,
      'screen': _reflectionScreen,
    });
    _bindTexture(pass, reflectionShader, 'scene_texture', scene, _clampSampler);
    _bindTexture(
        pass, reflectionShader, 'surface_texture', surface, _clampSampler);

    pass.draw();
    commandBuffer.submit();
    developer.Timeline.finishSync();
    return target;
  }

  int _encodeComposite({
    required gpu.HostBuffer host,
    required gpu.Texture target,
    required gpu.Texture scene,
    required gpu.Texture? bloom,
    required Scene sceneGraph,
    required List<RenderView> views,
    required RenderSettings settings,
    required int width,
    required int height,
  }) {
    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final pass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(
          texture: target,
          loadAction: gpu.LoadAction.dontCare,
          storeAction: gpu.StoreAction.store,
        ),
      ),
    );

    pass.setViewport(gpu.Viewport(x: 0, y: 0, width: width, height: height));
    pass.setScissor(gpu.Scissor(x: 0, y: 0, width: width, height: height));
    pass.setPrimitiveType(gpu.PrimitiveType.triangle);
    pass.setCullMode(gpu.CullMode.none);
    pass.setColorBlendEnable(false);
    pass.setDepthWriteEnable(false);
    pass.setDepthCompareOperation(gpu.CompareFunction.always);

    final showingSurface = settings.showSurfaceBuffer;
    // The cube atlas when there is one, because that is the map anybody
    // debugging shadows now wants to see.
    final shadowView = _cubeShadow ?? _shadowMap;
    final showingShadow = settings.showShadowMap && shadowView != null;
    final raw = showingSurface || showingShadow;
    _compositeParams[0] = raw ? 1.0 : settings.exposure;
    _compositeParams[1] = raw || bloom == null ? 0.0 : settings.bloom.intensity;
    _compositeParams[2] = raw || !settings.tonemap ? 0.0 : 1.0;

    pass.bindPipeline(
      _postPipeline(_compositePipeline, compositeShader,
          (p) => _compositePipeline = p),
    );
    pass.bindVertexBuffer(_fullscreenTriangle, 3);
    pass.bindIndexBuffer(_identityIndices(3), gpu.IndexType.int32, 3);
    _bindTexture(
      pass,
      compositeShader,
      _kSceneTextureSlot,
      showingShadow
          ? shadowView
          : (showingSurface ? (_surfaceColor ?? scene) : scene),
      _clampSampler,
    );
    // With bloom off there is still a sampler to satisfy, and the scene itself
    // is the cheapest texture to hand it — the intensity above is zero, so its
    // contribution is multiplied out.
    _bindTexture(
      pass,
      compositeShader,
      _kBloomTextureSlot,
      bloom ?? scene,
      _clampSampler,
    );
    bindUniformBlock(pass, host, compositeShader, _kCompositeInfoBlock, {
      'params': _compositeParams,
    });
    pass.draw();

    if (!settings.debug.anyEnabled && settings.highlighted.isEmpty) {
      commandBuffer.submit();
      return 0;
    }

    var lines = 0;
    for (final view in views) {
      final fraction = view.viewportFraction;
      final vw = math.max(1, (fraction.width * width).round());
      final vh = math.max(1, (fraction.height * height).round());
      pass.setViewport(
        gpu.Viewport(
          x: (fraction.x * width).round(),
          y: (fraction.y * height).round(),
          width: vw,
          height: vh,
        ),
      );

      if (_encodeDebugLines(
        pass: pass,
        host: host,
        scene: sceneGraph,
        view: view,
        viewProjection: view.camera.viewProjection(vw / vh),
        aspect: vw / vh,
        settings: settings,
      )) {
        lines += debugDraw.lineCount;
      }
    }
    commandBuffer.submit();
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
    final probe = library['MrtProbe'];
    if (probe == null) return 'MRT probe: the bundle has no MrtProbe entry.';

    const size = 4;
    gpu.Texture makeTarget() => gpu.gpuContext.createTexture(
          gpu.StorageMode.devicePrivate,
          size,
          size,
          format: gpu.gpuContext.defaultColorFormat,
          enableRenderTargetUsage: true,
          enableShaderReadUsage: true,
        );

    final first = makeTarget();
    final second = makeTarget();

    try {
      final commandBuffer = gpu.gpuContext.createCommandBuffer();
      final pass = commandBuffer.createRenderPass(
        gpu.RenderTarget(
          colorAttachments: <gpu.ColorAttachment>[
            gpu.ColorAttachment(
              texture: first,
              clearValue: vm.Vector4.zero(),
              storeAction: gpu.StoreAction.store,
            ),
            gpu.ColorAttachment(
              texture: second,
              clearValue: vm.Vector4.zero(),
              storeAction: gpu.StoreAction.store,
            ),
          ],
        ),
      );

      pass.setViewport(
        gpu.Viewport(x: 0, y: 0, width: size, height: size),
      );
      pass.setScissor(gpu.Scissor(x: 0, y: 0, width: size, height: size));
      pass.setPrimitiveType(gpu.PrimitiveType.triangle);
      pass.setCullMode(gpu.CullMode.none);
      pass.setColorBlendEnable(false);
      pass.setColorBlendEnable(false, colorAttachmentIndex: 1);
      pass.setDepthWriteEnable(false);
      pass.setDepthCompareOperation(gpu.CompareFunction.always);

      pass.bindPipeline(
        gpu.gpuContext.createRenderPipeline(fullscreenVertexShader, probe),
      );
      pass.bindVertexBuffer(_fullscreenTriangle, 3);
      pass.bindIndexBuffer(_identityIndices(3), gpu.IndexType.int32, 3);
      pass.draw();
      commandBuffer.submit();

      // asImage plus toByteData is the only readback path available: there is
      // no buffer readback in flutter_gpu at all.
      final a = await first.asImage().toByteData();
      final b = await second.asImage().toByteData();
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
  void _releaseAfterFrame(gpu.Texture texture) {
    _pendingRelease[_frameIndex % _kFramesInFlight].add(texture);
  }

  final List<List<gpu.Texture>> _pendingRelease = List<List<gpu.Texture>>
      .generate(_kFramesInFlight, (_) => <gpu.Texture>[]);

  /// Builds and submits the debug overlay for one view. Returns false when there
  /// was nothing to draw.
  ///
  /// The whole overlay is a single non-indexed `PrimitiveType.line` draw out of
  /// the per-frame host buffer, so switching it on costs one buffer write and one
  /// draw call no matter how much it shows.
  bool _encodeDebugLines({
    required gpu.RenderPass pass,
    required gpu.HostBuffer host,
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
    pass.clearBindings();

    pass.bindPipeline(
      _debugLinePipeline ??= gpu.gpuContext.createRenderPipeline(
        debugLineVertexShader,
        debugLineFragmentShader,
      ),
    );
    pass.setPrimitiveType(gpu.PrimitiveType.line);
    pass.setPolygonMode(gpu.PolygonMode.fill);
    pass.setCullMode(gpu.CullMode.none);
    pass.setColorBlendEnable(false);
    // Drawn on top of the scene: a bounding box that disappears inside the very
    // object it bounds is not much of a diagnostic.
    pass.setDepthWriteEnable(false);
    pass.setDepthCompareOperation(gpu.CompareFunction.always);

    final vertexCount = debugDraw.vertexCount;
    pass.bindVertexBuffer(host.emplace(debugDraw.vertexBytes), vertexCount);
    pass.bindIndexBuffer(
      _identityIndices(vertexCount),
      gpu.IndexType.int32,
      vertexCount,
    );
    bindUniformBlock(pass, host, debugLineVertexShader, _kLineInfoBlock, {
      'view_projection': viewProjection.storage,
    });

    pass.draw();
    developer.Timeline.finishSync();
    return true;
  }

  /// Binds one texture slot, defaulting the sampler to linear-repeat.
  void _bindTexture(
    gpu.RenderPass pass,
    gpu.Shader shader,
    String slot,
    gpu.Texture texture,
    gpu.SamplerOptions? sampler,
  ) {
    pass.bindTexture(
      shader.getUniformSlot(slot),
      texture,
      sampler: sampler ?? _defaultSampler,
    );
  }

  static final gpu.SamplerOptions _defaultSampler = gpu.SamplerOptions(
    minFilter: gpu.MinMagFilter.linear,
    magFilter: gpu.MinMagFilter.linear,
    widthAddressMode: gpu.SamplerAddressMode.repeat,
    heightAddressMode: gpu.SamplerAddressMode.repeat,
  );

  /// A view over the identity index sequence, growing the backing buffer when
  /// the overlay outgrows it.
  gpu.BufferView _identityIndices(int count) {
    if (count > _debugIndexCapacity) {
      var capacity = math.max(_debugIndexCapacity * 2, 1024);
      while (capacity < count) {
        capacity *= 2;
      }
      final indices = Uint32List(capacity);
      for (var i = 0; i < capacity; i++) {
        indices[i] = i;
      }
      _debugIndexBuffer = gpu.gpuContext.createDeviceBufferWithCopy(
        indices.buffer.asByteData(),
      );
      _debugIndexCapacity = capacity;
    }
    return gpu.BufferView(
      _debugIndexBuffer!,
      offsetInBytes: 0,
      lengthInBytes: count * 4,
    );
  }
}
