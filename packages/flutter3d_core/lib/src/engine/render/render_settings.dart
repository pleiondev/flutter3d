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
///
/// **0.7.4 took the ghost copies out.** A floor of roughness 0.3 under an
/// object showed shifted, smeared copies of it, and four things added up to
/// them: the march started every pixel on the same step, so neighbours crossed
/// the object with the same overshoot (now jittered, and refined by halving the
/// last stride); a roughness of 0.3 still reflected like a mirror at 58%
/// (now gone by 0.25, since this pass has no blur); a hit at the far end of
/// the march weighed as much as one beside the surface (now faded with the
/// length of the ray); and the Fresnel term floored at 15% where a dielectric
/// reflects 4% head-on (now Schlick with F0 = 0.04). The defaults follow
/// Filament's: a ten-centimetre stride over about three metres.
///
/// **Every surface is a dielectric here.** The surface buffer carries a
/// normal, a roughness and a depth, not a metalness, so the pass cannot tell
/// chrome from plastic: a polished metal floor seen head-on reflects the same
/// 4% a plastic one does, where a real one would reflect most of the light.
final class ReflectionSettings {
  const ReflectionSettings({
    this.enabled = false,
    this.steps = 32,
    this.stride = 0.1,
    this.thickness = 0.12,
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

/// Contact shadows: a short march toward the light, in screen space —
/// `gfx-76n`.
///
/// **What a shadow map cannot do at any resolution.** A box resting on a plane
/// meets it along a line, and the shadow that belongs there is a texel wide or
/// less. Raising the map's resolution moves the line closer to right without
/// arriving; raising the bias enough to stop the acne a tight contact produces
/// detaches the shadow from the object, which is the familiar look of a prop
/// floating a centimetre above the floor.
///
/// **Not contact *hardening*.** `shadow.glsl` already sizes its penumbra from
/// the blockers it finds, so a shadow is sharp where its caster is close. That
/// is a different thing with a confusingly similar name.
///
/// Off by default, and [strength] at nought multiplies by exactly one — the
/// same construction the occlusion above uses, and what lets this ship without
/// moving a recorded frame.
final class ContactShadowSettings {
  const ContactShadowSettings({
    this.enabled = false,
    this.length = 0.25,
    this.steps = 8,
    this.thickness = 0.15,
    this.bias = 0.01,
    this.strength = 1.0,
  });

  final bool enabled;

  /// How far the march reaches, in world metres.
  ///
  /// A quarter of a metre: the gap a shadow map leaves is the first few
  /// centimetres, and a march long enough to replace the map would be a march
  /// whose cost is the map's without its coverage.
  final double length;

  /// How many steps, one to sixteen — `kContactSteps` in the shader bounds the
  /// loop, and this is the count it breaks at.
  final int steps;

  /// How thick an occluder is assumed to be, in metres.
  ///
  /// A surface nearer to the eye than the ray by more than this is something
  /// else standing in front rather than the thing casting. Without it a wall
  /// four metres nearer than the floor shadows everything the ray crosses,
  /// which is the halo the occlusion's own range check exists to stop.
  final double thickness;

  /// How far the ray is lifted along the surface normal, in metres, so a flat
  /// surface does not shadow itself. Metres and not window depth, for
  /// `ssao.frag`'s reason: a bias in window depth is a different number of
  /// millimetres at every distance from the camera.
  final double bias;

  /// How much of the result reaches the picture, nought to one.
  ///
  /// Applied in the composite and nowhere else, so "off" is a multiplier of
  /// exactly one rather than nearly one.
  final double strength;

  ContactShadowSettings copyWith({
    bool? enabled,
    double? length,
    int? steps,
    double? thickness,
    double? bias,
    double? strength,
  }) => ContactShadowSettings(
    enabled: enabled ?? this.enabled,
    length: length ?? this.length,
    steps: steps ?? this.steps,
    thickness: thickness ?? this.thickness,
    bias: bias ?? this.bias,
    strength: strength ?? this.strength,
  );
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
    this.blurDepthFalloff = 0.02,
    this.method = AmbientOcclusionMethod.ssao,
    this.thickness = 0.3,
  });

  final bool enabled;

  /// How the occlusion is found — `L5`. [AmbientOcclusionMethod.ssao], the
  /// hemisphere kernel, stays the default.
  final AmbientOcclusionMethod method;

  /// How deep, in metres, the indirect method takes each thing it sees to
  /// be — `L5`. Read only by [AmbientOcclusionMethod.ssil].
  ///
  /// The horizon methods treat the depth buffer as a height field: whatever
  /// rises above a point hides everything behind it. A slab this thick hides
  /// only what is behind it, so a pole a few centimetres across shades the
  /// wall behind it and lets the light past on either side.
  final double thickness;

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

  /// How much difference in depth takes a tap's weight in that blur down to
  /// 1/e, **as a fraction of the centre pixel's own depth**.
  ///
  /// The number that decides whether occlusion bleeds past a silhouette. Too
  /// large and the dark of a corner spreads out over whatever is in front of
  /// it, which is the halo that makes people switch ambient occlusion off;
  /// too small and a curved surface loses the smoothing the blur is for,
  /// because its own depth changes faster than the falloff allows.
  ///
  /// Relative since 0.7.4, as XeGTAO's denoiser takes it. In metres it was
  /// right at one distance only: ten centimetres smeared small edges a metre
  /// from the camera and switched the blur off on a floor seen at twenty,
  /// whose depth changes by more than that from one pixel to the next. 0.02
  /// is the old ten centimetres at five metres.
  final double blurDepthFalloff;

  /// How far, in metres, the sample origin is lifted off its own surface.
  ///
  /// In metres rather than in window depth on purpose: a bias in depth units is
  /// a different physical distance at every range, so one tuned against a near
  /// wall leaves acne on a far one.
  final double bias;
}

/// How the occlusion pass finds what hides a point — `L5`.
///
/// A final class with const instances, like [TonemapCurve], because [code]
/// goes into a uniform four backends read.
final class AmbientOcclusionMethod {
  const AmbientOcclusionMethod._(this.name, this.code);

  final String name;

  /// What goes into `SsaoInfo.screen.z`. Part of the shader contract.
  final double code;

  /// Twelve taps into the hemisphere, rotated by the pixel — what the
  /// engine has always drawn.
  static const AmbientOcclusionMethod ssao = AmbientOcclusionMethod._(
    'ssao',
    0.0,
  );

  /// Ground-truth ambient occlusion: the horizon on either side of two
  /// slices, integrated against the projected normal in closed form. The
  /// sample count is spread over the slices' steps.
  static const AmbientOcclusionMethod gtao = AmbientOcclusionMethod._(
    'gtao',
    1.0,
  );

