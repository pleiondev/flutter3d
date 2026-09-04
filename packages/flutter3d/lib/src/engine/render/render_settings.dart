import 'package:vector_math/vector_math.dart' as vm;

import '../scene/scene_node.dart';
import 'auto_exposure.dart';
import 'debug_draw.dart';
import 'shadow_settings.dart';
import 'sky_settings.dart';

// Re-exported so that `render_settings.dart` stays the one import an
// application needs: what moved out is still part of the same vocabulary.
export 'auto_exposure.dart';
export 'frame_result.dart';
export 'shadow_settings.dart';

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

/// Screen-space ambient occlusion.
///
/// What it darkens is the ambient term, and that is why it arrived *after* the
/// hemispheric ambient rather than before: with one grey scalar at 0.06, a
/// correctly applied occlusion took six per cent off the corners of the frame
/// and was invisible. The temptation then is to apply it to everything, which
/// is no longer occlusion but dirt in the corners, and it reads as a mistake
/// under direct light.
///
/// **Off by default, and switching it on changes more than the corners.**
/// Reading the surface buffer turns MSAA off for the whole scene pass — the
/// average of two octahedral normals encodes no normal — so the antialiasing of
/// the entire frame changes with it. That is measured and written down here
/// rather than discovered by a reviewer who blames the occlusion for the edges.
final class AmbientOcclusionSettings {
  const AmbientOcclusionSettings({
    this.enabled = false,
    this.radius = 0.5,
    this.samples = 12,
    this.strength = 0.8,
    this.bias = 0.02,
  });

  final bool enabled;

  /// How far, in world metres, a surface looks for things blocking its sky.
  ///
  /// The one setting that has to suit the scene rather than the renderer: half
  /// a metre is a room, and on a level built in centimetres it is the whole
  /// level.
  final double radius;

  /// Taps per pixel. The shader's loop is bounded at twelve whatever this
  /// says, for the reason `ReflectionSettings.steps` is bounded — a loop a
  /// uniform can lengthen without limit is a hang.
  final int samples;

  /// How dark a fully enclosed corner goes, where 1 is black.
  final double strength;

  /// How far, in metres, the sample origin is lifted off its own surface.
  ///
  /// In metres rather than in window depth on purpose: a bias in depth units is
  /// a different physical distance at every range, so one tuned against a near
  /// wall leaves acne on a far one.
  final double bias;
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

/// Silhouettes of what the walls hide.
///
/// A node whose `layerMask` meets [layerMask] is drawn twice more at the end
/// of the scene pass: once to mark the stencil wherever it is *visible*, and
/// once as a flat colour wherever it fails the depth test and the stencil
/// says no visible part of a marked node is there. The stencil is what keeps
/// the lit half of a half-hidden monster lit — without it, a far limb behind
/// a near one would paint its silhouette over the part the player can see —
/// and it is what the second draw of a second monster is masked by.
///
/// Off by default, because [layerMask] is zero and a mask that meets nothing
/// draws nothing; the dungeon switches it on for the seconds a sensor
/// power-up lasts. The stage draws nothing at all on a device whose
/// `supportsStencil` is false, which is a picture without silhouettes rather
/// than a frame with something wrong in it.
final class XraySettings {
  const XraySettings({this.color, this.layerMask = 0});

  /// Which nodes get a silhouette: those whose `SceneNode.layerMask` shares
  /// a bit with this. Zero is off.
  final int layerMask;

  /// Linear light, before exposure and the tone curve, as every colour in
  /// the HDR target is. Null takes the default, an orange bright enough to
  /// read through a dark corridor without blooming.
  final vm.Vector3? color;

  vm.Vector3 get resolvedColor => color ?? _defaultColor;

  bool get enabled => layerMask != 0;

