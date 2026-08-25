/// The stages that render *into* a shadow map, as opposed to the ones that
/// look one up while lighting a surface — see `cpu_shaders_shadow_directional.dart`
/// and `cpu_shaders_shadow_point.dart` for those.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';
import 'cpu_shaders_layout.dart';

/// `shadow_depth.frag`: window depth into a colour target.
///
/// A colour target rather than the depth buffer because flutter_gpu gives no
/// way to sample a depth texture, and the workaround is in the engine rather
/// than in any one backend. `gl_FragCoord.z` is the right value *because* the
/// shadow camera is orthographic — under perspective it would be hyperbolic,
/// all its precision near the near plane, and comparing two of them would mean
/// nothing.
final class ShadowDepthShader implements CpuFragmentShader {
  const ShadowDepthShader();

  @override
  Vector4? run(Float32List v, ShaderBindings bindings, FragmentContext c) =>
      Vector4(c.coord.z, 0.0, 0.0, 1.0);
}

/// `shadow_distance.frag`: radial distance from a point light, over its range.
///
/// Not clip depth. Clip depth is measured along one cube face's axis, so the
/// same distance reads differently depending which face a direction lands on
/// and every face boundary shows a seam.
final class ShadowDistanceShader implements CpuFragmentShader {
  const ShadowDistanceShader();

  @override
  Vector4? run(Float32List v, ShaderBindings bindings, FragmentContext c) {
    final light = bindings.vec4('ShadowLight', 'light', Vector4.zero());
    final range = math.max(light.w, 1e-4);
    final world = Vector3(v[kVWorld], v[kVWorld + 1], v[kVWorld + 2]);
    final distance =
        (world - Vector3(light.x, light.y, light.z)).length;
    return Vector4((distance / range).clamp(0.0, 1.0), 0.0, 0.0, 1.0);
  }
}

/// `shadow_tile_reset.frag`: one, the far end of the range.
///
/// A texel no caster covers means "nothing between the light and its range",
/// which is the right answer for a direction with nothing in it.
final class ShadowTileResetShader implements CpuFragmentShader {
  const ShadowTileResetShader();

  @override
  Vector4? run(Float32List v, ShaderBindings bindings, FragmentContext c) =>
      Vector4(1.0, 1.0, 1.0, 1.0);
}

/// `shadow_tile_reset.vert`: the fullscreen triangle, but on the far plane.
///
/// `z = 1`, not zero. The casters are drawn into the same tile immediately
/// afterwards, comparing `less` against a buffer this triangle has just
/// covered, and a mid-depth value stamped across the tile makes every caster
/// beyond it fail and vanish. In the engine's history that was a shadow that
/// was present before the tile reset existed and missing after.
final class ShadowTileResetVertexShader implements CpuVertexShader {
  const ShadowTileResetVertexShader();

  @override
  int get varyingCount => 2;

  @override
  Vector4 run(Float32List a, ShaderBindings bindings, Float32List out) {
    out[0] = a[2];
    out[1] = a[3];
    return Vector4(a[0], a[1], 1.0, 1.0);
  }
}