  /// Screen-space indirect light: the slices of [gtao], each sample a slab
  /// of [AmbientOcclusionSettings.thickness] covering a run of sixteen
  /// sectors, and the light of the sectors it uncovers first bounced onto
  /// the point by the albedo buffer. Occlusion and one bounce from one
  /// march; the composite adds the light by the same strength it darkens by.
  static const AmbientOcclusionMethod ssil = AmbientOcclusionMethod._(
    'ssil',
    2.0,
  );

  static const List<AmbientOcclusionMethod> values = <AmbientOcclusionMethod>[
    ssao,
    gtao,
    ssil,
  ];

  @override
  String toString() => 'AmbientOcclusionMethod.$name';
}

/// Volumetric light shafts, marched through the directional shadow map —
/// `gfx-33n`.
///
/// **Not the radial smear, and the difference is what it can draw.** The
/// cheap version takes bright pixels and streaks them away from the sun's
/// position on screen: it needs the sun in frame, it brightens anything else
/// that happens to be bright, and it knows nothing about what is casting.
/// This marches the view ray and asks the shadow map whether each point in
/// the air is lit, so a beam through a doorway is the doorway's shape — and
/// with the caster's shadow switched off there is nothing to draw at all,
/// which is the check the row is held to.
///
/// **It needs a shadow-casting directional light**, because the shadow map is
/// where the shape comes from. A scene with no caster gets nothing, silently:
/// that is the honest answer rather than an error, since a light being added
/// later is the ordinary case.
///
/// **Single scattering since 0.7.4, and that is what took the white veil
/// away.** It used to add `strength × colour` to every pixel in proportion to
/// how much of its ray was lit — the same for a wall two metres off as for
/// forty metres of air, the same looking at the sun as with it behind you,
/// and white whatever colour the sun was. In an open daylight scene nearly
/// all the air is lit, so the whole frame rose by a flat 0.15 and lost its
/// saturation. Now the air in-scatters the caster's own light: in proportion
/// to how much air there is (`1 − e^(−σd)` over the ray), weighted by a
/// Henyey–Greenstein phase that puts it towards the sun and almost none away
/// from it — Pestana's shadow-map march, and Godot's volumetric fog, both do
/// the same. The scene behind is not dimmed; [FogSettings] does that.
/// What the composite encodes the finished frame for — `R9`.
enum OutputTransform {
  /// Tone-mapped, graded and dithered into eight bits: a standard display.
  sdr,

  /// Scene-referred, exposed but not tone-mapped, in the sRGB transfer
  /// extended past one, into the device's first HDR output format. Reference
  /// white is one; a highlight above it is brighter than white on a display
  /// that can show it. No colour table and no dither: a table is authored
  /// for the SDR range, and a float target does not band.
  extendedSrgb,
}

/// Local exposure by exposure fusion — `R7`.
///
/// **What one exposure cannot do.** A dark room with a bright window has two
/// right exposures, and auto exposure has to pick one: the room black or the
/// window white. This takes the scene three times over — [shadowStops] up,
/// as it is, [highlightStops] down — weighs at each place how near mid-grey
/// each would come out, blurs the weights wide so no edge grows a halo, and
/// gives each place the exposure its weights choose, before the tone curve.
/// [strength] is how much of that shift applies: nought is the one global
/// exposure, one the full local answer.
///
/// Measured at an eighth of the frame and applied bilinearly: the blur is
/// wide enough that nothing finer survives it.
final class LocalExposureSettings {
  const LocalExposureSettings({
    this.enabled = false,
    this.strength = 0.7,
    this.shadowStops = 2.0,
    this.highlightStops = 2.0,
  });

  final bool enabled;
  final double strength;
  final double shadowStops;
  final double highlightStops;
}

/// Bringing a frame drawn below full size up to it without a temporal
/// resolve — `R5`.
///
/// **For the path that has no history to reconstruct from.** With the
/// resolve on, the frame is rebuilt at full size from jittered frames; with
/// it off, [RenderSettings.renderScale] used to hand back the smaller texture
/// for the presenter to stretch. Enabled, the finished picture is brought up
/// to the asked-for size by an edge-adaptive twelve-tap filter, which keeps
/// an edge an edge where a stretch blurs it, and then sharpened. After the
/// tone map, because in HDR a highlight rings around any lobed filter.
final class SpatialUpscaleSettings {
  const SpatialUpscaleSettings({this.enabled = false, this.sharpen = 0.2});

  final bool enabled;

  /// How much the sharpening pass that follows adds back, nought to one.
  /// The same robust kernel a temporal resolve is followed by; nought skips
  /// it.
  final double sharpen;

  /// Whether a frame with [settings] is upscaled.
  static bool runsFor(RenderSettings settings) =>
      settings.spatialUpscale.enabled &&
      settings.renderScale < 1.0 &&
      !settings.antiAlias.temporal.enabled;
}

final class LightShaftSettings {
  const LightShaftSettings({
    this.enabled = false,
    this.steps = 16,
    this.distance = 40.0,
    this.strength = 0.005,
    this.color,
    this.anisotropy = 0.6,
  });

  /// Off by default. It is a full-screen pass with sixteen shadow lookups a
  /// pixel, which is a real cost for an effect a scene either wants badly or
  /// not at all.
  final bool enabled;

  /// Samples along each view ray. Bounded at sixty-four in the shader, the
  /// same rule every marching loop in this engine keeps — a loop a uniform
  /// can lengthen without limit is a hang rather than a slow frame.
  ///
  /// Sixteen reads as a beam because each pixel starts a fraction of a step
  /// further along, from an ordered cell; without that offset sixteen steps
  /// read as sixteen bands.
  final int steps;

  /// How far along the ray to march, in world metres. Shorter spends the
  /// samples where the air is closest and gives up the far end of a long
  /// shaft; longer spreads them and softens it.
  final double distance;

  /// How thick the air is: its scattering coefficient σ, per metre.
  ///
  /// **A density since 0.7.4, where it was a brightness.** 0.005 is a clear
  /// day's haze — forty metres of it in-scatter `1 − e^(−0.2)`, about a fifth
  /// of the light passing through; 0.02 to 0.05 is a dusty interior. The old
  /// default of 0.15 read as a density is thick fog. Zero is off.
  final double strength;

  /// The air's albedo, or null for white — a tint on the light it scatters.
  /// The light's own colour and intensity come from the sun that casts the
  /// shadow, so a sunset's shafts are orange without being told.
  final vm.Vector3? color;

  /// Which way the air scatters: Henyey–Greenstein's g, from −1 (back
  /// towards the light) through 0 (every direction alike) to 1 (straight on).
  ///
  /// 0.6, the default, is forward scattering of the kind haze does: looking
  /// towards the sun the shafts are bright, and with it behind you they are
  /// about a sixtieth as bright, which is why a frame no longer washes out
  /// when the sun is at your back.
  final double anisotropy;

