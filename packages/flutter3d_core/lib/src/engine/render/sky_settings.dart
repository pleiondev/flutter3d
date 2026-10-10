/// The sky as a property of the frame.
///
/// A setting rather than an object in the scene, because that is what it is:
/// nothing about a sky belongs to a place in the world, it has no transform,
/// and every camera looking out of the same world sees the same one. It is
/// drawn as a single full-screen triangle inside the scene pass, between the
/// opaque half of the render list and the transparent half — after the opaque
/// half so that every pixel already covered by geometry fails the depth test
/// before the sky's fragment stage runs, and before the transparent half so
/// that glass has something behind it to blend with.
///
/// **Off by default**, and that is what keeps sixty recorded golden images
/// valid: with [enabled] false the renderer emits nothing at all, not a single
/// state call, and every frame this engine ever drew is unchanged.
///
/// **On, it is the physical sky unless it was coloured** — `P5`. A sky
/// switched on with no [SkySettings.zenith], `horizon`, `nadir` or `sunColor`
/// scatters the sun through `const PhysicalSky()`; one given any of those
/// colours draws the gradient it was given. See
/// [SkySettings.resolvedPhysical].
///
/// The alternative in this repository is a painted dome (`SkyDome` in
/// `scene/sky.dart`), which needs no shader and works today. What this buys
/// over it: a sun disc — analytic, so its angular radius is a number rather
/// than a tessellation — no interaction with fog, nothing written into the
/// surface buffer, and no geometry to keep out of the shadow bounds. What the
/// dome still buys: a different sky per `RenderView`, which a frame-wide
/// setting cannot express.
///
/// **Colours are linear and scene-referred.** They are multiplied by
/// `RenderSettings.exposure` and pass through the tone curve like everything
/// else, so they are not the numbers an eyedropper reads off a screenshot —
/// unlike `RenderView.clearColorSrgb`, which the renderer decodes from sRGB. The
/// first sky anybody writes will look too bright, and it will look wrong in a
/// way that reads as a shader bug rather than as a units mismatch.
library;

import 'dart:math' as math;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show LinearColor;
import 'package:vector_math/vector_math.dart';

import 'engine_light_units.dart';
import 'physical_sky.dart';
import 'shadow_settings.dart' show ShadowSettings;

/// What the sky looks like, and whether there is one.
final class SkySettings {
  const SkySettings({
    this.enabled = false,
    this.zenith,
    this.horizon,
    this.nadir,
    this.directionToSun,
    this.sunColor,
    this.glowExponent = 6.0,
    this.glowStrength = 0.3,
    this.sunAngularRadius = ShadowSettings.sunAngularRadius,
    this.sunSoftness = 0.35 * math.pi / 180.0,
    this.sunIntensity = 0.0,
    this.cubemap,
    this.tint,
    this.physical,
  });

  /// Whether to draw at all. False emits nothing — see the library docstring.
  final bool enabled;

  // Nullable with a `resolved` accessor beside each. Null has a meaning on
  // the four colours below: with all of them null and no [physical], the sky
  // is the default air rather than the gradient — see [resolvedPhysical]. So
  // a default cannot simply be written in the parameter list, even though a
  // `LinearColor` is const. [directionToSun] is a `Vector3`, which has no
  // const constructor, and keeps the same shape for that reason.

  /// The sky straight up, for the gradient. Null takes [resolvedZenith];
  /// set, it asks for the gradient over the default air.
  final LinearColor? zenith;

  /// The sky level with the horizon, for the gradient. Null takes
  /// [resolvedHorizon]; set, it asks for the gradient, as [zenith] does.
  final LinearColor? horizon;

  /// The sky straight down, for the gradient. Null takes [resolvedNadir];
  /// set, it asks for the gradient, as [zenith] does.
  ///
  /// Not the ground: it is what fills the frame when the camera looks down at
  /// nothing, which is haze, and haze is darker than the sky above it.
  final LinearColor? nadir;

  /// A unit vector pointing **at** the sun.
  ///
  /// The other way from a directional light's own direction, which is where the
  /// light goes. Normalised on the way to the shader, so a caller may pass any
  /// length.
  final Vector3? directionToSun;

  /// The sun's own colour, used by both the lobe and the disc of the
  /// gradient. Set, it asks for the gradient, as [zenith] does: the air
  /// colours its own sun.
  final LinearColor? sunColor;

  LinearColor get resolvedZenith => zenith ?? _defaultZenith;
  LinearColor get resolvedHorizon => horizon ?? _defaultHorizon;
  LinearColor get resolvedNadir => nadir ?? _defaultNadir;
  Vector3 get resolvedDirectionToSun =>
      directionToSun ?? _defaultDirectionToSun;
  LinearColor get resolvedSunColor => sunColor ?? _defaultSunColor;

  static const LinearColor _defaultZenith = LinearColor(0.10, 0.22, 0.52);
  static const LinearColor _defaultHorizon = LinearColor(0.42, 0.50, 0.62);
  static const LinearColor _defaultNadir = LinearColor(0.06, 0.06, 0.07);
  static const LinearColor _defaultSunColor = LinearColor(1.0, 0.95, 0.86);

