import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../geometry/mesh_geometry.dart';
import '../scene/camera_node.dart';
import '../scene/light_buffer.dart';
import '../scene/light_node.dart';
import '../scene/mesh_node.dart';
import '../scene/projection.dart';
import '../scene/scene.dart';
import 'composite_mix.dart';
import 'debug_draw.dart';
import 'debug_draw_gizmos.dart';
import 'frame_graph.dart';
import 'frame_plan.dart';
import 'frame_resources.dart';
import 'lighting_model.dart';
import 'material.dart';
import 'pass_contributor.dart';
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
export 'render_settings.dart';

part 'renderer_shadow_pass.dart';
part 'renderer_scene_pass.dart';
part 'renderer_mesh_encode.dart';
part 'renderer_post_pass.dart';
part 'renderer_sky_pass.dart';
part 'renderer_resources.dart';
part 'renderer_frame_nodes.dart';

/// Uniform-block names as seen by shader reflection.
///
/// A backend may reflect a uniform block under its struct TYPE name, so
/// `uniform FrameInfo { ... } frame_info;` is looked up as `FrameInfo`. Using
/// the variable name instead is not an error at bind time — it just reflects as
/// a missing block, which surfaces much later as "no uniform block named ...".
const String _kReflectionInfoBlock = 'ReflectionInfo';
const String _kSsaoInfoBlock = 'SsaoInfo';
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
const String _kEnvironmentTextureSlot = 'environment_texture';
const String _kShadowTextureSlot = 'shadow_texture';
const String _kPostSourceSlot = 'source_texture';
const String _kSceneTextureSlot = 'scene_texture';
const String _kBloomTextureSlot = 'bloom_texture';
const String _kAoTextureSlot = 'ao_texture';

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
    required this.debugLineFragmentShader,
    required this.fullscreenVertexShader,
    required this.bloomThresholdShader,
    required this.bloomDownsampleShader,
    required this.bloomUpsampleShader,
    required this.compositeShader,
    required this.reflectionShader,
    required this.ssaoShader,
    required TextureHandle fallbackAlbedo,
    required TextureHandle fallbackNormal,
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
       _fallbackNormal = fallbackNormal;

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

  T addNode<T extends RenderNode>(T node) => nodes.add(node);

  bool removeContributor(PassContributor c) => contributors.remove(c);

  bool removeNode(RenderNode node) => nodes.remove(node);

  final ShaderHandle vertexShader;

  /// The skinned vertex stage. A separate shader because joints and weights are
  /// vertex attributes, and the layout is taken from the `in`
  /// declarations — so a skinned mesh cannot share a shader with a static one
  /// however similar the body is.
  final ShaderHandle skinnedVertexShader;

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

  /// The screen-space reflection pass.
  final ShaderHandle reflectionShader;

  /// The ambient occlusion pass.
  final ShaderHandle ssaoShader;

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
  /// What it deliberately does not touch: the HDR, LDR and surface-buffer
  /// render targets. They are reallocated together in [_ensureTargets]
  /// whenever the window resizes, which is the one place their lifetime is
  /// already managed — and that place now releases the ones it replaces.
  /// Folding them in here would duplicate that bookkeeping for a case — a
  /// renderer being discarded rather than resized — that drops every reference
  /// to the `Renderer` itself anyway.
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
    targetPool.trim();

    // Released rather than merely dropped, and nulled so a second call is the
    // no-op this method promises to be.
    for (final texture in <TextureHandle?>[
      _fallbackAlbedo,
      _fallbackNormal,
      _fallbackEnvironment,
      _shadowMap,
      _cubeShadow,
      _cubeShadowStatic,
    ]) {
      if (texture != null) device.releaseTexture(texture);
    }
    _fallbackAlbedo = null;
    _fallbackNormal = null;
    _fallbackEnvironment = null;
    _shadowMap = null;
    _cubeShadow = null;
    _cubeShadowStatic = null;
    _cubeShadowTile = 0;

    final indices = _debugIndexBuffer;
    if (indices != null) device.releaseGeometry(indices);
    _debugIndexBuffer = null;

    _renderList.materialIds.clear();
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
  final List<TextureHandle> _ldrFrames = <TextureHandle>[];
  final List<TextureHandle> _ldrFree = <TextureHandle>[];
  TextureHandle? _ldrCurrent;

  /// The frame currently being drawn into.
  TextureHandle? get _ldrColor => _ldrCurrent;
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

  // `hdrFormat` is declared in `renderer_resources.dart`, alongside the
  // caches that key off it.

  PipelineHandle? _shadowPipeline;
  PipelineHandle? _skinnedShadowPipeline;
  PipelineHandle? _bloomUpsamplePipeline;
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
  final Float32List _shadowCascades = Float32List(4);

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
  final Float32List _compositeAoTexel = Float32List(4);

  /// The look, packed for the composite's uniform block.
  ///
  /// Two vectors rather than one because std140 pads a `vec3` to sixteen bytes
  /// anyway, so seven floats cost the same as eight and the split reads better
  /// on the shader's side: grading in one, the lens and the film in the other.
  final Float32List _compositeLook = Float32List(4);
  final Float32List _compositeLookMore = Float32List(4);

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
      debugLineVertexShader: require('DebugLineVertex'),
      debugLineFragmentShader: require('DebugLine'),
      fullscreenVertexShader: require('FullscreenVertex'),
      bloomThresholdShader: require('BloomThreshold'),
      bloomDownsampleShader: require('BloomDownsample'),
      bloomUpsampleShader: require('BloomUpsample'),
      compositeShader: require('Composite'),
      reflectionShader: require('Reflections'),
      ssaoShader: require('Ssao'),
      fallbackAlbedo: fallbackAlbedo ?? SolidColorTexture.white.upload(device),
      fallbackNormal:
          fallbackNormal ?? SolidColorTexture.flatNormal.upload(device),
      msaaEnabled: device.supportsOffscreenMsaa,
    ).._shaders = library;
  }

  // `_fragmentShaderFor` and `_pipelineFor` are declared in
  // `renderer_resources.dart`, next to the caches they read and fill.

  void _ensureTargets(int width, int height) {
    if (width == _targetWidth && height == _targetHeight) return;

    // **Everything below is about to be replaced by assigning over a field.**
    // Where the collector frees a texture that is the whole story; where it
    // does not — WebGL2 — dropping the handle leaks the driver's object, and
    // this method is what a person resizing a window calls over and over. Sent
    // through the frames-in-flight ring rather than freed here, because the
    // frame these were drawn with may still be reading them.
    _destroyAfterFrame(_hdrColor);
    _destroyAfterFrame(_hdrMsaa);
    _destroyAfterFrame(_surfaceColor);
    _destroyAfterFrame(_surfaceMsaa);
    _destroyAfterFrame(_reflectionColor);
    _destroyAfterFrame(_depthStencil);
    _destroyAfterFrame(_depthStencilSingle);
    // The composited frames are the one set with an owner outside this class:
    // `Texture.asImage` hands one to the widget tree, and the compositor may
    // still be holding the last of them. The ring is what covers that, and it
    // is the same ring the pool's own releases wait in.
    for (final frame in _ldrFrames) {
      _destroyAfterFrame(frame);
    }

    // From the device, not a literal. Four is what these goldens were recorded
    // with and what both current backends answer; the engine no longer decides
    // it on their behalf.
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
    _makeLdrFrame = () =>
        make(StorageMode.devicePrivate, device.defaultColorFormat);

    // The surface buffer: world-space normal and depth, for whatever runs after
    // the scene. Allocated with the rest rather than on demand, because a
    // resize is the only moment any of this is allowed to be reallocated and a
    // buffer that appears mid-session would be the one that is the wrong size.
    _surfaceColor = make(StorageMode.devicePrivate, hdrFormat);
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
    final tile = settings.cubeResolution.clamp(
      ShadowSettings.minCubeTile,
      ShadowSettings.maxCubeTile,
    );
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
    // Two atlases at 75 MB each with the default tile, replaced whenever a
    // setting the pass reads changes. Dropping them is a free on one backend
    // and a leak on another — see [_destroyAfterFrame].
    _destroyAfterFrame(_cubeShadowStatic);
    _destroyAfterFrame(_cubeShadow);
    _cubeShadowStatic = device.createTexture(spec);
    _cubeShadow = device.createTexture(spec);
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

  final Float32List _cubeFaceMatrices = Float32List(16 * 6 * kShadowedLights);

  /// What a surface facing up, and one facing down, receive from the
  /// environment. Recomputed once a frame — see [_updateAmbient].
  final Float32List _ambientSky = Float32List(4);
  final Float32List _ambientGround = Float32List(4);

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
  }

  /// Per atlas row: xyz the direction a spot aims, w the tangent of half its
  /// frustum — or w negative when the row belongs to a point light.
  ///
  /// Separate from [_cubeLightData] rather than widening it, because that array
  /// is uploaded to the shader as `lights[]` and this is not: the shading reads
  /// a spot's tile through the matrix in `faces[]`, which already carries the
  /// aim. This is what the *pass* needs in order to build that matrix.
  final Float32List _cubeLightAim = Float32List(4 * kShadowedLights);
  final Float32List _cubeLightData = Float32List(4 * kShadowedLights);

  /// One vec4 per light the shading knows about; x is its atlas row or -1.
  final Float32List _shadowSlots = Float32List(4 * LightBuffer.maxLights);

  final Float32List _pointShadowParams = Float32List(4);
  final Float32List _pointShadowParams2 = Float32List(4);

  /// x: whether this backend stores the cube atlas bottom-up. See surface.glsl.
  final Float32List _pointShadowParams3 = Float32List(4);

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
  void _collectShadowCandidates(Scene scene, List<RenderView> views) {
    _shadowCandidates.clear();
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
      _shadowCandidates.add(
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
      final spotTanHalf = _cubeLightAim[slot * 4 + 3];
      final isSpot = spotTanHalf > 0.0;
      _shadowAim.setValues(
        _cubeLightAim[slot * 4],
        _cubeLightAim[slot * 4 + 1],
        _cubeLightAim[slot * 4 + 2],
      );

      // The light's own placement is part of every one of its faces: move the
      // light and every face of that row draws something different.
      final base = isSpot
          ? _bakeKeyFor(_cubePosition, range, _shadowAim, spotTanHalf)
          : _bakeKeyFor(_cubePosition, range);
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
      ..addNode(scene);

    for (final node in nodes.of(FramePhase.overlay)) {
      graph.addNode(node);
    }
    if (s.reflections.enabled) {
      graph.addNode(_ReflectionsNode(this, view));
    }
    // Before bloom, because the composite reads both and the registration order
    // is the version chain. Registered whether or not it is switched on, for
    // the reason bloom is: a name has to be known for a read of it to compile,
    // and the composite reads the occlusion.
    graph.addNode(_SsaoNode(this, view, s));
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

    // After the composite, which is the whole of what [FramePhase.present]
    // means: registration order is the version chain, so a node here reads the
    // version the composite wrote and produces the next one. Nothing about the
    // node changes between the two phases — it is where it is registered that
    // decides what it sees.
    for (final node in nodes.of(FramePhase.present)) {
      graph.addNode(node);
    }

    return graph.compile(
      outputs: <ResourceId>[
        FrameResourceIds.frame,
        // An application that asked for the surface buffer is a consumer no node
        // declares, so it is a frame output. Without this, `surfaceBuffer` on its
        // own would leave the buffer unread, the scene would not attach it, and
        // the application would read whatever the texture held last.
        if (s.surfaceBuffer) FrameResourceIds.surfaceBuffer,
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
  PipelineHandle? _cubeShadowResetPipeline;

  /// Skinned casters whose pose has already been evaluated in the pass now
  /// being encoded.
  ///
  /// Held on the renderer rather than allocated per pass so that a frame with
  /// no skinned casters — which is most frames in most scenes — costs one
  /// `clear` of an empty set. Identity is the right key: the same node twice
  /// means the same world matrix and the same joints, and two nodes sharing one
  /// skeleton at different transforms genuinely need two evaluations.
  final Set<MeshNode> _cubeShadowPosed = <MeshNode>{};

  /// Whether each atlas has been cleared since it was allocated.
  bool _cubeShadowCleared = false;
  bool _cubeShadowStaticCleared = false;
  TextureHandle? _cubeShadow;
  TextureHandle? _cubeShadowStatic;
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

  int _cubeShadowTile = 0;
  final vm.Matrix4 _cubeMatrix = vm.Matrix4.identity();

  /// [_cubeMatrix] in the backend's clip space, for drawing a face with.
  final vm.Matrix4 _cubeDrawMatrix = vm.Matrix4.identity();
  final Float32List _cubeLight = Float32List(4);

  /// How far this camera sees, for dividing between cascades.
  ///
  /// An orthographic camera has no far distance worth splitting by, and a
  /// camera with a far plane at infinity would put the first split at infinity
  /// too, so both fall back to something a level-sized scene can use.
  static double _cameraFar(CameraNode camera) {
    final projection = camera.projection;
    if (projection is PerspectiveProjection && projection.far.isFinite) {
      return math.max(10.0, projection.far);
    }
    return 200.0;
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
  /// The triangle every full-screen pass is drawn with, wound for this backend.
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
      pass.bindTexture(draw.fragment, slot, texture, sampler: draw.sampler);
    });
    draw.uniforms.forEach((block, members) {
      pass.bindUniformBlock(draw.fragment, block, members);
    });

    pass.draw();
    pass.submit();
  }

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
      if (_passLights.count == 0) _passLights.useDefaultLight();
      passLights = _passLights;
      passShadowSlots = _noShadowSlots;
    }

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
        lights: passLights,
        shadowSlots: passShadowSlots,
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
  /// The camera's view-projection, in the clip space this backend uses.
  ///
  /// Cameras build for [DepthRange.zeroToOne], which is what Metal, Vulkan and
  /// Vulkan want. A backend on OpenGL conventions gets the same matrix with
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
    if (lights.count == 0) lights.useDefaultLight();
    _lightsScene = scene;
    final lightOverflowCount = lights.overflow;
    final shadowCaster = _firstDirectionalIndex();

    // Zeroed by the frame rather than by the pass, because the pass may not
    // run. `_renderShadowMap` cleared these on its way out of every early
    // return; a node the graph culls has no way out to clear them on, and last
    // frame's strength left standing would shadow a scene whose shadows were
    // just switched off.
    _shadowParams[3] = 0.0;
    _shadowCasters = 0;
    // One cascade until a pass says otherwise, so a shader reading these
    // between frames sees the arrangement it has always seen.
    _shadowCascades[2] = 1.0;

    // Which point lights get a row of the atlas, decided by relevance rather
    // than by the order they happen to sit in the scene list. Four is now a
    // limit on how many can be shadowed *at once*, not on how many a level may
    // contain: a fifth torch takes a row as soon as it matters more than one of
    // the four, and gives it back when it stops.
    //
    // Every row is decided before any of the atlas is drawn, because one pass
    // draws all of them: a pass per light would clear the rows already there.
    _updateAmbient(scene, settings);

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

      final spot = owner.type == LightType.spot;
      // The frustum this row is drawn and read through. A cube face is ninety
      // degrees, so `tan(45°)` is exactly one; a cone opens to twice its outer
      // angle, and the margin is what keeps the very edge of the cone inside
      // the tile. Without it the shader's own `abs(ndc) > 1` bail — written to
      // catch a fragment outside the face — fires along the rim and quietly
      // returns "lit", which reads as the shadow being trimmed to a slightly
      // narrower cone than the light.
      final tanHalf = spot
          ? math.tan(
              (owner.outerConeAngle * _kSpotFrustumMargin).clamp(0.02, 1.5),
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

      // Which atlas row this light's shader index should read.
      _shadowSlots[index * 4] = row.toDouble();
      // Which shape it is: 0 a cube, 1 a single cone-shaped tile. The shader
      // needs this before it can pick a face, and it cannot be inferred from
      // the tangent beside it — a spot opening to exactly forty-five degrees
      // has a tangent of one, the same as every cube face.
      _shadowSlots[index * 4 + 1] = spot ? 1.0 : 0.0;
      // The tangent again, this time for the filter rather than the pass. It
      // has to be *written* rather than left at the −1 the clear above puts
      // there, because the penumbra estimate divides by it. Written next to the
      // row and not in a branch: the two are read together, and a slot with a
      // row but no angle is a black light.
      //
      // The depth bias is deliberately **not** scaled by this, and the reason
      // is a measurement rather than a preference. The argument for scaling it
      // is sound on paper — a cone's texel covers less world, so a bias fixed
      // in metres is relatively larger and should lift the shadow off its
      // caster's foot. It was probed: a post standing on a floor, lit once as a
      // point and once as a cone of 0.6 and then of 0.22 radians, put its
      // shadow in the same cells every time, contact included. A separate
      // `spotBias` would have been a knob nothing turns.
      _shadowSlots[index * 4 + 2] = tanHalf;
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
      // The first view's camera, for splitting the cascades by where somebody
      // is actually looking. A second viewport is a second set of splits and
      // one map cannot serve both; the primary view wins, which is the same
      // answer reflections give.
      camera: ordered.isEmpty ? null : ordered.first.camera,
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
    final resources =
        FrameResources(
            source: _DeferredTextureSource(this),
            graph: frameGraph,
            frameWidth: width,
            frameHeight: height,
          )
          // Half the frame, in the same HDR format, which is what the bloom chain's
          // top level has always been.
          // Not const any more: the format comes from the device, which is the
          // point — a description of a resource cannot be a compile-time constant
          // once it depends on which backend is drawing.
          ..declare(
            ResourceDesc(
              id: FrameResourceIds.bloom,
              format: hdrFormat,
              size: const FrameFraction(2),
            ),
          )
          // Half again, and the same format for the same reason: HDR is the one
          // format every backend here is known to render into. A single channel
          // would do — the pass writes occlusion four times over — but "known to
          // work on three backends" beats "three quarters smaller" for a target
          // that is a quarter of the frame to begin with.
          ..declare(
            ResourceDesc(
              id: FrameResourceIds.ao,
              format: hdrFormat,
              size: const FrameFraction(2),
            ),
          );

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
            // Only for a node that asked for it. This convenience used to hand
            // the scene colour to every node in the frame, including the shadow
            // passes that run before one exists and never wanted it — a read
            // the graph was never told about, ordered against nothing. It was
            // invisible until an undeclared read became an error.
            //
            // Still `tryTexture` for the nodes that did declare it: the scene
            // runs first and a node drawing over the world has to cope with
            // there being nothing yet. The view model returns early.
            sceneColor:
                frameGraph.readVersionOf(i, FrameResourceIds.hdrColour) == null
                ? null
                : resources.tryTexture(FrameResourceIds.hdrColour),
          ),
        );
        resources.endNode(i);
      }
    } catch (_) {
      // Only on the way out. On the ordinary path every version has already
      // retired at the node that last used it, and releasing again from here
      // would hand one texture back twice.
      resources.releaseAll();

      // **And the counter has to move, or the deferral this frame just relied
      // on is a frame that never happened.** Releases go into slot
      // `_frameIndex % 3` and are retired at the top of frame N + 3; leaving
      // the counter where it is means the very next `render` drains the slot
      // these were just put in, handing pooled targets back with no deferral
      // at all — which is exactly the failure the ring exists to prevent, and
      // it happens on the path where a frame is *already* going wrong. The
      // comment beside the increment below explains why one frame is not
      // enough; zero is worse.
      _frameIndex++;
      rethrow;
    }

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
    // The frame is encoded and submitted: everything it released is in this
    // slot, and the next two frames must not touch it.
    _frameIndex++;

    // And the picture goes back into rotation when the work that read it is
    // done — not a fixed number of frames later, which is a guess this engine
    // got wrong three times.
    final drawnInto = _ldrCurrent;
    if (drawnInto != null) {
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
    frameClock.stop();
    developer.Timeline.finishSync();

    return FrameResult(
      frame: frame,
      // Asked for and not given. Computed here rather than plumbed out of the
      // scene pass, because it is a fact about the settings and the device
      // rather than about anything that happened during the frame.
      wireframeDeclined: settings.wireframe && !device.supportsWireframe,
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

  final Float32List _ssaoParams = Float32List(4);
  final Float32List _ssaoScreen = Float32List(4);

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
        indices.buffer.asByteData(),
        GeometryUsage.indices,
      );
      _debugIndexCapacity = capacity;
    }
    return _debugIndexBuffer!.slice(length: count * 4);
  }
}
