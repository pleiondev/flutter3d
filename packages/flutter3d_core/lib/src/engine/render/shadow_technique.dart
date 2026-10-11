/// How the directional light's shadow map is turned into a soft edge: the
/// open interface behind `ShadowFilter`.
///
/// Its own file because it is the one part of the shadow settings meant to
/// be implemented outside the engine. `ShadowSettings` says what a scene
/// wants; a [ShadowTechnique] says what the renderer does about it.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart'
    show ScreenRect, TextureHandle;
import 'package:vector_math/vector_math.dart' as vm;

import '../scene/camera_node.dart';
import 'render_node.dart';
import 'shadow_settings.dart';

/// What a [ShadowTechnique] is told when the frame asks it for a producer
/// of its own (D22): one object that can gain members — the cascades the
/// engine fitted, the atlas rows a cube light holds — rather than a list of
/// parameters that grows.
final class ShadowProducerContext {
  const ShadowProducerContext({
    required this.settings,
    this.camera,
    this.cascades,
  });

  /// The frame's shadow settings.
  final ShadowSettings settings;

  /// The camera the cascades are split along — the first view's — or null
  /// for a frame with none.
  final CameraNode? camera;

  /// What the engine fitted and laid out for the directional map this
  /// frame, which [ShadowTechnique.shadowMapProducer]'s node draws into;
  /// null where the frame asks of a producer with nothing fitted.
  final ShadowCascades? cascades;
}

/// The directional map as the engine fitted and laid it out for one frame:
/// what a technique's own producer draws into (D22).
///
/// **The atlas is the engine's, and so is its layout.** [atlas] holds one
/// square tile of [resolution] texels per cascade, side by side
/// ([tileOf]), and the lit stages read tile `i` through the matrix the
/// engine fitted for it. A producer draws cascade `i` with
/// [viewProjections] `[i]` into [tileOf] `(i)`, with [depth] as its depth
/// attachment, and writes what the engine's `ShadowDepth` stage writes: the
/// stored depth in red, the far plane where nothing is — one where
/// [reversed] is false, nought where it is true, in red and in the depth
/// alike. It clears what it does not draw: nothing of an earlier frame is
/// kept for it.
final class ShadowCascades {
  const ShadowCascades({
    required this.atlas,
    required this.depth,
    required this.resolution,
    required this.viewProjections,
    required this.lightDirection,
    required this.reversed,
  });

  /// The colour target the lit stages sample as the directional map.
  final TextureHandle atlas;

  /// A depth attachment the size of [atlas], for the producer's pass.
  final TextureHandle depth;

  /// One tile's side, in texels.
  final int resolution;

  /// Each cascade's view and projection as this device draws with it —
  /// its depth range, and turned round where [reversed] says so.
  final List<vm.Matrix4> viewProjections;

  /// Which way the light travels, unit length, in world space.
  final vm.Vector3 lightDirection;

  /// Whether the map stores depth turned round, the far plane at nought.
  final bool reversed;

  /// How many cascades the atlas holds, one to three.
  int get count => viewProjections.length;

  /// Where cascade [index] lies in [atlas].
  ScreenRect tileOf(int index) => ScreenRect(
    x: index * resolution,
    width: resolution,
    height: resolution,
  );
}

/// The lookup the lit draws make into the directional map, and its
/// parameters.
///
/// **A closed set in 1.0, and the reason is the bundle.** The lit shaders are
/// compiled ahead of time (`tool/build_shaders.sh`) with these three lookups
/// in them, and a frame chooses between them with one number per draw. A
/// lookup the shaders do not contain cannot be named here; a stage of one's
/// own can, which [ShadowTechnique] explains.
///
/// A final class with const instances rather than an enum, so a lookup added
/// to the shaders in a minor release does not break anybody's `switch`.
final class ShadowKernel {
  const ShadowKernel._(this.name, this.lightRadius, this.bleedReduction);

  /// Percentage-closer soft shadows: a search for what is blocking, then a
  /// filter as wide as a light of apparent radius [lightRadius] (radians,
  /// above nought) would leave. Sixteen taps each way on a Vogel disc.
  const ShadowKernel.blockerSearch({required this.lightRadius})
    : name = 'blockerSearch',
      bleedReduction = 0.0,
      assert(lightRadius > 0.0, 'a light of no size casts no penumbra');

  /// One filtered tap of exponential moments, made from the map by a
  /// [ShadowPrefilter] before the lit draws run. [bleedReduction] is the
  /// share of the bound cut off as light bleeding, nought to 0.95.
  ///
  /// **Needs the moments.** A frame that has none, because the technique
  /// named no prefilter, the stage it named is not in the renderer's
  /// shaders, or the device cannot filter a 32-bit float target, draws
  /// [box3x3] instead, and the last of those is reported in
  /// `FrameResult.skipped` as `PassSkip.unsupported` for `'shadow moments'`.
  const ShadowKernel.moments({this.bleedReduction = 0.2})
    : name = 'moments',
      lightRadius = 0.0;