  LightShaftSettings copyWith({
    bool? enabled,
    int? steps,
    double? distance,
    double? strength,
    vm.Vector3? color,
    double? anisotropy,
  }) => LightShaftSettings(
    enabled: enabled ?? this.enabled,
    steps: steps ?? this.steps,
    distance: distance ?? this.distance,
    strength: strength ?? this.strength,
    color: color ?? this.color,
    anisotropy: anisotropy ?? this.anisotropy,
  );
}

/// Air with a thickness, lit by the sun and by the torches in it — `S4`.
///
/// **What [LightShaftSettings] does not.** The shafts add the sun's
/// in-scatter and leave the scene behind untouched; [FogSettings] dims the
/// scene towards one colour and knows about no light at all. This marches
/// each view ray through a medium whose density falls off with height, and at
/// every step asks the shadow map whether the sun reaches that point and the
/// view's light clusters which torches do. What comes out is the light the air
/// sends towards the eye *and* the share of the scene it lets through, so a
/// corridor of torches fills with a glow around each flame and the far wall
/// fades behind it.
///
/// **Marched at half resolution and brought up with the depth.** The four fog
/// texels nearest a pixel are weighed by how close the depth their rays
/// stopped at is to the pixel's own, so a halo behind a pillar stops at the
/// pillar's edge rather than bleeding a texel over it.
///
/// **The torches come from `L6`'s cells**, and only while
/// [RenderSettings.clusteredLights] is on and the scene has more lights than
/// a draw's eight slots — the case the cells are built for. Otherwise the fog
/// is lit by the sun and [ambient] alone. Point lights cast no shadow into
/// the air: the cube atlas is not consulted, so a torch's glow reaches
/// through the wall beside it.
///
/// **The sun is the shadow caster when there is one**, shadowed through the
/// cascades, and otherwise the first directional light, unshadowed. With
/// [LightShaftSettings] on as well the sun is scattered twice; the two are
/// alternatives rather than layers.
///
/// The step offset comes from the engine's noise: the fixed pattern without a
/// temporal resolve, a new slice of blue noise every frame with one, which the
/// history averages away.
final class VolumetricFogSettings {
  const VolumetricFogSettings({
    this.enabled = false,
    this.density = 0.02,
    this.heightFalloff = 0.0,
    this.baseHeight = 0.0,
    this.anisotropy = 0.3,
    this.steps = 24,
    this.distance = 40.0,
    this.color,
    this.ambient,
  });

  /// Off by default: two full-screen passes, one of them a march with a
  /// shadow lookup and a cell's lights at every step.
  final bool enabled;

  /// The air's extinction σ at [baseHeight], per metre. 0.02 keeps about a
  /// third of a wall fifty metres off; 0.2 is a smoky crypt. Zero is off.
  final double density;

  /// How fast the air thins with height, per metre: the density is
  /// `density · e^(−heightFalloff · (y − baseHeight))`. Nought is uniform
  /// air; 0.5 halves it about every metre and a half, the ground fog of a
  /// marsh.
  final double heightFalloff;

  /// The height at which the air is [density] thick, in world metres.
  final double baseHeight;

  /// Which way the air scatters: Henyey–Greenstein's g, from −1 through 0
  /// (every direction alike) to 1. 0.3 is a mild forward lobe, which makes a
  /// torch glow more when looked past than when looked away from.
  final double anisotropy;

  /// Samples along each view ray, at most sixty-four in the shader.
  final int steps;

  /// How far along the ray to march, in world metres. Past it the air stops,
  /// and the sky beyond keeps what the marched part let through.
  final double distance;

  /// The air's albedo, or null for white — a tint on every light it scatters.
  final vm.Vector3? color;

  /// Light reaching the air from every direction, in the units a light's
  /// colour times intensity has, or null for none. Without it fog in shadow
  /// only dims the scene; with a little, it reads as air.
  final vm.Vector3? ambient;

  VolumetricFogSettings copyWith({
    bool? enabled,
    double? density,
    double? heightFalloff,
    double? baseHeight,
    double? anisotropy,
    int? steps,
    double? distance,
    vm.Vector3? color,
    vm.Vector3? ambient,
  }) => VolumetricFogSettings(
    enabled: enabled ?? this.enabled,
    density: density ?? this.density,
    heightFalloff: heightFalloff ?? this.heightFalloff,
    baseHeight: baseHeight ?? this.baseHeight,
    anisotropy: anisotropy ?? this.anisotropy,
    steps: steps ?? this.steps,
    distance: distance ?? this.distance,
    color: color ?? this.color,
    ambient: ambient ?? this.ambient,
  );
}

/// Depth of field, from a lens rather than from a ramp — `gfx-34n`.
///
/// **Every number here is one a photographer already knows.** A focus
/// distance, a focal length and an f-number are what a lens is described by,
/// and the circle of confusion that follows from them is the thin-lens
/// formula rather than a curve chosen because it looked right. Open
/// [aperture] and the background softens by an amount somebody can predict
/// from the three numbers, which a strength slider between zero and one
/// cannot offer.
///
/// **The depth comes from the surface buffer's alpha**, which carries
/// distance along the view axis in metres. That is the same channel the
/// shafts read, and the reason the engine keeps it rather than depending on a
/// sampleable depth attachment: the formula wants a real distance, and a
/// window depth would make the same blur mean different things near and far.
///
/// Off by default, with defaults that are a no-op if it is switched on
/// blind — [focusDistance] is far enough and [aperture] narrow enough that
/// nothing in an ordinary scene leaves focus until somebody says so.
final class DepthOfFieldSettings {
  const DepthOfFieldSettings({
    this.enabled = false,
    this.focusDistance = 10.0,
    this.focalLength = 0.05,
    this.aperture = 8.0,
    this.samples = 24,
    this.maxRadius = 16.0,
    this.sensorWidth = 0.036,
  });

  /// Off by default: it is a full-screen gather of two dozen taps, and a scene
  /// either wants a lens or wants everything sharp.
  final bool enabled;

  /// What the lens is focused on, in world metres. Things at this distance
  /// image to a point; everything either side of it spreads.
  final double focusDistance;

  /// The focal length in metres — 0.05 is a fifty-millimetre lens.
  ///
  /// It enters the formula squared, so it is the strongest of the three: a
  /// long lens throws a background out of focus at an aperture where a wide
  /// one keeps it sharp, which is why a portrait is shot long.
  final double focalLength;

  /// The f-number. Eight is a landscape, 1.4 is a portrait wide open.
  ///
  /// Larger means a smaller circle, because it is a divisor — the direction
  /// is the one a photographer expects and the opposite of what a "blur
  /// amount" slider would do.
  final double aperture;

