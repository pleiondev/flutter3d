import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
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

/// Screen-space reflections.
///
/// Off by default: it costs a full-screen pass and the surface buffer that
/// feeds it, and a level lit by torches in a stone corridor gains less from it
/// than a wet floor would.
///
/// **Two things were wrong with the march for as long as nothing recorded a
/// frame of it**, which is what the front page advertising a feature no picture
/// covers buys. It turned clip space into a texture coordinate the opposite way
/// from every other lookup in the engine and against an unadjusted matrix, so
/// on the two backends whose row zero is at the top it read the surface buffer
/// mirrored about the middle of the frame and found nothing to do with the ray.
/// And it compared [thickness] in window depth, which is not a distance. Both
/// are covered now by `flutter3d/test/reflections_test.dart` and by the
/// `screen-space-reflections` golden.
final class ReflectionSettings {
  const ReflectionSettings({
    this.enabled = false,
    this.steps = 24,
    this.stride = 0.18,
    this.thickness = 0.25,
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

  /// How thick a surface is assumed to be, in world metres. Without an upper
  /// bound on how far behind a surface a ray may pass and still count as
  /// hitting it, every distant wall a ray crosses in front of is a hit.
  ///
  /// **In metres, and it used to be in window depth.** That was the bug that
  /// kept the whole effect off: window depth is not a distance, so 0.006 of it
  /// was a few centimetres up against the near plane and several metres a room
  /// away, and one value could not be both a surface a stride could land in
  /// and a wall a ray could pass. It reads as "the reflection does not work",
  /// which is what it was called for as long as it stood.
  ///
  /// A little over [stride] on purpose: a ray whose step is longer than the
  /// surface is thick straddles it and finds nothing.
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
/// rather than discovered by a reviewer who blames the occlusion for the edges,
/// and it is why the one frame that turns this on is a scene of its own rather
/// than a flag added to an existing one.
///
/// **One backend drew it in a check; the other two only proved it links, and
/// that lasted long enough to hide a real defect.** The software rasteriser's
/// `flutter3d/test/ssao_test.dart` was the only place in the tree where the
/// occlusion was compared against a picture, and even there the two rows it
/// compared had been read off a frame the pass was drawing upside down: it
/// turned clip space into a texture coordinate the opposite way from every
/// other lookup in the engine, so each pixel's occlusion was computed for the
/// pixel mirrored about the middle of the frame. What Impeller and WebGL had
/// was that the shader compiles into the bundle and that
/// `('FullscreenVertex', 'Ssao')` links, which says nothing about what it
/// darkens.
///
/// The `ambient-occlusion-corner` golden closes that: one frame, recorded on
/// three backends, of a corner this pass has something to darken.
final class AmbientOcclusionSettings {
  const AmbientOcclusionSettings({
    this.enabled = false,
    this.radius = 0.5,
    this.samples = 12,
    this.strength = 0.8,
    this.bias = 0.02,
    this.blurTaps = 0,
    this.blurDepthFalloff = 0.1,
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

  /// Taps to each side in the depth-aware blur over the occlusion buffer,
  /// 0 for no blur — `gfx-32n`. Bounded at eight whatever this says.
  ///
  /// **The composite's own 2x2 is not this, and widening it would not do.**
  /// That average exists to cancel the kernel rotation this pass applies by
  /// the parity of the pixel, and it is sized to that artefact rather than
  /// tuned for quality — widen it and the contact shadows smear. So the
  /// smoothing has to be a pass of its own, and this is how many taps it
  /// takes. Twelve is where a flat wall stops showing the sampling pattern.
  ///
  /// Off by default. A blur is a second full-screen pass over a signal that
  /// is already off by default, so nothing pays for it until two things are
  /// switched on.
  final int blurTaps;

  /// How much difference in depth, in world metres, halves a tap's weight in
  /// that blur.
  ///
  /// The number that decides whether occlusion bleeds past a silhouette. Too
  /// large and the dark of a corner spreads out over whatever is in front of
  /// it, which is the halo that makes people switch ambient occlusion off;
  /// too small and a curved surface loses the smoothing the blur is for,
  /// because its own depth changes faster than the falloff allows.
  final double blurDepthFalloff;

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

/// Scene-wide shading knobs that are not per-material.
///
/// **One value passed to `Renderer.render`, and nothing here is state.** A
/// caller builds the settings for a frame and hands them over; the renderer
/// keeps no copy of them, which is what lets a debug view be switched on for
/// one frame and off for the next without anything having to be switched back.
/// What does cross a frame boundary is measured rather than remembered from
/// here — the exposure meter, and what it answers is [autoExposure]'s to
/// explain. [copyWith] is how a frame is derived
/// from the last one — and every field belongs in it, which
/// `test/render_settings_test.dart` is there to insist on, having caught seven
/// that did not.
///
/// That first line used to sit at the top of the file, above
/// [ReflectionSettings] and separated from this class by four others — so the
/// most-used type in the public API had no doc comment at all, and the summary
/// written for it introduced something else.
final class RenderSettings {
  const RenderSettings({
    this.specular = 1.0,
    this.exposure = defaultExposure,
    this.wireframe = false,
    this.backfaceCulling = true,
    this.debug = const DebugDrawOptions(),
    this.highlighted = const <SceneNode>[],
    this.tonemap = true,
    this.tonemapCurve = TonemapCurve.neutral,
    this.antiAlias = const AntiAliasSettings(),
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
    this.lightFadeBand = 0.0,
    this.autoExposure = const AutoExposureSettings(),
    this.xray = const XraySettings(),
    this.disabledPasses = const <String>{},
  }) : assert(anisotropy >= 1, 'anisotropy is a count of taps, one or more'),
       assert(lightFadeBand >= 0.0, 'a fade band is a width, not a direction');

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

  /// How wide a ramp sits at the edge of a draw's own light list — `gfx-05n`.
  ///
  /// A scene with more lights than the shader's eight slots picks the eight
  /// that reach each object, and that choice changes as the camera walks: the
  /// light leaving the list was contributing whatever the ranking said it was,
  /// and the next frame it contributes nothing. That is a pop, and it belongs
  /// to the hard cut-off rather than to any fault in the ranking.
  ///
  /// This is the width of the ramp that replaces the cut-off, as a fraction of
  /// the strongest score the selection rejected: `0.5` fades a light in over
  /// the range where it is between one and one and a half times as relevant as
  /// the best light left out. A light about to be swapped out is then already
  /// near nothing, and the swap has nothing to show.
  ///
  /// **Nought, the default, is the hard edge this engine has always had.**
  /// Not approximately — a band of nought scales nothing and packs the same
  /// bytes, which is what lets the feature ship without moving a recorded
  /// frame on the three backends that cannot be re-recorded here. A wider band
  /// costs brightness: every light near the water line is dimmer than the
  /// shader would have made it, so this trades a little light for no jump.
  ///
  /// A scene whose lights all fit ignores this entirely: with nothing
  /// rejected there is no water line and nothing to fade.
  final double lightFadeBand;

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

  /// Which curve [tonemap] applies — `gfx-17n`'s own row.
  ///
  /// [TonemapCurve.neutral] by default, which is what every golden in this
  /// repository was recorded with and what a glTF asset's author saw in a
  /// reference viewer. The other three are a look a game asks for, not a
  /// default anybody inherits.
  final TonemapCurve tonemapCurve;

  /// Edges smoothed after the composite — see [AntiAliasSettings].
  final AntiAliasSettings antiAlias;

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

  /// Frame-graph nodes to leave out of this frame, by name — `gfx-37n`.
  ///
  /// The name is the node's own [FrameGraphNode.name], exactly as
  /// `FrameResult.passes` already reports it, which is what makes this
  /// addressable at all: an application can list what ran, hand a name back,
  /// and get a frame without it.
  ///
  /// **Data rather than a predicate, deliberately.** A `bool Function(String)`
  /// would be one character shorter at the call site and would cost the rest
  /// of this class: every pixel test in this repository is driven from a
  /// `RenderSettings`, and a frame with a closure applied is a frame no golden
  /// can describe. A set can also be written into a project file, put in a bug
  /// report, and diffed to see what an editor changed; and a name no node
  /// carries is rejected at compile with the name in the message, which a
  /// predicate matching nothing cannot be told apart from a misspelling.
  ///
  /// **What happens to a reader of a suppressed node is already decided**, and
  /// three of the four answers needed no new code. An optional read comes back
  /// null and the reader degrades — that is how the composite already treats
  /// bloom and the occlusion. A hard read cannot be satisfied, so the reader is
  /// culled with it, transitively, without an error. A suppressed *link* in a
  /// read-modify-write chain is free: it consumes no version, so the next pass
  /// binds the version before it, which is what "skip this step and keep
  /// everything after it" has to mean.
  ///
  /// The fourth is the sole producer of something the frame asked for, and four
  /// names are refused rather than honoured, each for its own reason:
  /// `composite` and `scene`, because the frame has no picture without them and
  /// the fallback would hand back a stale texture; `object ids`, because a pick
  /// already taken off the queue would never be answered and a click would
  /// await forever; and the computed `reflection probe N`, because it exists
  /// only on frames with that many probes.
  final Set<String> disabledPasses;

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
  /// **Every field, and that is the whole point of the test beside it.** Seven
  /// were missing here — `surfaceBuffer`, `showSurfaceBuffer`, `showShadowMap`,
  /// `showStaticShadowMap`, `showPointShadowDebug`, `reflections` and `fog` —
  /// so calling `copyWith` to change the exposure silently switched reflections
  /// and fog back off and turned four debug views off with them. Six were
  /// found at once; the seventh went on being dropped for as long as this file
  /// watched the other six, and took an audit to find. A `copyWith` that drops
  /// a field is
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
    TonemapCurve? tonemapCurve,
    AntiAliasSettings? antiAlias,
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
    double? lightFadeBand,
    AutoExposureSettings? autoExposure,
    XraySettings? xray,
    Set<String>? disabledPasses,
  }) => RenderSettings(
    specular: specular ?? this.specular,
    exposure: exposure ?? this.exposure,
    wireframe: wireframe ?? this.wireframe,
    backfaceCulling: backfaceCulling ?? this.backfaceCulling,
    debug: debug ?? this.debug,
    highlighted: highlighted ?? this.highlighted,
    tonemap: tonemap ?? this.tonemap,
    tonemapCurve: tonemapCurve ?? this.tonemapCurve,
    antiAlias: antiAlias ?? this.antiAlias,
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
    lightFadeBand: lightFadeBand ?? this.lightFadeBand,
    autoExposure: autoExposure ?? this.autoExposure,
    xray: xray ?? this.xray,
    disabledPasses: disabledPasses ?? this.disabledPasses,
  );

  /// These settings with the effects a stereo pair cannot have taken out.
  ///
  /// **Three of them are wrong on a stereo frame rather than merely slow**, and
  /// the reason is one line in the renderer: the frame graph is compiled for
  /// `views.first`. Ambient occlusion and reflections then read the surface
  /// buffer of the *whole* frame and reconstruct world positions from the first
  /// view's matrix, so on a pair drawn side by side the right eye is
  /// reconstructed with the left eye's camera — occlusion in the wrong places
  /// and reflections marching along the wrong ray, on half the picture. The
  /// aspect they derive is the whole target's too, which is twice what either
  /// eye has.
  ///
  /// Bloom is here for a nearer reason: it blurs across the seam, so the sun in
  /// one eye glows into the edge of the other, which is exactly where a
  /// difference between the eyes is least forgivable.
  ///
  /// What is *not* here is as deliberate. Fog is applied per draw, in the scene
  /// pass, with the view's own camera, so a pair gets it right. Auto exposure
  /// meters the whole frame, which is what a pair wants: one exposure for two
  /// eyes rather than two that disagree while the head turns. Shadows are drawn
  /// once for the frame and sampled per view.
  ///
  /// Effects are turned off by replacing their settings with the defaults,
  /// which are already off, rather than by clearing one flag: a tuned radius
  /// kept beside a disabled effect is a value that lies about what the frame
  /// did.
  RenderSettings forStereo() => copyWith(
    bloom: bloom.copyWith(enabled: false),
    reflections: const ReflectionSettings(),
    ambientOcclusion: const AmbientOcclusionSettings(),
  );

  /// Node names a measurement frame leaves out — see [forMeasurement].
  ///
  /// Published rather than inlined so a caller building their own variant is
  /// not guessing at strings, and so a new post pass has one obvious list to
  /// join. Every name here is a pass that changes a pixel away from the
  /// number the material wrote; `scene` and `composite` are deliberately
  /// absent, because a measurement frame still needs a picture and the
  /// composite is where `tonemap: false` is honoured.
  static const Set<String> pixelAlteringPasses = <String>{
    'bloom',
    'ssao',
    'reflections',
    'antialias',
    'luminance',
  };

  /// These settings, arranged so the frame's bytes are the numbers the
  /// material wrote rather than a photograph of them — `gfx-40n`.
  ///
  /// **This existed four times before it existed once.** `render_project.dart`
  /// built `tonemap: false, exposure: 1.0` for the agent's weights and
  /// wireframe modes; `display_modes.dart`'s `settingsFor` built the same pair
  /// for the viewport's normals chip; `weight_gradient.dart` built it a third
  /// time; and `CompositeMix` built a fourth inside the engine, forcing
  /// exposure, tone mapping **and** bloom off because — in its own words — a
  /// debug buffer is data rather than light and any of the three would
  /// misreport it.
  ///
  /// **The four did not agree, and that was a bug rather than four styles.**
  /// `CompositeMix` was right and the other three were incomplete: they
  /// touched neither bloom nor the occlusion, so a normals view over a
  /// viewport with bloom switched on returned a glowing debug buffer and
  /// nothing caught it. The number a caller read back was not the number the
  /// material wrote, which is the one promise the mode makes.
  ///
  /// Auto exposure is turned off rather than left to [exposure], because with
  /// the meter running it is the meter and not this setting that decides what
  /// the composite uses, and a pinned exposure beside a running meter is a
  /// value that lies about what the frame did — the argument [forStereo]
  /// makes about a tuned radius beside a disabled effect.
  ///
  /// The passes go through [disabledPasses] rather than through each effect's
  /// own settings object, which is what `gfx-37n` bought: one list to read,
  /// and `FrameResult.skipped` afterwards reporting `PassSkip.disabled` for
  /// each — so a caller who gets an unexpected picture can see that this
  /// method is why, rather than wondering which of six flags did it.
  RenderSettings forMeasurement() => copyWith(
    tonemap: false,
    exposure: 1.0,
    autoExposure: const AutoExposureSettings(),
    disabledPasses: <String>{...disabledPasses, ...pixelAlteringPasses},
  );
}

/// How much of the frame's light spills into a glow.
/// The look put on the frame after it has been tone mapped.
///
/// **Everything here defaults to doing nothing, exactly.** Not nearly nothing:
/// a vignette of zero multiplies by one and grain of zero adds zero, so a scene
/// that asks for none of it composites to the same bytes it did before this
/// existed. Forty-four goldens depend on that being exact, and the composite
/// pass already keeps the same promise for ambient occlusion.
///
/// Applied in the composite rather than as passes of their own, which is the
/// trade this makes against a chain of full-screen effects: one pass, one read
/// of the scene, and no intermediate target — at the cost that the order is
/// fixed. The order is the one a camera imposes and is not arbitrary: the lens
/// disperses colour *before* the sensor sees it, so chromatic aberration reads
/// the scene at offset coordinates; grading is a decision about a displayable
/// image and so follows the tone map; grain and vignette are the film and the
/// barrel, and come last.
/// Which curve the composite rolls highlights off with — `gfx-17n`.
///
/// **A final class with const instances rather than an enum**, the shape
/// `LightingModel` already has and the one `tool/structure.dart`'s "an enum in
/// a published package is machinery or is not an enum" rule asks for: the
/// [code] is part of a uniform layout four backends read, so it is a number
/// this type owns rather than an ordinal the language happens to assign.
///
/// None of these is better than the others and the default is not a verdict:
/// [neutral] leaves midtones where the asset's author put them, [aces] trades
/// midtones for a filmic shoulder, [agx] keeps a gradient inside bright
/// saturated light at the cost of desaturating as it climbs, and [reinhard]
/// touches nothing but the highlights. `composite.frag` carries the argument
/// for each one beside its arithmetic.
final class TonemapCurve {
  const TonemapCurve._(this.name, this.code);

  /// The name it is written down as.
  final String name;

  /// What goes into `CompositeInfo.params.z`. Part of the shader contract.
  final double code;

  /// Khronos PBR Neutral — the default, and what every golden here holds.
  static const TonemapCurve neutral = TonemapCurve._('neutral', 1.0);

  /// ACES, the Narkowicz fit.
  static const TonemapCurve aces = TonemapCurve._('aces', 2.0);

  /// AgX's curve, without the gamut rotation — see `composite.frag`.
  static const TonemapCurve agx = TonemapCurve._('agx', 3.0);

  /// Reinhard, extended so white reaches white.
  static const TonemapCurve reinhard = TonemapCurve._('reinhard', 4.0);

  /// AgX with the gamut rotation, so a hue survives being over-bright —
  /// `gfx-26n`.
  ///
  /// A fifth member rather than a fix to [agx], because 18% grey lands
  /// somewhere else through the rotation and every golden that names `agx`
  /// names the bare curve on purpose. Reach for this when a deep blue or a
  /// saturated lamp has to keep its hue four stops over white; reach for
  /// [agx] when the recorded look is the one that matters.
  static const TonemapCurve agxFull = TonemapCurve._('agxFull', 5.0);

  /// All of them, in the order their codes run.
  static const List<TonemapCurve> values = <TonemapCurve>[
    neutral,
    aces,
    agx,
    reinhard,
    agxFull,
  ];

  @override
  String toString() => 'TonemapCurve.$name';
}

final class LookSettings {
  const LookSettings({
    this.contrast = 1.0,
    this.saturation = 1.0,
    this.temperature = 0.0,
    this.vignette = 0.0,
    this.vignetteRoundness = 1.0,
    this.grain = 0.0,
    this.chromaticAberration = 0.0,
    this.dither = 0.0,
    this.lift,
    this.gamma,
    this.gain,
    this.whiteBalance = 0.0,
    this.tint = 0.0,
    this.lut,
    this.lutStrength = 1.0,
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

  /// What is **added**, per channel, so the shadows move and white stays —
  /// `gfx-27n`. Null is neutral, the same as zero.
  ///
  /// **Lift, gamma and gain are three ranges rather than three strengths.**
  /// [contrast] and [saturation] move the whole picture at once; these move
  /// one end of it, which is what a grade is for. Lift raises the shadows and
  /// leaves white alone, [gain] moves the highlights and leaves black alone,
  /// and [gamma] is the exponent between them. Each is a colour rather than a
  /// number, because the whole reason to reach for them is a warm highlight
  /// over a cool shadow, and one scalar per stage cannot say that.
  final vm.Vector3? lift;

  /// The **exponent**, per channel, so the midtones move and both ends stay.
  /// Null is neutral, the same as one. See [lift].
  final vm.Vector3? gamma;

  /// What is **multiplied**, per channel, so the highlights move and black
  /// stays. Null is neutral, the same as one. See [lift].
  final vm.Vector3? gain;

  /// Warm above zero, cool below, in the range −1 to 1 — `gfx-27n`.
  ///
  /// **Not [temperature], and the two are deliberately both here.**
  /// [temperature] is a gain on red against blue: a look, and documented as
  /// one. This is the correction a camera and a grading panel offer, and it
  /// comes with [tint] across it because a white balance without a
  /// green-magenta axis can only fix half of what is wrong with a white.
  ///
  /// Approximated in display space rather than converted through a chromatic
  /// adaptation matrix: the exact transform wants the scene's own white
  /// point, and the composite has the picture rather than the light that made
  /// it.
  final double whiteBalance;

  /// Green above zero, magenta below, in the range −1 to 1. The other axis of
  /// [whiteBalance], and takes its green out of red and blue rather than
  /// adding light, so a tint alone changes the hue and not the level.
  final double tint;

  /// Ordered noise added after the sRGB encode, in output steps — `gfx-24n`.
  ///
  /// `1 / 255` is one 8-bit step and is the value to reach for; 0 is off,
  /// exactly, and is the default because every golden was recorded without it.
  ///
  /// **What it is for: a dark gradient that arrives in six flat bands.** The
  /// frame is computed in floating point and written to an 8-bit target, and
  /// near black the sRGB curve is at its steepest, so a long shallow ramp —
  /// a shadowed corridor wall, a vignette, a soft key light falling off —
  /// quantises to a handful of distinct values with visible edges between
  /// them. Adding less than one step of ordered noise before the value is
  /// rounded turns each edge into a dither pattern the eye integrates back
  /// into a gradient.
  ///
  /// Ordered rather than random: a hash gives the same result numerically and
  /// reads as noise on a flat surface, where a 4x4 Bayer cell reads as a
  /// gradient. Both are fixed to screen position and neither moves with time,
  /// which is what keeps a golden stable — the same constraint [grain]
  /// documents from the other side.
  final double dither;

  /// A colour table, as a strip of N slices of N×N — `gfx-18n`'s own row.
  ///
  /// **The shape every grading tool exports**, and the shape three of this
  /// engine's four backends can sample without a capability check: N² wide
  /// and N tall, blue selecting the slice, red running across it and green
  /// down. [buildIdentityLut] makes the one that changes nothing, which is
  /// what a test compares against and what somebody starts from.
  ///
  /// Null is not "a neutral table": nothing is sampled at all, and that is
  /// the difference [lutStrength] of zero also makes.
  final TextureHandle? lut;

  /// How much of [lut] to apply, 0 to 1.
  ///
  /// Zero means the composite never samples the table — a branch on a
  /// uniform, so the whole draw takes one side of it. Anything above zero
  /// mixes towards the graded colour.
  final double lutStrength;

  /// Whether [lut] will actually be sampled this frame.
  bool get gradesThroughLut => lut != null && lutStrength > 0.0;

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
      chromaticAberration == 0.0 &&
      !gradesThroughLut;

  LookSettings copyWith({
    double? contrast,
    double? saturation,
    double? temperature,
    double? vignette,
    double? vignetteRoundness,
    double? grain,
    double? chromaticAberration,
    double? dither,
    vm.Vector3? lift,
    vm.Vector3? gamma,
    vm.Vector3? gain,
    double? whiteBalance,
    double? tint,
    TextureHandle? lut,
    double? lutStrength,
  }) => LookSettings(
    contrast: contrast ?? this.contrast,
    saturation: saturation ?? this.saturation,
    temperature: temperature ?? this.temperature,
    vignette: vignette ?? this.vignette,
    vignetteRoundness: vignetteRoundness ?? this.vignetteRoundness,
    grain: grain ?? this.grain,
    chromaticAberration: chromaticAberration ?? this.chromaticAberration,
    dither: dither ?? this.dither,
    lift: lift ?? this.lift,
    gamma: gamma ?? this.gamma,
    gain: gain ?? this.gain,
    whiteBalance: whiteBalance ?? this.whiteBalance,
    tint: tint ?? this.tint,
    lut: lut ?? this.lut,
    lutStrength: lutStrength ?? this.lutStrength,
  );
}

/// Edges smoothed on the finished picture — `gfx-04n`'s own row.
///
/// **It exists to end a choice nobody should have to make.** The scene pass
/// turns MSAA off whenever anything consumes the surface buffer, because a
/// multisampled attachment and a buffer a later pass reads are the same
/// decision made twice — so switching ambient occlusion on cost every edge in
/// the frame its smoothing, and a game got shadows in its corners or clean
/// silhouettes and not both.
///
/// Off by default, because it is a pass and a texture, and because MSAA is
/// the better answer wherever it is still available: it sees edges this
/// cannot, a thin wire that fell between two pixel centres among them. On by
/// default *with* the surface buffer would be a reasonable policy and is
/// deliberately not taken here — the renderer does not turn passes on behind
/// a caller's back.
/// How many halvings the bloom chain does on a frame [frameHeight] tall —
/// `gfx-31n`.
///
/// **A function rather than a method, so it can be checked without a frame.**
/// The arithmetic is where the row's whole claim lives — that identical
/// settings cover the same fraction of the picture at two resolutions — and a
/// claim about arithmetic should be testable as arithmetic rather than by
/// rendering two frames and comparing glows.
///
/// With [BloomSettings.referenceHeight] at zero this is
/// [BloomSettings.levels] unchanged. Otherwise it is that count plus the
/// doublings between the reference height and the real one, rounded to the
/// nearest whole halving: the chain can only be lengthened by whole levels,
/// so a frame 1.5x taller gets one more rather than half of one.
int bloomLevelsFor(BloomSettings settings, {required int frameHeight}) {
  final reference = settings.referenceHeight;
  if (reference <= 0 || frameHeight <= 0) return settings.levels;
  // log2 of the ratio: each doubling of the frame wants one more halving for
  // the glow to reach the same share of it.
  final doublings = math.log(frameHeight / reference) / math.ln2;
  return settings.levels + doublings.round();
}

final class AntiAliasSettings {
  const AntiAliasSettings({
    this.enabled = false,
    this.contrastThreshold = 0.125,
    this.blend = 0.75,
    this.sharpen = 0.0,
  });

  final bool enabled;

  /// How much local contrast a pixel needs before it is worth touching, as a
  /// fraction of the local maximum.
  ///
  /// Relative and not absolute: a step of 0.02 across a dark surface is an
  /// edge somebody can see and the same step across a white wall is
  /// dithering. 0.125 is where an edge starts reading as an edge; lower
  /// scrubs texture detail, higher leaves staircases on shallow slopes.
  final double contrastThreshold;

  /// How far along the edge to sample, as a fraction of a texel. One is the
  /// whole neighbour, which over-blurs; 0.75 keeps a silhouette crisp.
  final double blend;

  /// Contrast-adaptive sharpening on the finished picture — `gfx-29n`. 0 is
  /// off exactly, and is the default.
  ///
  /// **It lives on the anti-aliasing settings because it lives in that pass**,
  /// and it lives in that pass because the four neighbours it needs are the
  /// four the smoothing already fetches. A pass of its own would be a second
  /// full-screen draw for the same answer.
  ///
  /// **Sharpening is what normally follows a smoothed image**, and this
  /// engine had neither it nor any unsharp path, while `fxaa.frag` documents
  /// that it is the only anti-aliasing left once the surface buffer is in use
  /// — so a frame with ambient occlusion on was softened with nothing to put
  /// the edge back.
  ///
  /// Adaptive rather than a plain unsharp mask: the amplitude comes from how
  /// much headroom the neighbourhood leaves, so a pixel already against the
  /// ceiling is not pushed past it. That is what separates sharpening from
  /// the bright halo along every hard edge that reads as a cheap filter.
  /// 0.5 is visible without announcing itself; 1 is the most the kernel
  /// offers.
  final double sharpen;

  AntiAliasSettings copyWith({
    bool? enabled,
    double? contrastThreshold,
    double? blend,
    double? sharpen,
  }) => AntiAliasSettings(
    enabled: enabled ?? this.enabled,
    contrastThreshold: contrastThreshold ?? this.contrastThreshold,
    blend: blend ?? this.blend,
    sharpen: sharpen ?? this.sharpen,
  );
}

/// The colour table that changes nothing, [size] slices wide — `gfx-18n`.
///
/// **What every other table is a departure from.** A grading tool exports one
/// of these, somebody paints over it, and the difference between the two is
/// the look. It is also what a test compares against: a table whose entries
/// are exactly the colours they stand for should leave a frame where it was,
/// and whether it *exactly* does is a question about the texture's own
/// precision rather than about the arithmetic.
///
/// The strip is `size²` wide and `size` tall: blue picks the slice, red runs
/// across it, green down. 33 is what most tools export and is the default;
/// 17 is the other common one and is cheap enough to test with.
///
/// Eight bits a channel, because that is what a table read off disk will be
/// and a neutral one that is secretly more precise than a real one would be
/// testing the wrong thing.
Uint8List buildIdentityLut({int size = 33}) {
  if (size < 2) {
    throw ArgumentError.value(size, 'size', 'a table needs at least two ends');
  }
  final width = size * size;
  final pixels = Uint8List(width * size * 4);
  final last = size - 1;
  for (var blue = 0; blue < size; blue++) {
    for (var green = 0; green < size; green++) {
      for (var red = 0; red < size; red++) {
        final at = ((green * width) + blue * size + red) * 4;
        pixels[at] = (red * 255 / last).round();
        pixels[at + 1] = (green * 255 / last).round();
        pixels[at + 2] = (blue * 255 / last).round();
        pixels[at + 3] = 255;
      }
    }
  }
  return pixels;
}

final class BloomSettings {
  const BloomSettings({
    this.enabled = true,
    this.threshold = 1.0,
    this.knee = 0.5,
    this.intensity = 0.06,
    this.levels = 5,
    this.filterRadius = 1.0,
    this.referenceHeight = 0,
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

  /// The frame height [levels] was chosen at, or 0 to leave it alone —
  /// `gfx-31n`.
  ///
  /// **What it fixes: the same settings glowing differently at two
  /// resolutions.** [levels] is a count of halvings, and each halving doubles
  /// the glow's reach *in pixels* — so a chain of five reaches a fixed number
  /// of pixels, which is a different fraction of the picture at 512 than it
  /// is at 1024. Export the frame at twice the size and the bloom covers half
  /// as much of it, from settings nobody touched.
  ///
  /// Given a height, the chain is lengthened or shortened by the doublings
  /// between that height and the real one, so the reach stays a fraction of
  /// the frame rather than a number of pixels. At 0 — the default — nothing
  /// is recomputed and [levels] means exactly what it always did, which is
  /// what keeps every recorded frame where it was.
  ///
  /// The count is still clamped to the chain the frame can actually hold: a
  /// level whose target is one pixel has nothing left to halve.
  final int referenceHeight;

  BloomSettings copyWith({
    bool? enabled,
    double? threshold,
    double? knee,
    double? intensity,
    int? levels,
    double? filterRadius,
    int? referenceHeight,
  }) => BloomSettings(
    enabled: enabled ?? this.enabled,
    threshold: threshold ?? this.threshold,
    knee: knee ?? this.knee,
    intensity: intensity ?? this.intensity,
    levels: levels ?? this.levels,
    filterRadius: filterRadius ?? this.filterRadius,
    referenceHeight: referenceHeight ?? this.referenceHeight,
  );
}
