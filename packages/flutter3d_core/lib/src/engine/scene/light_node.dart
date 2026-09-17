import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'scene.dart';
import 'scene_node.dart';

enum LightType { directional, point, spot }

/// A light placed in the scene graph.
///
/// Direction comes from the node's local -Z, the same forward axis cameras use,
/// so [SceneNode.lookAt] aims a spot light exactly as it aims a camera.
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

final class LightNode extends SceneNode {
  LightNode({
    this.type = LightType.directional,
    Vector3? color,
    this.intensity = 1.0,
    this.range = 0.0,
    this.castsShadow = false,
    this.innerConeAngle = 0.0,
    this.outerConeAngle = math.pi / 4.0,
    super.name,
  }) : color = color ?? Vector3(1.0, 1.0, 1.0);

  LightType type;

  /// Linear RGB.
  final Vector3 color;

  /// Whether this light wants a shadow map.
  ///
  /// A request, not a promise: the renderer shadows one directional light and
  /// one point light, and asking does not put a light at the front of that
  /// queue. The level format has carried the flag since it was written and
  /// nothing read it, which is why a torch lit the far side of a wall.
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

  /// How bright this light is, in the engine's own unit — see [Photometric]
  /// for what that unit is worth in lumens, candela and lux.
  ///
  /// Dimensionless on purpose, and it stays that way: the shaders multiply
  /// it by an attenuation and a tone curve maps the result, so putting a
  /// physical unit *in* here would mean every existing scene's numbers
  /// changing meaning. [Photometric] converts into it instead, which leaves
  /// a hand-tuned lamp and a lamp off a datasheet side by side in the same
  /// field.
  double intensity;

  /// Distance at which a point or spot light stops contributing. Zero means
  /// unbounded, matching glTF's default.
  double range;

  double innerConeAngle;
  double outerConeAngle;

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

/// Lumens, candela and lux, into [LightNode.intensity] — `gfx-13n`.
///
/// **What the engine's own unit is worth, stated once so it can be argued
/// with.** [LightNode.intensity] is a plain number the shaders multiply by an
/// attenuation; nothing in the renderer has ever said what one of it *means*,
/// so a lamp off a datasheet could only be tuned by eye. This fixes the
/// exchange rate at one place, and the place the row itself names:
///
/// > an 800-lumen lamp gives the same illuminance as today's tuned number
///
/// Eight hundred lumens is the ordinary bulb — what a sixty-watt incandescent
/// was replaced by — and today's tuned number is one. So: **an 800 lm point
/// lamp is [LightNode.intensity] 1.0 at a metre**, and every other conversion
/// follows from that by arithmetic rather than by taste.
///
/// Reading it out: a point lamp spreads its flux over the whole sphere, so
/// 800 lm is `800 / 4π` = 63.66 candela, and a source of *I* candela lights a
/// surface a metre away with *I* lux. [referenceIlluminance] is therefore
/// 63.66 lux, and it is the one number here anybody should want to change —
/// changing it rescales every physically-specified light in a scene together,
/// which is what an exposure control is for and why this is not one.
///
/// **Nothing is applied automatically.** A scene built by hand keeps the
/// numbers it was tuned with, because these are functions a caller reaches
/// for rather than a mode the renderer enters.
abstract final class Photometric {
  /// The illuminance one unit of [LightNode.intensity] stands for, in lux.
  ///
  /// `800 / 4π`, which is what makes an 800-lumen point lamp come out at one.
  static const double referenceIlluminance = 63.66197723675813;

  /// Illuminance in lux — what a *directional* light is rated in.
  ///
  /// A directional light has no position and so no falloff: its intensity is
  /// the illuminance on a surface facing it, anywhere in the scene. Overcast
  /// daylight is about 10 000 lux, a bright office 500, a living room 150.
  static double fromLux(double lux) => lux / referenceIlluminance;

  /// Luminous intensity in candela — what a *point or spot* light's own
  /// datasheet gives when it gives a direction rather than a total.
  ///
  /// A source of one candela lights a surface a metre away with one lux, and
  /// the shaders' inverse square does the rest, so this is [fromLux] with the
  /// metre already in it.
  static double fromCandela(double candela) => candela / referenceIlluminance;

  /// Luminous flux in lumens — what a bulb's box says.
  ///
  /// Spread over the solid angle the light actually covers: the whole sphere
  /// for a point lamp, and the cone for a spot, which is why the same eight
  /// hundred lumens are far brighter through a spot. [outerConeAngle] is the
  /// half-angle from the axis, the same one [LightNode.outerConeAngle] holds,
  /// and is ignored for the two types that do not have one.
  ///
  /// A directional light is not rated in lumens at all — the sun's flux is
  /// not a useful number for lighting a room — so asking for one here gives
  /// back what [fromLux] would, treating the flux as an illuminance and
  /// leaving the caller to have meant it.
  static double fromLumens(
    double lumens, {
    LightType type = LightType.point,
    double outerConeAngle = math.pi / 4.0,
  }) => switch (type) {
    LightType.directional => fromLux(lumens),
    LightType.point => fromCandela(lumens / (4.0 * math.pi)),
    LightType.spot => fromCandela(lumens / _coneSteradians(outerConeAngle)),
  };

  /// [intensity] back in lux, for a panel that shows what a light is set to.
  static double toLux(double intensity) => intensity * referenceIlluminance;

  /// [intensity] back in candela.
  static double toCandela(double intensity) => intensity * referenceIlluminance;

  /// [intensity] back in lumens, inverting [fromLumens] for the same type and
  /// cone.
  static double toLumens(
    double intensity, {
    LightType type = LightType.point,
    double outerConeAngle = math.pi / 4.0,
  }) => switch (type) {
    LightType.directional => toLux(intensity),
    LightType.point => toCandela(intensity) * 4.0 * math.pi,
    LightType.spot => toCandela(intensity) * _coneSteradians(outerConeAngle),
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