  static final vm.Vector3 _defaultColor = vm.Vector3(1.0, 0.32, 0.08);
}

final class RenderSettings {
  const RenderSettings({
    this.specular = 1.0,
    this.exposure = defaultExposure,
    this.wireframe = false,
    this.backfaceCulling = true,
    this.debug = const DebugDrawOptions(),
    this.highlighted = const <SceneNode>[],
    this.tonemap = true,
    this.bloom = const BloomSettings(),
    this.look = const LookSettings(),
    this.shadows = const ShadowSettings(),
    this.surfaceBuffer = false,
    this.showSurfaceBuffer = false,
    this.showShadowMap = false,
    this.showStaticShadowMap = false,
    this.showPointShadowDebug = false,
    this.reflections = const ReflectionSettings(),
    this.ambientOcclusion = const AmbientOcclusionSettings(),
    this.fog = const FogSettings(),
    this.sky = const SkySettings(),
    this.anisotropy = 1,
    this.autoExposure = const AutoExposureSettings(),
    this.xray = const XraySettings(),
  }) : assert(anisotropy >= 1, 'anisotropy is a count of taps, one or more');

  final double specular;

  /// Taps a model's texture samplers may take along a foreshortened axis.
  ///
  /// Applied at bind time to every material sampler that is trilinear and
  /// asks for no anisotropy of its own; one — the default — leaves every
  /// sampler as the asset loaded it. Clamped to `GraphicsDevice.maxAnisotropy`
  /// on the way, so sixteen is a safe thing to ask for and a device that
  /// filters isotropically draws the picture it always drew.
  ///
  /// **A setting rather than a property of the asset**, because glTF has no
  /// way to say it: a `sampler` in the file names filters and wrap modes and
  /// nothing about taps, so a model's textures arrive at one and this is
  /// where a game turns them up. A level's brush materials do not come
  /// through here — the bridge hands them `min(8, maxAnisotropy)` when it
  /// builds them, since it knows the device and a brush floor at a grazing
  /// angle is the surface the filter exists for.
  ///
  /// Bilinear samplers are left alone whatever this says: the taps are taken
  /// across the mip chain, and a sampler that blends no levels has nothing
  /// to spread them over. That is also flutter_gpu's rule, which refuses
  /// anisotropy on a nearest filter.
  final int anisotropy;

  /// Linear multiplier applied before tone mapping.
  ///
  /// The default is a demo choice, not a physical constant: with light intensity
  /// at a unitless 1.0 the scene's brightest values land around linear 0.6, so
  /// the tone mapper's shoulder would otherwise go unused and the image would
  /// read as under-exposed. [autoExposure] derives it from the frame instead,
  /// and while that is on this is only where the meter starts from.
  final double exposure;

  /// What [exposure] is when nothing says otherwise — named, because the
  /// renderer reports this as the exposure of a frame it has not drawn yet.
  static const double defaultExposure = 1.6;

  /// Exposure decided by the frame's own brightness — see
  /// [AutoExposureSettings].
  ///
  /// Off by default, and the goldens are why: every one of them is recorded at
  /// [exposure], and a meter that ran unasked would move all of them. On, the
  /// frame gains a small pass that writes the scene's log luminance and a
  /// readback of it, and the composite exposes with what the meter answered a
  /// frame or two ago, adapted at the settings' rate.
  final AutoExposureSettings autoExposure;
  /// Draws the scene's triangles as lines.
  ///
  /// **Two of the three backends decline it**, which is the one thing a caller
  /// has to know before reaching for it. It is a polygon
  /// mode, and OpenGL ES has no `glPolygonMode` — so the WebGL backend and the
  /// software rasteriser both answer false to
  /// `GraphicsDevice.supportsWireframe`, and the engine declines the setting on
  /// their behalf rather than sending a request they would refuse mid-frame.
  /// Only Impeller draws it.
  ///
  /// A declined frame is a solid model and no exception, so the frame says so
  /// instead: [FrameResult.wireframeDeclined] is true exactly when this was
  /// asked for and could not be given. Ask that rather than the picture.
  ///
  /// Making it work everywhere is not a backend's to invent: lines from a
  /// triangle list need an index buffer built for them, which is geometry work
  /// in this package rather than a translation in a backend.
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

  /// Grading, vignette, grain and dispersion, applied inside the composite.
  /// Neutral by default — see [LookSettings].
  final LookSettings look;

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

  /// Darkens the ambient term where a surface cannot see the sky.
  final AmbientOcclusionSettings ambientOcclusion;