  /// Taps in the gather, on a spiral. Bounded at sixty-four in the shader, the
  /// rule every loop in this engine keeps.
  ///
  /// The spiral is why this is a number of taps rather than a kernel width: a
  /// square kernel makes a square bokeh, and the shape of an out-of-focus
  /// highlight is the one thing anybody looks at in this effect.
  final int samples;

  /// The largest circle the gather will draw, in pixels at the render
  /// resolution.
  ///
  /// A bound on the cost rather than on the optics: the formula is happy to
  /// ask for a circle a hundred pixels across at f/1.4 with a near focus, and
  /// the taps that would need are not there. Clamping shows as a background
  /// that stops getting softer, which is the failure worth having.
  final double maxRadius;

  /// How wide the sensor is, in metres. 0.036 is full-frame 35mm.
  ///
  /// **Without it a focal length in millimetres means nothing.** "Fifty
  /// millimetres" is only a normal lens beside a 36mm frame; on a phone
  /// sensor it is a telephoto. The circle of confusion comes out in metres on
  /// the sensor, and this is what turns those metres into pixels together
  /// with the frame's width — which is also why the blur does not change when
  /// the resolution does: a scene rendered twice as wide is the same
  /// photograph, larger.
  final double sensorWidth;

  DepthOfFieldSettings copyWith({
    bool? enabled,
    double? focusDistance,
    double? focalLength,
    double? aperture,
    int? samples,
    double? maxRadius,
    double? sensorWidth,
  }) => DepthOfFieldSettings(
    enabled: enabled ?? this.enabled,
    focusDistance: focusDistance ?? this.focusDistance,
    focalLength: focalLength ?? this.focalLength,
    aperture: aperture ?? this.aperture,
    samples: samples ?? this.samples,
    maxRadius: maxRadius ?? this.maxRadius,
    sensorWidth: sensorWidth ?? this.sensorWidth,
  );
}

/// Which viewport shading a frame is drawn with — `gfx-43n`, `44n`, `45n`.
///
/// **A final class with const instances rather than an enum**, the shape
/// `TonemapCurve` and `PassSkip` have and the one `tool/structure.dart`'s "an
/// enum in a published package is machinery or is not an enum" rule asks for:
/// the [code] is part of a uniform layout four backends read, so it is a
/// number this type owns rather than an ordinal the language happens to
/// assign.
final class ViewportShading {
  const ViewportShading._(this.name, this.code);

  /// The name it is written down as.
  final String name;

  /// What goes into `ShadeInfo.params.x`. Part of the shader contract.
  final double code;

  /// The lit picture, untouched — the default, and an exact no-op.
  static const ViewportShading off = ViewportShading._('off', 0.0);

  /// The world normal as colour, which is the mode the material swap in
  /// `apps/flutter3d_modeler` existed for.
  static const ViewportShading normals = ViewportShading._('normals', 1.0);

  /// One studio light over a neutral surface: a form with its albedo taken
  /// away, which is what a sculptor turns on to read shape.
  static const ViewportShading clay = ViewportShading._('clay', 2.0);

  /// A dark line where depth or normal steps — `gfx-44n`.
  static const ViewportShading outline = ViewportShading._('outline', 3.0);

  /// Ridges lit and creases darkened, from how fast the normal field turns —
  /// `gfx-45n`.
  static const ViewportShading curvature = ViewportShading._('curvature', 4.0);

  /// All of them, off first.
  static const List<ViewportShading> values = <ViewportShading>[
    off,
    normals,
    clay,
    outline,
    curvature,
  ];

  @override
  String toString() => 'ViewportShading.$name';
}

/// Shading read out of the surface buffer instead of out of the materials —
/// `gfx-43n`, `gfx-44n` and `gfx-45n`.
///
/// **What this replaces is a traversal, and that is the point.** A normals
/// view built by walking the subject and swapping every material has to
/// remember what it swapped and put it back; the modeller's own docstring
/// documents what happens when the remembering fails. The scene pass already
/// wrote a world normal and a view-axis depth into its second attachment, so
/// every mode here is arithmetic on a buffer that exists — nothing is
/// modified and there is nothing to restore.
///
/// **It costs the frame its multisampling**, and that is said here rather
/// than found later: reading the surface buffer attaches the second colour
/// attachment, attachments in one target must agree on sample count, so a
/// frame with a mode on is a frame the scene pass did not multisample.
/// `FrameResult.antiAliasing.msaaDeclined` reports it.
final class ViewportShadingSettings {
  const ViewportShadingSettings({
    this.mode = ViewportShading.off,
    this.amount = 1.0,
    this.ambient = 0.25,
    this.depthEdge = 0.05,
    this.normalEdge = 0.15,
    this.outlineWidth = 1.0,
    this.curvatureGain = 4.0,
    this.cavity = 1.0,
    this.lightDirection,
  });

  /// Which mode. [ViewportShading.off] is the default and an exact no-op.
  final ViewportShading mode;

  /// How much of the shaded result is mixed over the lit picture.
  ///
  /// One is the mode alone. Below one is the mode *over* the render, which is
  /// what an outline is usually wanted as — the shading a modeller was
  /// already looking at, with the edges drawn on top.
  final double amount;

  /// How much ambient sits under the studio light in [ViewportShading.clay].
  ///
  /// Not zero by default: clay with no ambient puts everything facing away
  /// from the light at black, and a sculptor reading a form needs the far
  /// side to have a shape too.
  final double ambient;

  /// How far apart in metres two depths must be to count as an edge.
  final double depthEdge;

  /// How far apart two normals must be, as one minus their dot product: 0.15
  /// is about thirty-two degrees.
  ///
  /// **Both thresholds, because either alone misses half the edges.** A depth
  /// step finds a silhouette and misses a crease in a flat wall; a normal
  /// step finds the crease and misses two surfaces at the same angle one
  /// behind the other.
  final double normalEdge;

  /// How wide the outline's neighbour taps reach, in pixels.
  final double outlineWidth;

  /// The gain on the curvature estimate, which is a screen-space divergence
  /// and therefore a small number before it is scaled.
  final double curvatureGain;

  /// How much of the concave half is darkened, 0 to 1 — the cavity in a
  /// cavity map.
  final double cavity;

  /// Which way the clay light points, or null for over the camera's shoulder.
  ///
  /// A direction rather than a position: clay is a studio light at infinity,
  /// so a distance would be a number with nothing to do.
  final vm.Vector3? lightDirection;