  /// Nine taps in a 3×3 square: a texel-wide edge, sharp or soft only as the
  /// map's resolution makes it.
  static const ShadowKernel box3x3 = ShadowKernel._('box3x3', 0.0, 0.0);

  /// `box3x3`, `blockerSearch` or `moments`: which lookup this is.
  final String name;

  /// The light's apparent radius for [ShadowKernel.blockerSearch], in
  /// radians; nought for the others.
  final double lightRadius;

  /// The light-bleeding cut for [ShadowKernel.moments], a fraction from
  /// nought to 0.95; nought for the others.
  final double bleedReduction;

  /// Whether this lookup reads moments rather than depth.
  bool get readsMoments => name == 'moments';

  @override
  bool operator ==(Object other) =>
      other is ShadowKernel &&
      other.name == name &&
      other.lightRadius == lightRadius &&
      other.bleedReduction == bleedReduction;

  @override
  int get hashCode => Object.hash(name, lightRadius, bleedReduction);

  @override
  String toString() => switch (name) {
    'blockerSearch' => 'ShadowKernel.blockerSearch($lightRadius)',
    'moments' => 'ShadowKernel.moments($bleedReduction)',
    _ => 'ShadowKernel.$name',
  };
}

/// The full-screen stage that turns the directional depth atlas into the
/// moments [ShadowKernel.moments] reads, and how wide it blurs.
///
/// The renderer draws [stage] twice over the whole atlas, across and then
/// down, into two `r32g32b32a32Float` targets the size of the atlas, and
/// only when the atlas has changed since the moments were last made. A
/// stage of one's own is found by name in `Renderer.shaders`, so an
/// application's bundle handed to `RendererSteps.addMaterials` can supply
/// it.
///
/// **What such a stage has to declare** is what the engine's `EvsmFilter`
/// (`evsm_filter.frag`) does: the source as the sampler `evsm_source`, and the
/// block `EvsmFilterInfo` with `tile` (cascade count, half a texel across and
/// down, how the atlas stores depth) and `axis` (the texel step across, the
/// step down, the radius, and one on the first pass, which reads depth and
/// warps it, nought on the second, which reads moments). What it writes is
/// read by `EvsmVisibility` in `evsm.glsl`, so it writes that layout: the
/// positive and negative exponential warps and their squares. A stage in the
/// material language cannot be one yet, since a full-screen `.f3dmat` stage
/// binds `scene` and its own parameters rather than this block.
final class ShadowPrefilter {
  const ShadowPrefilter({required this.stage, this.radius = 2});

  /// The fragment stage's name in `Renderer.shaders`.
  final String stage;

  /// How far the blur reaches to each side, in texels of the atlas, nought
  /// to eight; clamped to that.
  final int radius;

  @override
  bool operator ==(Object other) =>
      other is ShadowPrefilter &&
      other.stage == stage &&
      other.radius == radius;

  @override
  int get hashCode => Object.hash(stage, radius);

  @override
  String toString() => 'ShadowPrefilter($stage, radius: $radius)';
}