  final FogSettings fog;

  /// What is behind everything, when there is anything.
  ///
  /// Off by default: a sky changes every pixel a frame did not otherwise draw,
  /// and sixty golden images are recorded against there being none.
  final SkySettings sky;

  /// Silhouettes of the nodes on a layer, drawn where something hides them.
  final XraySettings xray;

  /// Composites the shadow map instead of the scene.
  ///
  /// A shadow map is the one buffer in the renderer that nothing has ever
  /// shown. It is about to hold a cube atlas, and an atlas whose contents
  /// nobody can look at is an atlas whose layout nobody can check.
  ///
  /// Shows the cube atlas the movers are drawn into, or the directional map
  /// when there is no cube. For the other cube atlas see [showStaticShadowMap].
  final bool showShadowMap;

  /// Composites the **static** cube atlas instead of the scene.
  ///
  /// A separate switch rather than a mode of [showShadowMap], because the whole
  /// value of these is that each answers one question. There are two cube
  /// atlases — the movers, redrawn every frame, and the things that never move,
  /// drawn once at load — and the lighting shader samples both and keeps the
  /// nearer occluder. Showing only the first is how "the atlas is right" got
  /// said about a backend whose second atlas nobody had looked at.
  final bool showStaticShadowMap;

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
  @Deprecated(
    'A setting cannot see the frame, so this can only ever be a model of the '
    'built-in passes. Ask the compiled graph instead: '
    'CompiledFrameGraph.isConsumed(FrameResourceIds.surfaceBuffer), which is '
    'what the scene node does. Scheduled for removal.',
  )
  bool get needsSurfaceBuffer =>
      surfaceBuffer ||
      showSurfaceBuffer ||
      showPointShadowDebug ||
      reflections.enabled;

  /// This one with some fields replaced.
  ///
  /// **Every field, and that is the whole point of the test beside it.** Six
  /// were missing here — `surfaceBuffer`, `showSurfaceBuffer`, `showShadowMap`,
  /// `showPointShadowDebug`, `reflections` and `fog` — so calling `copyWith` to
  /// change the exposure silently switched reflections and fog back off and
  /// turned three debug views off with them. A `copyWith` that drops a field is
  /// a peculiarly quiet bug: it does exactly what was asked *and* something
  /// else, and the something else looks like the feature never worked.
  ///
  /// `test/render_settings_test.dart` round-trips every field through an
  /// argument-less call, which is what catches the next one somebody adds.
  RenderSettings copyWith({
    double? specular,
    double? exposure,
    bool? wireframe,
    bool? backfaceCulling,
    DebugDrawOptions? debug,
    List<SceneNode>? highlighted,
    bool? tonemap,
    BloomSettings? bloom,
    LookSettings? look,
    ShadowSettings? shadows,
    bool? surfaceBuffer,
    bool? showSurfaceBuffer,
    bool? showShadowMap,
    bool? showStaticShadowMap,
    bool? showPointShadowDebug,
    ReflectionSettings? reflections,
    AmbientOcclusionSettings? ambientOcclusion,
    FogSettings? fog,
    SkySettings? sky,
    int? anisotropy,
    AutoExposureSettings? autoExposure,
    XraySettings? xray,
  }) => RenderSettings(
    specular: specular ?? this.specular,
    exposure: exposure ?? this.exposure,
    wireframe: wireframe ?? this.wireframe,
    backfaceCulling: backfaceCulling ?? this.backfaceCulling,
    debug: debug ?? this.debug,
    highlighted: highlighted ?? this.highlighted,
    tonemap: tonemap ?? this.tonemap,
    bloom: bloom ?? this.bloom,
    look: look ?? this.look,
    shadows: shadows ?? this.shadows,
    surfaceBuffer: surfaceBuffer ?? this.surfaceBuffer,
    showSurfaceBuffer: showSurfaceBuffer ?? this.showSurfaceBuffer,
    showShadowMap: showShadowMap ?? this.showShadowMap,
    showStaticShadowMap: showStaticShadowMap ?? this.showStaticShadowMap,
    showPointShadowDebug: showPointShadowDebug ?? this.showPointShadowDebug,
    reflections: reflections ?? this.reflections,
    ambientOcclusion: ambientOcclusion ?? this.ambientOcclusion,
    fog: fog ?? this.fog,
    sky: sky ?? this.sky,
    anisotropy: anisotropy ?? this.anisotropy,
    autoExposure: autoExposure ?? this.autoExposure,
    xray: xray ?? this.xray,
  );
}

/// How much of the frame's light spills into a glow.
/// The look put on the frame after it has been tone mapped.
///
/// **Everything here defaults to doing nothing, exactly.** Not nearly nothing:
/// a vignette of zero multiplies by one and grain of zero adds zero, so a scene
/// that asks for none of it composites to the same bytes it did before this
/// existed. Thirty goldens depend on that being exact, and the composite pass
/// already keeps the same promise for ambient occlusion.
///
/// Applied in the composite rather than as passes of their own, which is the
/// trade this makes against a chain of full-screen effects: one pass, one read
/// of the scene, and no intermediate target — at the cost that the order is
/// fixed. The order is the one a camera imposes and is not arbitrary: the lens
/// disperses colour *before* the sensor sees it, so chromatic aberration reads
/// the scene at offset coordinates; grading is a decision about a displayable
/// image and so follows the tone map; grain and vignette are the film and the
/// barrel, and come last.
final class LookSettings {
  const LookSettings({
    this.contrast = 1.0,
    this.saturation = 1.0,
    this.temperature = 0.0,
    this.vignette = 0.0,
    this.vignetteRoundness = 1.0,
    this.grain = 0.0,
    this.chromaticAberration = 0.0,
  });