  ViewportShadingSettings copyWith({
    ViewportShading? mode,
    double? amount,
    double? ambient,
    double? depthEdge,
    double? normalEdge,
    double? outlineWidth,
    double? curvatureGain,
    double? cavity,
    vm.Vector3? lightDirection,
  }) => ViewportShadingSettings(
    mode: mode ?? this.mode,
    amount: amount ?? this.amount,
    ambient: ambient ?? this.ambient,
    depthEdge: depthEdge ?? this.depthEdge,
    normalEdge: normalEdge ?? this.normalEdge,
    outlineWidth: outlineWidth ?? this.outlineWidth,
    curvatureGain: curvatureGain ?? this.curvatureGain,
    cavity: cavity ?? this.cavity,
    lightDirection: lightDirection ?? this.lightDirection,
  );
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
    this.batchIdenticalDraws = false,
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
    this.showVelocity = false,
    this.showPointShadowDebug = false,
    this.reflections = const ReflectionSettings(),
    this.ambientOcclusion = const AmbientOcclusionSettings(),
    this.contactShadows = const ContactShadowSettings(),
    this.fog = const FogSettings(),
    this.sky = const SkySettings(),
    this.anisotropy = 1,
    this.lightFadeBand = 0.0,
    this.autoExposure = const AutoExposureSettings(),
    this.xray = const XraySettings(),
    this.disabledPasses = const <String>{},
    this.renderScale = 1.0,
    this.spatialUpscale = const SpatialUpscaleSettings(),
    this.localExposure = const LocalExposureSettings(),
    this.outputTransform = OutputTransform.sdr,
    this.frameWorkBudget = 0,
    this.energyCompensation = false,
    this.clusteredLights = false,
    this.lightShafts = const LightShaftSettings(),
    this.volumetricFog = const VolumetricFogSettings(),
    this.depthOfField = const DepthOfFieldSettings(),
    this.viewportShading = const ViewportShadingSettings(),
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

  /// Whether a run of identical opaque draws is merged into one instanced call
  /// — `gfx-67n`.
  ///
  /// A hundred `MeshNode`s sharing one geometry and one material are a hundred
  /// pipeline binds, six hundred uniform writes and a hundred draws. The sort
  /// already groups by material, so the run is there to be found: the scene
  /// pass walks the sorted opaque half, collects each run whose members share a
  /// mesh, a material, a mirroring and a reflection probe and carry no skeleton,
  /// no morph and no lightmap, and draws it through the instanced stage with
  /// each member's world transform as an instance.
  ///
  /// **Off by default, and the reason is what cannot be measured here rather
  /// than what was.** The two vertex stages compute different expressions: a
  /// plain mesh clips with `(viewProjection * model) * position` and a batch
  /// with `viewProjection * (instance * position)`, because the instance
  /// transform is where the node's own matrix went, and the normal takes a
  /// `normalize` on the instanced side that the plain side does not. On the
  /// software rasteriser, which computes in Dart doubles, both carry to the same
  /// eight-bit answer — `auto_batch_test.dart` holds a hundred cubes, turned and
  /// scaled, to byte equality. Impeller, WebGL and WebGPU compute in 32-bit
  /// floats, where those expressions have far less room before they part, and
  /// nothing headless can run them. So the forty-four goldens keep the frame
  /// they have, and an application that wants the draw calls back asks.
  ///
  /// Shadows and picking are unaffected: both walk the scene themselves and
  /// still draw a node at a time.
  final bool batchIdenticalDraws;

  /// How many identical draws it takes before merging them is worth a pipeline
  /// switch on either side of the batch.
  ///
  /// Four rather than two, because a batch costs the instanced pipeline coming
  /// in and the plain one going out, and two draws do not pay for that.
  static const int batchRunMinimum = 4;

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

  /// The short march toward the light — `gfx-76n`.
  final ContactShadowSettings contactShadows;

  /// `gfx-33n`'s volumetric shafts through the directional shadow map.
  final LightShaftSettings lightShafts;

  /// `S4`'s fog: a medium with a height, lit by the sun and the clustered
  /// lights, marched at half resolution.
  final VolumetricFogSettings volumetricFog;

  /// `gfx-34n`'s lens, which decides what is sharp and by how much the rest
  /// is not.
  final DepthOfFieldSettings depthOfField;

  /// `gfx-43n`/`44n`/`45n`'s shading read out of the surface buffer rather
  /// than out of the materials.
  final ViewportShadingSettings viewportShading;

  final FogSettings fog;

  /// What is behind everything, when there is anything.
  ///
  /// Off by default: a sky changes every pixel a frame did not otherwise draw,
  /// and sixty golden images are recorded against there being none.
  final SkySettings sky;

  /// Silhouettes of the nodes on a layer, drawn where something hides them.
  final XraySettings xray;

  /// How much of the asked-for resolution the frame is actually drawn at —
  /// `gfx-35n`. 1 is all of it, and is the default.
  ///
  /// **The one missing capability class that is not an effect.** Every other
  /// knob in this class trades a look for time; this trades resolution for
  /// it, which is the lever an application reaches for when a frame will not
  /// fit in its budget and everything else is already off — the lever most
  /// engines reach for before they start switching effects off, and this
  /// engine had no way to.
  ///
  /// Applied at the top of `Renderer.render`, so it reaches everything: the
  /// scene target, the surface buffer, the occlusion, the bloom chain and the
  /// composite are all sized from it. At 0.75 a frame costs 0.5625 of the
  /// pixels, because both axes shrink.
  ///
  /// **What comes back is the smaller texture, not an upscaled one.**
  /// `FrameResult.frame` is what a presenter stretches over its widget, and
  /// it already stretches — so an upscale pass here would be a full-screen
  /// draw to do again what the presenter does for nothing. A caller reading
  /// pixels back gets the size it was drawn at, which is the honest answer
  /// and the one a measurement wants.
  final double renderScale;

  /// An edge-adaptive upscale of the finished picture to the asked-for size
  /// — `R5`. Off by default, which is [renderScale]'s smaller texture as
  /// before; takes effect only below a scale of one with the temporal resolve
  /// off, since the resolve already reconstructs the full size.
  final SpatialUpscaleSettings spatialUpscale;

  /// Each place of the frame at the exposure that shows it best — `R7`. Off
  /// by default.
  final LocalExposureSettings localExposure;

  /// What the finished frame is encoded for — `R9`. [OutputTransform.sdr],
  /// the default, is the tone-mapped 8-bit frame every earlier version drew.
  /// [OutputTransform.extendedSrgb] takes effect only on a device whose
  /// `GraphicsDevice.hdrOutputFormats` is not empty, and elsewhere draws the
  /// SDR frame.
  final OutputTransform outputTransform;

  /// Microseconds a frame may spend on work that can wait — `N3`: irradiance
  /// probe updates and point-shadow faces share it, and what does not fit
  /// waits for the next frame. Nought, the default, is no limit, which is
  /// every frame before this existed. See `FrameWorkBudget`.
  final int frameWorkBudget;

