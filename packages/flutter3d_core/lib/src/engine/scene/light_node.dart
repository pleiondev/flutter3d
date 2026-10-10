import 'dart:math' as math;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show LinearColor;
import 'package:vector_math/vector_math.dart';

import 'light_buffer.dart';
import 'scene.dart';
import 'scene_node.dart';

/// What shape a light is, which decides how its contribution is integrated.
///
/// The first three are *punctual*: light leaves one point, so the direction to
/// it is a single vector and the integral over the surface's hemisphere is one
/// cosine. [area] is not, and that is the whole of what makes it worth a fourth
/// entry — `gfx-77n`. A rectangle has extent, so what reaches a surface is an
/// integral over the rectangle rather than a value at a point, and that is what
/// makes an interior read as lit by a window instead of by a bright dot with a
/// window painted behind it.
///
/// **An open set.** [LightType.custom] names a kind of one's own — a torch a
/// plugin flickers, a lamp a level editor files apart — lit as its [base], a
/// built-in shape the renderer integrates. The engine reads [base] wherever
/// it decides how a light is drawn, so a custom kind is drawn exactly as its
/// base is; whoever made it tells it apart by identity, and a format writes
/// its base.
final class LightType {
  const LightType._(this._index, this.name) : _base = null;

  /// A kind called [name], lit as [_base] — one of [values].
  const LightType.custom(this.name, {required LightType base})
    : _base = base, // ignore: prefer_initializing_formals
      _index = -1;

  static const LightType directional = LightType._(0, 'directional');

  static const LightType point = LightType._(1, 'point');

  static const LightType spot = LightType._(2, 'spot');

  static const LightType area = LightType._(3, 'area');

  /// Every built-in value this version names, in the order of [index].
  static const List<LightType> values = <LightType>[
    directional,
    point,
    spot,
    area,
  ];

  /// The value whose [name] is [wireName], or null when this version names
  /// none (absent) — how a file that names a value is read.
  static LightType? byName(String wireName) {
    for (final value in values) {
      if (value.name == wireName) return value;
    }
    return null;
  }

  /// The position of [base] in [values]: stable within a major, appended
  /// only.
  int get index => _base?.index ?? _index;
  final int _index;

  final LightType? _base;

  /// The built-in shape this kind is lit as: itself for each of [values].
  LightType get base => _base?.base ?? this;

  /// The stable name, and the wire name: what a file, a report or a
  /// snapshot writes for this value. Never renamed within a major.
  final String name;

  @override
  String toString() => 'LightType.$name';
}

/// The bit masks [LightNode.channels] and [SceneNode.lightChannels] meet on.
///
/// Plain integers rather than an enum, because the whole point is that a
/// caller invents their own meanings: this engine knows that a bit set on
/// both sides means the light applies, and nothing about what the bit is
/// called. [all] and [none] are the two a caller does not have to invent.
abstract final class LightChannels {
  /// Every channel — what both sides default to, so channels cost nothing
  /// until somebody uses them.
  static const int all = 0xFFFFFFFF;

  /// No channel at all. A light set to this shines on nothing and an object
  /// set to it is lit by nothing but the ambient term — which is a stranger
  /// thing to want than it looks, and is here so that "off" has a spelling.
  static const int none = 0;

  /// The nth channel, counting from zero.
  static int only(int index) => 1 << index;
}

/// A light placed in the scene graph.
///
/// Direction comes from the node's local -Z, the same forward axis cameras use,
/// so [SceneNode.lookAt] aims a spot light exactly as it aims a camera.
final class LightNode extends SceneNode {
  /// How many lights one draw is lit by in the forward pass: 8. A light past
  /// this is carried by the extra slots, then dropped — see
  /// `Scene.overflowingLights`.
  ///
  /// **A getter, not a constant**, since 1.0: the number is the shaders'
  /// array length, which a later minor may raise, and a constant's value is
  /// copied into whoever read it at compile time.
  static int get maxLights => LightBuffer.maxLights;

  /// How many lights past [maxLights] a frame can still carry, in the slots
  /// the clustered path reads: 24. A getter for the reason [maxLights] is.
  static int get maxExtraLights => LightBuffer.maxExtraLights;

