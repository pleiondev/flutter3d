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
