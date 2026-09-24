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
    final distance = (world - Vector3(light.x, light.y, light.z)).length;
    return Vector4((distance / range).clamp(0.0, 1.0), 0.0, 0.0, 1.0);
  }
}

/// Whether a cut-out caster covers this fragment — `gfx-60n`.
///
/// Shared by both masked stages because both ask the same question of the same
/// two numbers: the base colour map's alpha times the material's own alpha,
/// against the material's cutoff. glTF's MASK mode is a hard threshold rather
/// than coverage, and a shadow map holds one depth per texel, so a
/// half-transparent fragment either records or does not.
bool _maskPasses(ShaderBindings bindings, Float32List v) {
  final texture = bindings.textures['base_color_texture'];
  final mask = bindings.vec4('MaskInfo', 'mask', Vector4.zero());
  // No map bound is a caster with nothing to cut out, which passes: the engine
  // only selects these stages for a material that has one, and a stage that
  // discarded everything on a missing binding would turn a mistake into an
  // invisible shadow rather than a loud one.
  if (texture == null) return true;
  final alpha = texture.sample(v[kVUv], v[kVUv + 1]).w * mask.y;
  return alpha >= mask.x;
}

/// `shadow_depth_masked.frag`: window depth, where the caster is opaque
/// enough — `gfx-60n`.
///
/// Null is a discard here, which is what the rasteriser does with it, and it
/// is the whole stage: a leaf card that does not cut out casts the shadow of
/// its quad, which is a stack of dark slabs where the eye expects dappled
/// light.
final class ShadowDepthMaskedShader implements CpuFragmentShader {
  const ShadowDepthMaskedShader();

  @override
  Vector4? run(Float32List v, ShaderBindings bindings, FragmentContext c) =>
      _maskPasses(bindings, v) ? Vector4(c.coord.z, 0.0, 0.0, 1.0) : null;
}

/// `shadow_distance_masked.frag`: the point-light twin of the above.
final class ShadowDistanceMaskedShader implements CpuFragmentShader {
  const ShadowDistanceMaskedShader();

  @override
  Vector4? run(Float32List v, ShaderBindings bindings, FragmentContext c) {
    if (!_maskPasses(bindings, v)) return null;
    final light = bindings.vec4('ShadowLight', 'light', Vector4.zero());
    final range = math.max(light.w, 1e-4);
    final world = Vector3(v[kVWorld], v[kVWorld + 1], v[kVWorld + 2]);
    final distance = (world - Vector3(light.x, light.y, light.z)).length;
    return Vector4((distance / range).clamp(0.0, 1.0), 0.0, 0.0, 1.0);
  }
}

/// `shadow_copy.frag`: one cascade's tile of the static atlas, into colour
/// and depth — `S1`.
final class ShadowCopyShader implements CpuFragmentShader {
  const ShadowCopyShader();

  @override
  Vector4? run(Float32List v, ShaderBindings bindings, FragmentContext c) {
    final source = bindings.textures['static_shadow_texture'];
    if (source == null) return null;
    final tile = bindings.vec4('ShadowCopyInfo', 'tile', Vector4.zero());
    final shift = bindings.vec4('ShadowCopyInfo', 'shift', Vector4.zero());
    final fromU = v[0] - shift.x;
    final fromV = v[1] - shift.y;
    final inside = fromU >= 0.0 && fromU <= 1.0 && fromV >= 0.0 && fromV <= 1.0;
    final stored = source
        .sample(
          tile.x + fromU.clamp(0.0, 1.0) * tile.z,
          tile.y + fromV.clamp(0.0, 1.0) * tile.w,
        )
        .x;
    // Nothing stays nothing: the far end is not a depth the move shifts.
    final depth = inside && stored < 1.0
        ? (stored + shift.z).clamp(0.0, 1.0)
        : 1.0;
    c.fragDepth = depth;
    return Vector4(depth, 0.0, 0.0, 1.0);
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