  /// Puts back the light single-scattering GGX loses on rough surfaces —
  /// `L1`. Off by default.
  ///
  /// A microfacet model counts one bounce off the facets and nothing after
  /// it, so the rougher a metal, the more of its reflection is simply
  /// missing: a rough gold sphere comes out darker than a polished one,
  /// which no real gold does. On, the metal-rough model scales its direct
  /// specular by `1 + f0·(1/E − 1)`, with E the albedo the split sum already
  /// computes, and adds Fdez-Agüera's multiple-scattering term to the
  /// environment's. Dielectrics barely move; rough metals brighten.
  final bool energyCompensation;

  /// Lights each fragment by the lights that reach its part of the view
  /// rather than by the ones ranked against its whole draw — `L6`. Off by
  /// default.
  ///
  /// A draw is handed eight slots and a tail of twenty-four, ranked against
  /// its bounding sphere, so a floor that spans the map is lit by the
  /// thirty-two brightest lights anywhere on it. On, the view is cut into
  /// 16 × 9 × 24 cells each frame with the lights whose range reaches each,
  /// and the tail comes from the fragment's own cell. The eight slots stay,
  /// and with them the only shadowed lights. Takes effect only when a scene
  /// has more lights than the slots and no light channels are in use.
  final bool clusteredLights;

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

  /// Shows the velocity buffer instead of the lit image — `R1`. Red and green
  /// are the motion in UV units, now minus then, through the output encoding
  /// the way every raw view goes: a still frame is black, and only motion
  /// down and to the right shows, since a negative channel has nothing to
  /// light. A test that needs both signs reads the resource itself. Only while
  /// temporal anti-aliasing is on, which is when there is a buffer; off, the
  /// lit image is shown.
  final bool showVelocity;

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
    bool? batchIdenticalDraws,
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
    bool? showVelocity,
    bool? showPointShadowDebug,
    ReflectionSettings? reflections,
    AmbientOcclusionSettings? ambientOcclusion,
    ContactShadowSettings? contactShadows,
    FogSettings? fog,
    SkySettings? sky,
    int? anisotropy,
    double? lightFadeBand,
    AutoExposureSettings? autoExposure,
    XraySettings? xray,
    Set<String>? disabledPasses,
    double? renderScale,
    SpatialUpscaleSettings? spatialUpscale,
    LocalExposureSettings? localExposure,
    OutputTransform? outputTransform,
    int? frameWorkBudget,
    bool? energyCompensation,
    bool? clusteredLights,
    LightShaftSettings? lightShafts,
    VolumetricFogSettings? volumetricFog,
    DepthOfFieldSettings? depthOfField,
    ViewportShadingSettings? viewportShading,
  }) => RenderSettings(
    specular: specular ?? this.specular,
    exposure: exposure ?? this.exposure,
    wireframe: wireframe ?? this.wireframe,
    backfaceCulling: backfaceCulling ?? this.backfaceCulling,
    batchIdenticalDraws: batchIdenticalDraws ?? this.batchIdenticalDraws,
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
    showVelocity: showVelocity ?? this.showVelocity,
    showPointShadowDebug: showPointShadowDebug ?? this.showPointShadowDebug,
    reflections: reflections ?? this.reflections,
    ambientOcclusion: ambientOcclusion ?? this.ambientOcclusion,
    contactShadows: contactShadows ?? this.contactShadows,
    fog: fog ?? this.fog,
    sky: sky ?? this.sky,
    anisotropy: anisotropy ?? this.anisotropy,
    lightFadeBand: lightFadeBand ?? this.lightFadeBand,
    autoExposure: autoExposure ?? this.autoExposure,
    xray: xray ?? this.xray,
    disabledPasses: disabledPasses ?? this.disabledPasses,
    renderScale: renderScale ?? this.renderScale,
    spatialUpscale: spatialUpscale ?? this.spatialUpscale,
    localExposure: localExposure ?? this.localExposure,
    outputTransform: outputTransform ?? this.outputTransform,
    frameWorkBudget: frameWorkBudget ?? this.frameWorkBudget,
    energyCompensation: energyCompensation ?? this.energyCompensation,
    clusteredLights: clusteredLights ?? this.clusteredLights,
    lightShafts: lightShafts ?? this.lightShafts,
    volumetricFog: volumetricFog ?? this.volumetricFog,
    depthOfField: depthOfField ?? this.depthOfField,
    viewportShading: viewportShading ?? this.viewportShading,
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
  /// **`gfx-22n` gave the meter a per-view mode and this method leaves it
  /// off**, which is a decision rather than an omission: per-view metering
  /// exists for split screen, where two players in two rooms metered together
  /// means the darker room is the one nobody can see. A stereo pair is the
  /// case it is wrong for, and it is off by default, so a pair that never asks
  /// gets the right answer without this method having to take it away.
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

  /// Every pass the engine registers, in the order it registers them —
  /// `gfx-19n`.
  ///
  /// **The key space [disabledPasses] is typed against, published as data
  /// rather than described in prose.** A name here is what a caller types,
  /// character for character: `'point shadows (static)'` carries spaces and
  /// parentheses, `'antialias'` is not spelled `fxaa`, and the graph rejects
  /// anything else rather than silently changing nothing. Prose cannot be
  /// typed into a set, and a document that drifted from the strings would be
  /// worse than no document — which is why `pass_order_test.dart` compiles a
  /// frame and compares.
  ///
  /// The order is the *version chain*: each pass reads what the ones before
  /// it left. That is why it is a list rather than a set, and why reading it
  /// answers questions the names alone cannot — occlusion is registered
  /// before bloom, so a glow is taken from a picture that is already
  /// occluded.
  ///
  /// **Not every registered pass is here, and the exception is stated rather
  /// than hidden.** A reflection probe's name carries its index —
  /// `'reflection probe 0'` — so the set of them is a property of the scene
  /// and not of the engine. [probePassName] builds one. Everything else is a
  /// fixed string.
  ///
  /// Three of these cannot be switched off at all; ask [undisablePasses].
  static const List<String> passOrder = <String>[
    'point shadows (static)',
    'point shadows',
    'directional shadows',
    // `S2`: the directional map as blurred moments, for the `evsm` filter.
    'shadow moments',
    // `L4`: the irradiance field's probes, a few a frame.
    'irradiance update',
    // Reflection probes are registered here, one per probe in the scene, and
    // are named by index rather than by a constant — see [probePassName].
    'scene',
    'object ids',
    'reflections',
    'luminance',
    'ssao',
    'ssao blur',
    // Beside the occlusion because it reads the same buffer and its result is
    // applied in the same place — `gfx-76n`.
    'contact shadows',
    // `R1`: the motion of every pixel, and then of what moved over it.
    'camera velocity',
    'object velocity',
    // `R3`: the two noisy effects carried into their own histories.
    'ssao history',
    'contact shadow history',
    // `S4`: before the shafts, so the air the fog dims is not the shafts'
    // own light a second time.
    'volumetric fog',
    'light shafts',
    'depth of field',
    // `R2`: the frames blended into one, before the glow is taken from it.
    'temporal resolve',
    // `R7`: measured on the resolved picture, applied in the composite.
    'local exposure',
    'bloom',
    'composite',
    // `R5`: the finished picture brought up to the asked-for size, before
    // the sharpening that follows it.
    'spatial upscale',
    'antialias',
    // `gfx-43n`/`44n`/`45n`, last: a mode here is about the finished picture,
    // so it runs after the tone map and after the edges are smoothed.
    'viewport shading',
  ];

  /// What a reflection probe's pass is called, for probe [index].
  ///
  /// A function rather than a list entry because the count belongs to the
  /// scene: a level with nine probes registers nine of these, and an engine
  /// that published a fixed set of names would be publishing a guess about
  /// somebody else's world.
  static String probePassName(int index) => 'reflection probe $index';

  /// The three names [disabledPasses] refuses — `gfx-19n` publishing what the
  /// graph already enforced.
  ///
  /// Switching any of them off would leave no frame at all, so the graph
  /// throws rather than drawing nothing. Published so a caller building a set
  /// out of [passOrder] can subtract them instead of discovering the rule
  /// from an exception.
  static const Set<String> undisablePasses = <String>{
    'scene',
    'composite',
    'object ids',
  };

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
    // Multiplied into the ambient term in the composite beside the occlusion,
    // so it moves a measured pixel exactly as `ssao` does.
    'contact shadows',
    'reflections',
    'spatial upscale',
    'local exposure',
    'antialias',
    'luminance',
    // Both of these are off by default, so a measurement frame taken from
    // stock settings never had them. They are named all the same, because a
    // caller who switched a lens on and then asked for a measurement would
    // otherwise be handed a photograph of the numbers rather than the
    // numbers: a shaft adds light the material never wrote, and a lens
    // averages a neighbourhood of values that each meant something on their
    // own.
    'light shafts',
    'volumetric fog',
    'depth of field',
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

  /// AgX: the gamut rotation, the log sigmoid, and back to linear — see
  /// `composite.frag`.
  ///
  /// Until 0.7.4 this was the bare sigmoid, and its display-encoded output
  /// went through the sRGB encode a second time: 18% grey landed at 187/255
  /// rather than 128/255, and saturated colours came out pastel.
  static const TonemapCurve agx = TonemapCurve._('agx', 3.0);

  /// Reinhard, extended so white reaches white.
  static const TonemapCurve reinhard = TonemapCurve._('reinhard', 4.0);

  /// The same transform as [agx] — `gfx-26n`.
  ///
  /// Added as the rotated variant while [agx] was the bare sigmoid; now that
  /// [agx] is the whole of AgX the two draw the same picture. Kept so a
  /// setting that names it keeps working.
  @Deprecated('Use TonemapCurve.agx, which is now the full AgX transform.')
  static const TonemapCurve agxFull = TonemapCurve._('agxFull', 5.0);

  /// The ACES 2.0 tonescale through the engine's display transform table —
  /// `L2`. See `EngineTables.aces2Display` for what the table holds and does
  /// not: the SDR tonescale applied with the hue held, not the reference
  /// transform's appearance-model gamut work.
  ///
  /// Code 6 is "read a display transform", and this curve is the table the
  /// engine ships; [LookSettings.displayTransform] puts another in its place.
  static const TonemapCurve aces2 = TonemapCurve._('aces2', 6.0);

  /// All of them, in the order their codes run.
  static const List<TonemapCurve> values = <TonemapCurve>[
    neutral,
    aces,
    agx,
    reinhard,
    agxFull,
    aces2,
  ];

  @override
  String toString() => 'TonemapCurve.$name';
}