  /// Whether this light reaches a mesh on [lightChannels] (a mesh's
  /// `lightChannels` mask): the test every pass applies before lighting it.
  bool reaches(int lightChannels) => LightBuffer.reaches(this, lightChannels);

  LightNode({
    this.type = LightType.directional,
    this.color = LinearColor.white,
    this.intensity = Photometric.legacyUnit,
    this.range = 0.0,
    bool? castsShadow,
    this.innerConeAngle = 0.0,
    this.outerConeAngle = math.pi / 4.0,
    super.name,
  }) : castsShadow = castsShadow ?? type.base == LightType.directional;

  /// A light of [type] rated at [lumens] of luminous flux, converted once to
  /// the candela [intensity] holds — [Photometric.fromLumens] over the light's
  /// own cone.
  LightNode.lumens(
    double lumens, {
    LightType type = LightType.point,
    LinearColor color = LinearColor.white,
    double range = 0.0,
    bool? castsShadow,
    double innerConeAngle = 0.0,
    double outerConeAngle = math.pi / 4.0,
    String? name,
  }) : this(
         type: type,
         color: color,
         intensity: Photometric.fromLumens(
           lumens,
           type: type,
           outerConeAngle: outerConeAngle,
         ),
         range: range,
         castsShadow: castsShadow,
         innerConeAngle: innerConeAngle,
         outerConeAngle: outerConeAngle,
         name: name,
       );

  LightType type;

  /// The light's colour, in linear light — `LinearColor` since 1.0 (it was a
  /// mutable `Vector3`). Its alpha is ignored. Replaced whole:
  /// `light.color = const LinearColor(1.0, 0.8, 0.6)`.
  LinearColor color;

  /// Whether this light wants a shadow map.
  ///
  /// A request, not a promise: the renderer shadows a limited number of lights
  /// and asking does not put a light at the front of that queue. Clearing it
  /// is a promise, and on a directional light that used to be the half that
  /// was missing: the sun cast whether or not the flag said so, because only
  /// the cube shadows read it.
  ///
  /// **Left out of the constructor, it depends on [type]**: true for a
  /// directional light, false for a point, spot or area light. That is what
  /// every scene already drew, since the sun cast regardless and a point light
  /// cast only when asked. It is decided once, when the node is made;
  /// changing [type] afterwards leaves it as it was.
  bool castsShadow;

  /// Which channels this light shines on — `gfx-12n`'s own row.
  ///
  /// A bit mask meeting [SceneNode.lightChannels]: a light reaches an object
  /// when `light.channels & node.lightChannels` is not zero. Both default to
  /// every bit, so a scene that has never heard of channels is lit exactly as
  /// it was — which is checkable rather than asserted, since a frame with no
  /// channels takes the same fast path through the light selection it always
  /// did and packs the identical bytes.
  ///
  /// **What it is for**: a hero's flashlight that does not light the sky, an
  /// interior lamp that does not leak through a wall the renderer has no way
  /// to know is there. Both are cases where the right answer is not more
  /// shadow work but a statement about what a light is *for*.
  ///
  /// It is applied when the eight lights of a draw are chosen, so a light
  /// that cannot reach an object does not take one of its slots either. That
  /// is the difference between a channel and a check in the shader.
  int channels = LightChannels.all;

  /// How bright this light is: **lux** for a directional light, **candela**
  /// for a point, spot or area light — see [Photometric] (since 1.0; the
  /// engine's own unit before it, which [Photometric.legacyUnit] converts).
  ///
  /// The default is [Photometric.legacyUnit], the light a default-made node
  /// always was, kept so a scene of default lights draws as it did: about
  /// 5 790.6 lux, a bright overcast day, for a sun, and for a lamp about
  /// 5 790.6 cd — some 73 000 lumens, a stadium floodlight rather than a
  /// bulb. Say what a lamp is: [LightNode.lumens] makes one from what its box
  /// says, and about 100 cd is a household bulb.
  double intensity;

