/// `SampleLight` and `AccumulateLights` from `surface.glsl`: turning a light
/// index into a contribution, and summing every light a fragment sees.
///
/// The seam between this file and `cpu_shaders_surface.dart` is the seam
/// `surface.glsl` itself draws: reading a surface answers "what is here",
/// this file answers "what lights it".
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';
import 'cpu_shaders_layout.dart';
import 'cpu_shaders_shadow_directional.dart';
import 'cpu_shaders_shadow_point.dart';
import 'cpu_shaders_surface.dart';

/// `LightCount()`: the count lives in `frame_params.y`, not in a member of its
/// own. Reading a member that does not exist is silent, which is how the first
/// version of this file drew an unlit scene.
int lightCount(ShaderBindings bindings) {
  final params = bindings.vec4('FragInfo', 'frame_params', Vector4.zero());
  return (params.y + 0.5).floor().clamp(0, kMaxLights);
}

/// `PunctualAttenuation`: inverse square with glTF's range window.
double attenuation(double distance, double range) {
  var attenuation = 1.0 / math.max(distance * distance, 1e-4);
  if (range > 0.0) {
    final ratio = distance / range;
    final window = (1.0 - ratio * ratio * ratio * ratio).clamp(0.0, 1.0);
    attenuation *= window * window;
  }
  return attenuation;
}

/// What `SampleLight` produces.
typedef LightSample = ({
  Vector3 direction,
  Vector3 radiance,
  double nDotL,
  double nDotH,
  double vDotH,
});

/// `SampleLight`.
///
/// Returns null for a light that contributes nothing, which is the `n_dot_l <=
/// 0` early-out in `AccumulateLights`.
LightSample? sampleLight(ShaderBindings bindings, int index, Surface s) {
  final position = bindings.vec4(
    'FragInfo',
    'light_position',
    Vector4.zero(),
    at: index,
  );
  final colour = bindings.vec4(
    'FragInfo',
    'light_color',
    Vector4.zero(),
    at: index,
  );
  final direction = bindings.vec4(
    'FragInfo',
    'light_direction',
    Vector4.zero(),
    at: index,
  );

  final aim = Vector3(direction.x, direction.y, direction.z);
  final aimLength = aim.length;
  if (aimLength > 1e-6) aim.scale(1.0 / aimLength);

  Vector3 toLight;
  var lightAttenuation = 1.0;
  if (position.w < 0.5) {
    // Directional: the direction to the light is the reverse of the one it
    // points.
    toLight = -aim;
  } else {
    toLight = Vector3(position.x, position.y, position.z) - s.world;
    final distance = toLight.length;
    if (distance < 1e-6) return null;
    toLight.scale(1.0 / distance);
    lightAttenuation = attenuation(distance, direction.w);
  }

  // The spot cone: a smooth ramp between the two cosines, transcribed from
  // `SampleLight` in surface.glsl. The Dart side guarantees the denominator is
  // non-zero.
  //
  // Three lines above this there used to be a comment saying spot cones were
  // not transcribed, left behind when they were. This file's header promises
  // that where it departs from the GLSL it says so, which is only worth
  // anything if a departure it names is one it has.
  if (position.w > 1.5) {
    final cone = bindings.vec4(
      'FragInfo',
      'light_cone',
      Vector4.zero(),
      at: index,
    );
    final cosAngle = aim.dot(-toLight);
    lightAttenuation *= ((cosAngle - cone.y) / (cone.x - cone.y)).clamp(
      0.0,
      1.0,
    );
  }

  final half = (toLight + s.view)..normalize();
  final nDotL = math.max(s.normal.dot(toLight), 0.0);
  if (nDotL <= 0.0) return null;
  return (
    direction: toLight,
    radiance:
        Vector3(colour.x, colour.y, colour.z) * (colour.w * lightAttenuation),
    nDotL: nDotL,
    nDotH: math.max(s.normal.dot(half), 0.0),
    vDotH: math.max(s.view.dot(half), 0.0),
  );
}

/// `AccumulateLights`, with the model's own response passed in.
///
/// The GLSL achieves this with two function prototypes each shader defines;
/// here it is a callback, which is the same shape and one fewer file.
Vector3 accumulateLights(
  Surface s,
  ShaderBindings b,
  FragmentContext c, {
  required Vector3 Function(Surface s, LightSample light) shade,
  required bool shadowed,
}) {
  var total = Vector3.zero();
  final count = lightCount(b);
  for (var i = 0; i < count; i++) {
    final light = sampleLight(b, i, s);
    if (light == null) continue;
    var visibility = shadowed ? shadowFactor(s, b, i) : 1.0;
    visibility *= pointShadowFactor(b, s.world, s.normal, i, c);
    if (visibility <= 0.0) continue;
    final response = shade(s, light);
    total += Vector3(
      response.x * light.radiance.x,
      response.y * light.radiance.y,
      response.z * light.radiance.z,
    )..scale(light.nDotL * visibility);
  }
  return total;
}