  // A getter rather than `static final`: a `Vector3` is mutable, so a shared
  // one is a global variable that looks like a constant — and this is handed
  // straight to a caller's settings object, which is free to scale it.
  static Vector3 get _defaultDirectionToSun => Vector3(0.34, 0.56, 0.76);

  /// The wide scattering lobe around the sun: how tight, and how bright.
  /// A unitless exponent on the cosine of the angle to the sun.
  final double glowExponent;

  /// A unitless multiplier on the sun's colour at the lobe's peak.
  final double glowStrength;

  /// The disc's angular radius, in radians, and the width of its soft edge
  /// beyond that, in radians too. The default is the real sun's radius,
  /// 0.2666° ([ShadowSettings.sunAngularRadius], the one the soft shadows
  /// use); before 1.0-rc.1 it was 0.53°, which is the sun's diameter.
  ///
  /// [sunIntensity] is zero by default, which means no disc: a sky with a sun
  /// in it needs the sun to agree with the light in the scene, and a disc drawn
  /// where no light comes from is worse than none. It is free to be far above
  /// the scene's own light — the target is HDR, and a sun that cannot blow
  /// out is a sun bloom has nothing to find.
  final double sunAngularRadius;

  /// In radians.
  final double sunSoftness;

  /// How bright the disc is, in **lux** since 1.0: the illuminance whose
  /// white Lambertian surface shows the disc's luminance, `E/π` nits — the
  /// same unit as `Atmosphere.sunIntensity` and a directional light's
  /// intensity. Before 1.0 it was the engine's own unit; multiply such a
  /// number by `Photometric.legacyUnit`. Zero, the default, draws no disc.
  final double sunIntensity;

  /// A cube map to sample instead of evaluating the gradient.
  ///
  /// When this is set the gradient, the lobe and the disc are all ignored — a
  /// photographed sky already has a sun in it, and adding a second one is the
  /// mistake this would otherwise invite. Everything else on this class stays
  /// meaningful for [sample], which is what a fog colour or a light picked from
  /// the sky is built on, and which cannot read a texture.
  ///
  /// Build one with `GraphicsDevice.createCubeTextureFromPixels`, whose
  /// docstring carries the face order. Ask `supportsCubeTextures` first: a
  /// device that cannot make one leaves this null and the procedural sky —
  /// the air or the gradient, see [resolvedPhysical] — is what draws, which is
  /// why the textured sky is an option on top of it rather than a replacement
  /// for it.
  final TextureHandle? cubemap;

  /// Multiplied into the cube's own colour, so one cube can serve more than one
  /// hour of the day. Ignored when there is no [cubemap].
  final LinearColor? tint;

  LinearColor get resolvedTint => tint ?? LinearColor.white;

  /// The air to scatter the sun through instead of evaluating the gradient —
  /// `P5`. What draws is [resolvedPhysical], not this field: null takes the
  /// default air, `const PhysicalSky()`, unless the caller coloured the sky.
  ///
  /// When there is air the colours of the sky come from it and from where the
  /// sun is: [zenith], [horizon], [nadir], [sunColor], [glowExponent] and
  /// [glowStrength] are not read. [directionToSun] places the sun, and the
  /// disc keeps its size, softness and [sunIntensity], drawn white and dimmed
  /// by the air in front of it — so it reddens towards the horizon by itself,
  /// and is gone below it. Stars come out as the sun goes down; see
  /// [PhysicalSky.starBrightness].
  ///
  /// A [cubemap] still wins: a photographed sky is a sky somebody chose.
  ///
  /// [sample] answers from the same model, so an environment map built from
  /// the sky, a fog colour picked off its horizon and the ambient the renderer
  /// takes from it all follow the sun too. The stars are the one part [sample]
  /// leaves out: an environment map thirty-two texels a side would turn each
  /// into a bright texel somewhere it does not belong.
  ///
  /// **It costs more than the gradient.** Each pixel of sky marches sixteen
  /// samples along the view ray and eight towards the sun from each, and there
  /// is no precomputed table yet to turn that into a texture read; on a phone
  /// that fills the frame with sky, the gradient is the cheaper choice.
  final PhysicalSky? physical;

  /// The air the sky is drawn through, or null for the gradient.
  ///
  /// [physical] if it is set. Otherwise the default air, `const
  /// PhysicalSky()`, when none of [zenith], [horizon], [nadir] and [sunColor]
  /// is set — a sky nobody coloured is a physical one — and null, the
  /// gradient, when any of them is: a caller who wrote gradient colours keeps
  /// the gradient they asked for. A [cubemap] wins over either, which the
  /// readers of this check first.
  PhysicalSky? get resolvedPhysical =>
      physical ??
      (zenith == null && horizon == null && nadir == null && sunColor == null
          ? const PhysicalSky()
          : null);