/// How the directional map is drawn, prepared and read: what a
/// `ShadowFilter` stands for when the renderer draws a frame.
///
/// **The renderer asks it three things, each frame, of the frame's
/// `ShadowSettings`:**
///
/// - [cascadesFor]: how many cascades the map is split into, one to three;
/// - [prefilterFor]: whether a stage turns the map into moments after the
///   casters are drawn, which one, and how wide it blurs;
/// - [kernelFor]: which lookup the lit draws make, with what parameters.
///
/// The built-in filters are instances: [pcf], [pcss] and [evsm], and
/// `ShadowFilter.pcf.technique` is [pcf]. They read the settings exactly as
/// the renderer did before there was an interface, so every picture is the
/// same.
///
/// **A technique of one's own** extends this class and is named by
/// `ShadowFilter.custom(name, base: …, technique: …)`. What it can change in
/// 1.0, and what each part runs on:
///
/// - the cascade count, and the parameters of any of the three lookups (a
///   softer or harder sun than the settings say, a different bleed cut);
/// - the moments prefilter, as a stage of its own (see [ShadowPrefilter]):
///   a different blur, another warp, on every backend that runs the bundle
///   it ships in.
///
/// What it cannot change is the lookup itself. That is compiled into the
/// engine's lit stages, and the material language's `light` hook multiplies
/// by the engine's shadow rather than computing one. An application that
/// needs a lookup of its own writes its own lit stage in GLSL, names it with
/// a `LightingModel` of its own, and reads `shadow_texture` and the kernel
/// slot the renderer binds for every lit draw; it is the one path that runs
/// a different lookup today, and it is a shader, not a technique.
///
/// The cube atlas of point and spot lights is filtered by its own soft
/// path, `ShadowSettings.pointLightRadius`; a technique may draw it through
/// [cubeAtlasProducer].
///
/// **Extendable outside this package, and stays so through 1.x**: a member
/// added later arrives with a default, so a technique written against 1.0
/// keeps compiling. Keep it immutable and give it a `const` constructor, so
/// a `ShadowFilter.custom` that names it stays `const`.
abstract base class ShadowTechnique {
  const ShadowTechnique();

  /// The name it is written down as, in a trace or an error.
  String get name;

  /// The lookup the lit draws make into the map under [settings].
  ShadowKernel kernelFor(ShadowSettings settings);

  /// What turns the map into moments under [settings], or null for none.
  ///
  /// Read only while [kernelFor] answers a [ShadowKernel.moments]: a
  /// prefilter under another lookup is never drawn. A moments lookup takes
  /// over the atlas's spare channels, so `ShadowSettings.translucentCasters`
  /// does nothing under one.
  ShadowPrefilter? prefilterFor(ShadowSettings settings) => null;

  /// How many cascades the map is split into under [settings]; the renderer
  /// clamps it to one to three. `ShadowSettings.cascades` by default.
  int cascadesFor(ShadowSettings settings) => settings.cascades;

  /// A node that draws the directional map — writes
  /// `FrameResourceIds.shadowMap` — in place of the engine's `directional
  /// shadows`, or null for the engine's own (D22).
  ///
  /// **The seam for a shadow of one's own making**: casters drawn another
  /// way (moments written directly, a ray-traced mask, a baked map read
  /// back), into the atlas the engine laid out and with the light's
  /// matrices the engine fitted, which the lit stages read as they always
  /// do. The node is placed where the engine's stands and declares
  /// `shadowMap` among its writes. Null by default, which is every built-in
  /// technique.
  ///
  /// The renderer asks this each frame the map is drawn, once it has fitted
  /// the cascades and laid out the atlas, with both in
  /// [ShadowProducerContext.cascades], and runs the node's
  /// [RenderNode.execute] where it would have drawn the casters. A frame
  /// the shadows are off in, or with nothing to cast, asks nothing.
  RenderNode? shadowMapProducer(ShadowProducerContext context) => null;

  /// For a technique an application or a plugin writes: a node that
  /// maintains the cube atlas of point and spot lights — keeps
  /// `FrameResourceIds.cubeShadow` — in place of the engine's `point
  /// shadows`, or null for the engine's own (D22). The atlas's layout, a
  /// row of six faces per light in the slot the engine assigned, is the
  /// contract the lit stages read; see [shadowMapProducer] for when the
  /// renderer asks.
  RenderNode? cubeAtlasProducer(ShadowProducerContext context) => null;

  /// [ShadowFilter.pcf]'s: a 3×3 box.
  static const ShadowTechnique pcf = _PcfTechnique();

  /// [ShadowFilter.pcss]'s: a blocker search sized by
  /// `ShadowSettings.directionalLightRadius`, or the sun's when that is
  /// nought.
  static const ShadowTechnique pcss = _PcssTechnique();

  /// [ShadowFilter.evsm]'s: the engine's `EvsmFilter` blur at
  /// `ShadowSettings.evsmBlurRadius`, read with
  /// `ShadowSettings.evsmBleedReduction`.
  static const ShadowTechnique evsm = _EvsmTechnique();

  @override
  String toString() => 'ShadowTechnique($name)';
}

final class _PcfTechnique extends ShadowTechnique {
  const _PcfTechnique();

  @override
  String get name => 'pcf';

  @override
  ShadowKernel kernelFor(ShadowSettings settings) => ShadowKernel.box3x3;
}

final class _PcssTechnique extends ShadowTechnique {
  const _PcssTechnique();

  @override
  String get name => 'pcss';

  @override
  ShadowKernel kernelFor(ShadowSettings settings) => ShadowKernel.blockerSearch(
    lightRadius: settings.directionalLightRadius > 0.0
        ? settings.directionalLightRadius
        : ShadowSettings.sunAngularRadius,
  );
}

final class _EvsmTechnique extends ShadowTechnique {
  const _EvsmTechnique();

  @override
  String get name => 'evsm';

  @override
  ShadowKernel kernelFor(ShadowSettings settings) => ShadowKernel.moments(
    bleedReduction: settings.evsmBleedReduction.clamp(0.0, 0.95),
  );

  @override
  ShadowPrefilter? prefilterFor(ShadowSettings settings) => ShadowPrefilter(
    stage: 'EvsmFilter',
    radius: settings.evsmBlurRadius.clamp(0, 8),
  );
}