/// A display transform read in place of the tone curve — `L2`.
///
/// **Scene-referred in, display-linear out**, in the colour table's strip
/// shape (N slices of N × N, blue picking the slice) but float, and indexed
/// through a log2 shaper: entry `i` of N holds the output for the input
/// `0.18 · 2^(−10 + 16 · i / (N − 1))`. So −10 stops below mid grey to +6
/// above it are covered, which is where a real output transform does all of
/// its work.
///
/// Whatever a tool can bake into that shape goes here: the ACES 2.0
/// reference output transform through OCIO, a studio's own, a filmic curve.
/// Applied after exposure and before the grade, exactly where a tone curve
/// is.
final class DisplayTransform {
  const DisplayTransform({required this.texture, required this.size});

  /// The strip, `size²` × `size`, in a float format the device samples
  /// filtered.
  final TextureHandle texture;

  /// Entries per axis, N.
  final int size;
}

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
final class LookSettings {
  const LookSettings({
    this.contrast = 1.0,
    this.saturation = 1.0,
    this.temperature = 0.0,
    this.vignette = 0.0,
    this.vignetteRoundness = 1.0,
    this.grain = 0.0,
    this.chromaticAberration = 0.0,
    this.dither = 1.0 / 255.0,
    this.lift,
    this.gamma,
    this.gain,
    this.whiteBalance = 0.0,
    this.tint = 0.0,
    this.lut,
    this.lutStrength = 1.0,
    this.displayTransform,
  });

  /// Pivoted about mid grey, so raising it does not also raise exposure.
  ///
  /// A power about 0.18, linear light's mid grey, since 0.7.4: it pivoted on
  /// 0.5, which in linear light is a bright highlight, so a contrast of 1.2
  /// also took about a stop off the picture.
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

  /// Where black is **lifted to**, per channel, so the shadows move and white
  /// stays — `gfx-27n`. Null is neutral, the same as zero. Applied as
  /// `c * (1 - lift) + lift`; until 0.7.4 it was a plain add, which moved
  /// white to one plus the lift and clipped it.
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
  /// `1 / 255` is one 8-bit step, and the default since 0.7.4; 0 is off,
  /// exactly. It was off by default so the goldens would not move, and every
  /// bloom around a small bright light came out in coloured rings — one per
  /// 8-bit code, and at a different radius for each channel. The goldens were
  /// recorded again with it on.
  ///
  /// **Centred**, so a flat colour stays the colour it was: only where a
  /// gradient's bands fall changes. That is also why [isNeutral] does not ask
  /// about it.
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

  /// A display transform read instead of the tone curve — `L2`. Null uses
  /// the curve, as always; set, it wins over whichever curve is chosen, and
  /// `RenderSettings.tonemap` off still turns it off with the rest.
  final DisplayTransform? displayTransform;

  /// Whether [lut] will actually be sampled this frame.
  bool get gradesThroughLut => lut != null && lutStrength > 0.0;