  /// Pivoted about mid grey, so raising it does not also raise exposure.
  final double contrast;

  /// Zero is luminance alone; above one pushes past the original chroma.
  final double saturation;

  /// Warm above zero, cool below, in the range −1 to 1. A gain on red against
  /// blue rather than a true white-balance conversion: this is a look control,
  /// and a scene lit at the wrong colour temperature should be fixed at the
  /// light rather than here.
  final double temperature;

  /// How far the corners are pulled down, 0 to 1.
  final double vignette;

  /// 1 keeps the falloff circular whatever the aspect; 0 lets it follow the
  /// frame and reach the short edges sooner.
  final double vignetteRoundness;

  /// Amplitude of per-pixel noise, 0 to about 0.1.
  ///
  /// **Static, not animated**, and that is a decision rather than an omission:
  /// grain that moves needs the frame number in the uniform, and a shader that
  /// reads a frame counter is a shader whose golden differs every run. If
  /// moving grain is wanted it needs a way to be pinned for a test first.
  final double grain;

  /// Radial colour dispersion, in screen widths at the corner. 0.005 is
  /// visible without reading as a fault.
  final double chromaticAberration;

  /// Whether any of this changes the picture at all.
  ///
  /// Read by the renderer to skip packing the second uniform, and by tests to
  /// say what "off" means in one place rather than seven.
  bool get isNeutral =>
      contrast == 1.0 &&
      saturation == 1.0 &&
      temperature == 0.0 &&
      vignette == 0.0 &&
      grain == 0.0 &&
      chromaticAberration == 0.0;

  LookSettings copyWith({
    double? contrast,
    double? saturation,
    double? temperature,
    double? vignette,
    double? vignetteRoundness,
    double? grain,
    double? chromaticAberration,
  }) => LookSettings(
    contrast: contrast ?? this.contrast,
    saturation: saturation ?? this.saturation,
    temperature: temperature ?? this.temperature,
    vignette: vignette ?? this.vignette,
    vignetteRoundness: vignetteRoundness ?? this.vignetteRoundness,
    grain: grain ?? this.grain,
    chromaticAberration: chromaticAberration ?? this.chromaticAberration,
  );
}

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
  /// this engine builds no mip levels at all.
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
  }) => BloomSettings(
    enabled: enabled ?? this.enabled,
    threshold: threshold ?? this.threshold,
    knee: knee ?? this.knee,
    intensity: intensity ?? this.intensity,
    levels: levels ?? this.levels,
    filterRadius: filterRadius ?? this.filterRadius,
  );
}
