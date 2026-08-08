import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'scene.dart';
import 'scene_node.dart';

enum LightType { directional, point, spot }

/// A light placed in the scene graph.
///
/// Direction comes from the node's local -Z, the same forward axis cameras use,
/// so [SceneNode.lookAt] aims a spot light exactly as it aims a camera.
final class LightNode extends SceneNode {
  LightNode({
    this.type = LightType.directional,
    Vector3? color,
    this.intensity = 1.0,
    this.range = 0.0,
    this.innerConeAngle = 0.0,
    this.outerConeAngle = math.pi / 4.0,
    super.name,
  }) : color = color ?? Vector3(1.0, 1.0, 1.0);

  LightType type;

  /// Linear RGB.
  final Vector3 color;

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