  /// Whether any of this changes the picture at all.
  ///
  /// For a caller or a test to say what "off" means in one place rather than
  /// fifteen. Every field that changes a colour is asked, including the grade
  /// `gfx-27n` added: a look with only a lift in it used to report itself
  /// neutral. [vignetteRoundness] is not asked, because it shapes a vignette
  /// and does nothing while [vignette] is zero, and neither is [dither],
  /// which is centred and moves where a gradient's bands fall rather than
  /// what colour anything is — and which is on by default.
  bool get isNeutral =>
      contrast == 1.0 &&
      saturation == 1.0 &&
      temperature == 0.0 &&
      vignette == 0.0 &&
      grain == 0.0 &&
      chromaticAberration == 0.0 &&
      whiteBalance == 0.0 &&
      tint == 0.0 &&
      _isNeutralTriple(lift, 0.0) &&
      _isNeutralTriple(gamma, 1.0) &&
      _isNeutralTriple(gain, 1.0) &&
      !gradesThroughLut;

  /// Null, or all three components at [neutral].
  static bool _isNeutralTriple(vm.Vector3? value, double neutral) =>
      value == null ||
      (value.x == neutral && value.y == neutral && value.z == neutral);

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
    DisplayTransform? displayTransform,
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
    displayTransform: displayTransform ?? this.displayTransform,
  );
}

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
final class AntiAliasSettings {
  const AntiAliasSettings({
    this.enabled = false,
    this.contrastThreshold = 0.125,
    this.blend = 0.75,
    this.sharpen = 0.0,
    this.temporal = const TemporalSettings(),
  });

  final bool enabled;

  /// Anti-aliasing across frames — `R1`, `R2`. Independent of [enabled]: the
  /// temporal resolve and the edge pass can run together, and the resolve is
  /// the one that replaces multisampling.
  final TemporalSettings temporal;

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
    TemporalSettings? temporal,
  }) => AntiAliasSettings(
    enabled: enabled ?? this.enabled,
    contrastThreshold: contrastThreshold ?? this.contrastThreshold,
    blend: blend ?? this.blend,
    sharpen: sharpen ?? this.sharpen,
    temporal: temporal ?? this.temporal,
  );
}

/// Edges smoothed across frames — `R1`, `R2`.
///
/// **The scene is drawn a fraction of a pixel off each frame**, along a
/// Halton(2, 3) sequence of [sequenceLength] offsets, and a resolve pass
/// blends each frame into the history of the ones before it, reprojected
/// through the motion the velocity passes measured. Sixteen frames of a still
/// picture are sixteen samples of every pixel, which is what multisampling
/// buys with memory and this buys with time.
///
/// **It turns multisampling off**, because the velocity pass reads the
/// surface buffer and the surface buffer cannot be multisampled; the frame
/// result says so through `EffectiveAntiAliasing.temporal`.
///
/// Off by default: a still frame on its own is as sharp as without it, but a
/// frame one draws once — a golden, a thumbnail — would come out a fraction
/// of a pixel off and never be resolved.
final class TemporalSettings {
  const TemporalSettings({
    this.enabled = false,
    this.sequenceLength = 16,
    this.historyWeight = 0.9,
    this.sharpen = 0.25,
  });

  final bool enabled;

  /// How many offsets the jitter cycles through before it repeats. Sixteen
  /// covers a pixel evenly enough that a still frame converges to within a
  /// grey level of its 16× supersampled self.
  final int sequenceLength;

  /// How much of each resolved pixel is history, from nought to one. Higher
  /// is smoother and slower to follow change.
  final double historyWeight;

  /// Robust contrast-adaptive sharpening after the resolve, from nought to
  /// one, to put back the softness a history always adds.
  final double sharpen;

  TemporalSettings copyWith({
    bool? enabled,
    int? sequenceLength,
    double? historyWeight,
    double? sharpen,
  }) => TemporalSettings(
    enabled: enabled ?? this.enabled,
    sequenceLength: sequenceLength ?? this.sequenceLength,
    historyWeight: historyWeight ?? this.historyWeight,
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

/// How much of the frame's light spills into a glow.
final class BloomSettings {
  const BloomSettings({
    this.enabled = true,
    this.threshold = 1.0,
    this.knee = 0.5,
    this.intensity = 0.06,
    this.levels = 5,
    this.filterRadius = 1.0,
    this.referenceHeight = 0,
    this.halation = 0.0,
    this.scatter = 1.0,
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

  /// How red the broad part of the glow goes — `gfx-30n`. 0 is off exactly,
  /// and is the default.
  ///
  /// **What it is, and why it is not a tint on the whole bloom.** On film the
  /// halo around a highlight is warm: light that gets through the emulsion
  /// scatters off the backing and comes back, and the red layer sits deepest
  /// so it catches the most of it. What makes that read as light rather than
  /// as a colour cast is that only the *wide* part is warm — the tight core
  /// around the highlight stays the colour of the highlight.
  ///
  /// So this is applied per level of the chain, on the way back up, where the
  /// levels still exist as separate pictures. The composite sees one glow and
  /// could not tell the core from the skirt.
  ///
  /// It costs nothing new: the pyramid is the expensive half and bloom has
  /// already paid for it. 0.5 is visible as warmth without reading as a
  /// filter.
  ///
  /// **Each level warmed once, since 0.7.4.** On the way up a level already
  /// holds every level below it, so warming each one compounded: at 0.5 over
  /// five levels the widest came out with red at 1.78 and blue at 0.63 rather
  /// than the 1.25 and 0.83 promised, and the core was not neutral. Each step
  /// now carries only the ratio between its warmth and the one above.
  ///
  /// Read as between 0 and 2.5: past that the blue weight of the widest level
  /// would reach zero and then go negative.
  final double halation;

  /// How much each level of the chain weighs against the one above it —
  /// `scatter` to the power of the level, level zero at one.
  ///
  /// **One, the default, is every level at full weight**, which is what this
  /// bloom has always been: five levels sum to five times the energy that
  /// passed the threshold, and the widest level, a thirty-second of the frame,
  /// throws a skirt a hundred and fifty pixels round a small lamp. Below one
  /// the wide levels fade and the glow tightens: Godot's default weights fall
  /// off roughly like 0.6 to 0.7, Unity's `scatter` is the same idea. The
  /// default stays one so every frame recorded before this is where it was.
  /// A negative value is read as zero.
  final double scatter;

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
    double? halation,
    double? scatter,
  }) => BloomSettings(
    enabled: enabled ?? this.enabled,
    threshold: threshold ?? this.threshold,
    knee: knee ?? this.knee,
    intensity: intensity ?? this.intensity,
    levels: levels ?? this.levels,
    filterRadius: filterRadius ?? this.filterRadius,
    referenceHeight: referenceHeight ?? this.referenceHeight,
    halation: halation ?? this.halation,
    scatter: scatter ?? this.scatter,
  );
}