  /// Distance at which a point or spot light stops contributing. Zero means
  /// unbounded, matching glTF's default.
  /// In metres.
  double range;

  /// Half-angle from the spot axis to where the falloff starts, in radians.
  double innerConeAngle;

  /// Half-angle from the spot axis to where the light ends, in radians.
  double outerConeAngle;

  /// How wide the rectangle is, in world metres, along the node's local +X —
  /// `gfx-77n`. Ignored by every other kind.
  double width = 1.0;

  /// How tall it is, along the node's local +Y.
  ///
  /// The rectangle faces the node's local −Z, the same forward axis a spot
  /// light aims down and a camera looks along, so [SceneNode.lookAt] aims a
  /// window at what it should be lighting exactly as it aims everything else.
  /// In metres.
  double height = 1.0;

  /// The rectangle's half-width vector in world space, i.e. local +X scaled by
  /// half of [width]. Mutates and returns [out].
  ///
  /// A vector rather than a scalar, because the shader needs the rectangle's
  /// *roll* around its own normal and a number cannot carry it. The pair of
  /// these plus the centre is the whole rectangle: its corners are the centre
  /// plus and minus each of them.
  Vector3 readHalfWidth([Vector3? out]) {
    final result = out ?? Vector3.zero();
    final m = worldMatrix.storage;
    result.setValues(m[0], m[1], m[2]);
    // Normalised and then scaled, so a node scaled by its parent does not
    // multiply the panel twice: the size is the light's own property and the
    // matrix is only being asked which way its axes point.
    if (result.length2 > 0.0) result.normalize();
    return result..scale(width * 0.5);
  }

  /// The half-height vector, local +Y scaled by half of [height].
  Vector3 readHalfHeight([Vector3? out]) {
    final result = out ?? Vector3.zero();
    final m = worldMatrix.storage;
    result.setValues(m[4], m[5], m[6]);
    if (result.length2 > 0.0) result.normalize();
    return result..scale(height * 0.5);
  }

  /// World-space direction the light points, i.e. the node's local -Z.
  ///
  /// Normalizes [out] in place and returns it. `normalized()` would return a new
  /// vector and leave [out] holding the un-normalized value — a caller that reads
  /// its own variable instead of the return value then gets silently wrong data.
  Vector3 readDirection([Vector3? out]) {
    final result = out ?? Vector3.zero();
    final m = worldMatrix.storage;
    result.setValues(-m[8], -m[9], -m[10]);
    if (result.length2 > 0.0) result.normalize();
    return result;
  }

  /// Direction *towards* the light, which is what shading maths wants.
  ///
  /// Mutates [out] so the returned vector and [out] are the same object. Getting
  /// this wrong inverts the light: surfaces facing the camera fall to N.L <= 0 and
  /// the scene renders as pure ambient.
  Vector3 readDirectionToLight([Vector3? out]) => readDirection(out)..negate();

  @override
  void onAttachedToScene(Scene scene) => scene.registerLight(this);

  @override
  void onDetachedFromScene(Scene scene) => scene.unregisterLight(this);
}

/// Lumens, candela and lux — the units [LightNode.intensity] is in since 1.0
/// (decision 8 of the API review, `docs/CONTRACTS.md` "Light").
///
/// **What a light is rated in.** A directional light in lux, the illuminance
/// on a surface facing it: about 100 000 for direct sun, 1 000 to 10 000 for
/// an overcast day, 500 for a bright office. A point, spot or area light in candela, its
/// luminous intensity along its axis: about 100 for a 1 200 lm bulb. A box's
/// lumens are converted once, by [fromLumens], into what the light holds.
/// The camera's exposure (`PhysicalCamera`, EV100) turns these absolute
/// values into a picture.
///
/// **The unit before 1.0, and why a picture does not change.** Until 1.0
/// [LightNode.intensity] was the engine's own number, and the physical
/// camera fixed what it was worth: one unit of illuminance is about
/// 5 790.6 lux (one unit of luminance is 1 843.2 cd/m², [legacyNits], and a
/// white Lambertian surface shows `E/π`). That is [legacyUnit]. A light written before 1.0 with intensity `x` is the same
/// light at `x * Photometric.legacyUnit` now — what `migrate` writes — and
/// the renderer divides by it on the way to the shaders, so the picture is
/// the picture it was. (`gfx-13n`'s own exchange rate, 800 lm to one unit,
/// went with the old unit: it was a matter of taste, and the physical
/// camera's is a matter of arithmetic.)
abstract final class Photometric {
  /// Lux (for a directional light) or candela (for the others) in one unit
  /// of the engine's pre-1.0 intensity: `π × 1.6 × 1.2 × 960`, about 5 790.6.
  /// Multiply a pre-1.0 intensity by it to keep a light as bright as it was;
  /// the same for a pre-1.0 `Scene.ambientIntensity`,
  /// `Atmosphere.ambientIntensity` or `SkySettings.sunIntensity`, which are
  /// lux since 1.0.
  static const double legacyUnit = 5790.583578; // π × 1843.2

