import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'light_node.dart';

/// Light type codes as the shader reads them.
///
/// Explicit integers rather than an enum index: the value is written into a
/// uniform and compared against a literal in GLSL, so a reordered enum would
/// silently re-type every light in the scene.
abstract final class ShaderLightType {
  static const double directional = 0.0;
  static const double point = 1.0;
  static const double spot = 2.0;

  static double of(LightType type) => switch (type) {
    LightType.directional => directional,
    LightType.point => point,
    LightType.spot => spot,
  };
}

/// The scene's active lights, packed the way the fragment shaders read them.
///
/// Four `vec4` arrays plus a count, because that is what a uniform block can
/// hold and what turning a light on or off must not disturb: the count is a
/// uniform, so the shader loop shortens without any pipeline being rebuilt.
/// That constraint is not a preference — with shaders compiled ahead of time
/// there is no recompilation available to fall back on.
///
/// The arrays are allocated once and refilled in place, so gathering lights
/// costs nothing per frame.
///
/// ## The layout
///
/// For light `i`:
///
/// | Array | xyz | w |
/// |---|---|---|
/// | `positions` | world position (point, spot) | type code |
/// | `colors` | linear RGB | intensity |
/// | `directions` | the direction it points, its local -Z | range, 0 for unbounded |
/// | `cones` | x: cos(inner), y: cos(outer) | unused |
final class LightBuffer {
  /// The shader declares arrays of this length, so it is a compile-time
  /// constant on both sides. Raising it means rebuilding the bundle.
  static const int maxLights = 8;

  final Float32List positions = Float32List(maxLights * 4);
  final Float32List colors = Float32List(maxLights * 4);
  final Float32List directions = Float32List(maxLights * 4);
  final Float32List cones = Float32List(maxLights * 4);

  /// The nodes behind the packed slots, in slot order.
  ///
  /// Needed because a shadow belongs to a light, and the shader knows lights
  /// only by their index here. Without this the renderer can build a shadow
  /// map and then be unable to say which light it is for.
  final List<LightNode> packed = <LightNode>[];

  int _count = 0;
  int _overflow = 0;

  /// Lights actually packed, never more than [maxLights].
  int get count => _count;

  /// Lights that did not fit, so a caller can say so rather than leave the user
  /// wondering why the ninth lamp does nothing.
  int get overflow => _overflow;

  final Vector3 _direction = Vector3.zero();
  final Vector3 _position = Vector3.zero();

  /// Packs the visible lights of [lights] into the arrays.
  ///
  /// Registry order, capped. Choosing *which* eight matter when there are more
  /// is the job of clustered forward, and guessing at it here — nearest to the
  /// camera, brightest, largest solid angle — would be a heuristic that looks
  /// right in a demo and pops in a real scene.
  void gather(List<LightNode> lights) {
    _count = 0;
    _overflow = 0;
    packed.clear();

    for (var i = 0; i < lights.length; i++) {
      final light = lights[i];
      if (!light.visibleInHierarchy) continue;
      if (light.intensity <= 0.0) continue;

      if (_count >= maxLights) {
        _overflow++;
        continue;
      }

      packed.add(light);
      final slot = _count * 4;
      light.readDirection(_direction);
      light.readWorldPosition(_position);

      positions[slot] = _position.x;
      positions[slot + 1] = _position.y;
      positions[slot + 2] = _position.z;
      positions[slot + 3] = ShaderLightType.of(light.type);

      colors[slot] = light.color.x;
      colors[slot + 1] = light.color.y;
      colors[slot + 2] = light.color.z;
      colors[slot + 3] = light.intensity;

      directions[slot] = _direction.x;
      directions[slot + 1] = _direction.y;
      directions[slot + 2] = _direction.z;
      directions[slot + 3] = math.max(light.range, 0.0);

      // Cosines rather than angles: the shader compares against a dot product,
      // and doing the conversion here keeps a transcendental out of the inner
      // loop of every fragment.
      //
      // The inner cone is clamped just inside the outer one. glTF allows them
      // to be equal, which makes the falloff divide by zero, and the result is
      // a spot light that renders as a black disc.
      final outer = light.outerConeAngle.clamp(0.0, math.pi / 2.0);
      final inner = light.innerConeAngle.clamp(0.0, outer);
      final cosOuter = math.cos(outer);
      var cosInner = math.cos(inner);
      if (cosInner - cosOuter < 1e-4) cosInner = cosOuter + 1e-4;

      cones[slot] = cosInner;
      cones[slot + 1] = cosOuter;
      cones[slot + 2] = 0.0;
      cones[slot + 3] = 0.0;

      _count++;
    }
  }

  /// Fills slot zero with a neutral key light.
  ///
  /// A scene with no lights at all would otherwise render as pure ambient,
  /// which reads as "the renderer is broken" rather than "you forgot a light".
  void useDefaultLight() {
    _count = 1;
    _overflow = 0;

    final direction = Vector3(-0.45, -0.8, -0.6)..normalize();

    positions[0] = 0.0;
    positions[1] = 0.0;
    positions[2] = 0.0;
    positions[3] = ShaderLightType.directional;

    colors[0] = 1.0;
    colors[1] = 0.97;
    colors[2] = 0.92;
    colors[3] = 1.0;

    directions[0] = direction.x;
    directions[1] = direction.y;
    directions[2] = direction.z;
    directions[3] = 0.0;

    cones[0] = 1.0;
    cones[1] = 0.0;
    cones[2] = 0.0;
    cones[3] = 0.0;
  }

  @override
  String toString() =>
      'LightBuffer($_count lights'
      '${_overflow > 0 ? ', $_overflow dropped' : ''})';
}