  /// The colour of the sky in [direction], on the CPU.
  ///
  /// The same arithmetic the shader runs, for the things that cannot ask the
  /// GPU: a fog colour that has to match the horizon, a light picked from the
  /// sky, and the test that keeps the two transcriptions of this model honest.
  ///
  /// [direction] need not be normalised.
  Vector3 sample(Vector3 direction) {
    final air = resolvedPhysical;
    if (air != null) return _samplePhysical(air, direction);
    final length = direction.length;
    if (length <= 0.0) return _rgb(resolvedHorizon);
    final x = direction.x / length;
    final y = (direction.y / length).clamp(-1.0, 1.0);
    final z = direction.z / length;

    final base = resolvedHorizon;
    final far = y >= 0.0 ? resolvedZenith : resolvedNadir;
    final magnitude = y.abs();
    final t = magnitude * magnitude * (3.0 - 2.0 * magnitude);
    final color = Vector3(
      base.r + (far.r - base.r) * t,
      base.g + (far.g - base.g) * t,
      base.b + (far.b - base.b) * t,
    );

    final sun = resolvedDirectionToSun.normalized();
    final towards = x * sun.x + y * sun.y + z * sun.z;
    if (towards > 0.0) {
      final lobe = glowStrength * math.pow(towards, glowExponent).toDouble();
      color.addScaled(_rgb(resolvedSunColor), lobe);
    }

    final edge =
        _smoothstep(discOuterCosine, discInnerCosine, towards) *
        luxToEngine(sunIntensity);
    if (edge > 0.0) color.addScaled(_rgb(resolvedSunColor), edge);

    return color;
  }

  /// [sample] for a physical sky: the scattered light, and the disc where the
  /// ray reaches space, white and dimmed by the air it crossed.
  Vector3 _samplePhysical(PhysicalSky air, Vector3 direction) {
    final seen = air.look(direction, resolvedDirectionToSun);
    final color = seen.radiance;
    if (seen.ground || sunIntensity <= 0.0) return color;
    final length = direction.length;
    if (length <= 0.0) return color;
    final towards = direction.dot(resolvedDirectionToSun.normalized()) / length;
    final edge =
        _smoothstep(discOuterCosine, discInnerCosine, towards) *
        luxToEngine(sunIntensity);
    if (edge > 0.0) color.addScaled(seen.transmittance, edge);
    return color;
  }

  /// Cosine of the disc's angular radius, and of the radius plus its soft edge.
  ///
  /// Cosines rather than angles because that is what a dot product answers, and
  /// the outer one is the *smaller* number: cosine falls as the angle grows.
  /// Getting these the wrong way round gives a disc that is inside out — bright
  /// everywhere except at the sun.
  double get discInnerCosine => math.cos(sunAngularRadius);

  /// The cosine of the soft edge's outer angle, unitless.
  double get discOuterCosine => math.cos(sunAngularRadius + sunSoftness.abs());

  /// A copy with the given fields replaced. A `clear…` flag resets that
  /// nullable field to null, which passing null cannot say.
  SkySettings copyWith({
    bool? enabled,
    LinearColor? zenith,
    LinearColor? horizon,
    LinearColor? nadir,
    Vector3? directionToSun,
    LinearColor? sunColor,
    double? glowExponent,
    double? glowStrength,
    double? sunAngularRadius,
    double? sunSoftness,
    double? sunIntensity,
    TextureHandle? cubemap,
    LinearColor? tint,
    PhysicalSky? physical,
    bool clearZenith = false,
    bool clearHorizon = false,
    bool clearNadir = false,
    bool clearDirectionToSun = false,
    bool clearSunColor = false,
    bool clearCubemap = false,
    bool clearTint = false,
    bool clearPhysical = false,
  }) => SkySettings(
    enabled: enabled ?? this.enabled,
    zenith: clearZenith ? null : (zenith ?? this.zenith),
    horizon: clearHorizon ? null : (horizon ?? this.horizon),
    nadir: clearNadir ? null : (nadir ?? this.nadir),
    directionToSun: clearDirectionToSun
        ? null
        : (directionToSun ?? this.directionToSun),
    sunColor: clearSunColor ? null : (sunColor ?? this.sunColor),
    glowExponent: glowExponent ?? this.glowExponent,
    glowStrength: glowStrength ?? this.glowStrength,
    sunAngularRadius: sunAngularRadius ?? this.sunAngularRadius,
    sunSoftness: sunSoftness ?? this.sunSoftness,
    sunIntensity: sunIntensity ?? this.sunIntensity,
    cubemap: clearCubemap ? null : (cubemap ?? this.cubemap),
    tint: clearTint ? null : (tint ?? this.tint),
    physical: clearPhysical ? null : (physical ?? this.physical),
  );
}

/// [color]'s red, green and blue as the `Vector3` the sky's arithmetic is
/// written in.
Vector3 _rgb(LinearColor color) => Vector3(color.r, color.g, color.b);

double _smoothstep(double edge0, double edge1, double x) {
  if (edge0 == edge1) return x < edge0 ? 0.0 : 1.0;
  final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}