  /// Nits (cd/m²) in one unit of the engine's pre-1.0 luminance:
  /// `1.6 × 1.2 × 960`, 1 843.2. The reference camera draws it at 1.6, past
  /// white: its white, the brightest luminance it records, is `1.2 × 960`,
  /// 1 152 nits. Multiply a pre-1.0 `RenderMaterial.emissiveStrength` by it
  /// to keep a surface glowing as it did; it is nits since 1.0.
  static const double legacyNits = 1843.2;

  /// The illuminance an 800-lumen lamp — an ordinary bulb — gives a surface
  /// a metre away: `800 / 4π`, about 63.66 lux. A yardstick for scaling an
  /// emissive colour by a brightness someone stated in lux or nits; it was
  /// the engine's exchange rate for `Photometric.fromLux` before 1.0.
  static const double bulbAtOneMeter = 63.66197723675813;

  /// What [LightNode.intensity] holds for [lumens] of luminous flux, for a
  /// light of [type]: candela for a point, spot or area light, spread over
  /// the solid angle it covers — the whole sphere for a point lamp, the cone
  /// (of half-angle [outerConeAngle]) for a spot, `π` for a one-sided
  /// Lambertian panel — and, for a directional light, which has no flux worth
  /// rating, the number itself as lux.
  static double fromLumens(
    double lumens, {
    LightType type = LightType.point,
    double outerConeAngle = math.pi / 4.0,
  }) => switch (type.base) {
    LightType.directional => lumens,
    LightType.point => lumens / (4.0 * math.pi),
    LightType.spot => lumens / _coneSteradians(outerConeAngle),
    // A rectangle emits from one face, as a Lambertian surface: its
    // intensity falls off as `cos θ` from the axis, and the flux into the
    // hemisphere is `π` times the axial candela, not `2π`.
    LightType.area => lumens / math.pi,
    _ => throw ArgumentError.value(type, 'type', 'has no lumens rating here'),
  };

  /// The lumens a light of [type] at [intensity] (candela, or lux for a
  /// directional light) puts out: [fromLumens] the other way.
  static double toLumens(
    double intensity, {
    LightType type = LightType.point,
    double outerConeAngle = math.pi / 4.0,
  }) => switch (type.base) {
    LightType.directional => intensity,
    LightType.point => intensity * 4.0 * math.pi,
    LightType.spot => intensity * _coneSteradians(outerConeAngle),
    LightType.area => intensity * math.pi,
    _ => throw ArgumentError.value(type, 'type', 'has no lumens rating here'),
  };

  /// The solid angle of a cone of half-angle [outerConeAngle], in steradians.
  ///
  /// `2π(1 − cos θ)`, clamped away from nothing: a cone of no width has no
  /// solid angle, and dividing a flux by it would make one lumen infinitely
  /// bright. The floor is a cone about a tenth of a degree across, which is
  /// narrower than any spot anybody aims and wide enough that the arithmetic
  /// stays finite.
  static double _coneSteradians(double outerConeAngle) {
    final angle = outerConeAngle.clamp(0.001, math.pi);
    return 2.0 * math.pi * (1.0 - math.cos(angle));
  }
}
