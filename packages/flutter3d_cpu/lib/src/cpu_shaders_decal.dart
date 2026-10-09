/// `decal.frag` on the software rasteriser — `P3`.
///
/// Line for line, the order of the stack included: the GLSL paints each decal
/// over the ones before it, and so does this. See the GLSL for why the light
/// is read back through the albedo and why one stage writes two terms.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';
import 'cpu_shaders_color.dart' show decodeSurfaceNormal, pixelRay, toLinear;

/// `kMaxDecals` in `decal.frag`.
const int _maxDecals = 16;

/// `kAlbedoFloor` in `decal.frag`.
const double _albedoFloor = 0.08;

/// `decal.frag`: the factor a decal multiplies the scene by, or the term it
/// adds, by `params.w`.
final class DecalShader extends CpuFragmentShader {
  const DecalShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final params = b.vec4('DecalInfo', 'params', Vector4.zero());
    final factor = params.w < 0.5;
    final keep = factor
        ? Vector4(1.0, 1.0, 1.0, 1.0)
        : Vector4(0.0, 0.0, 0.0, 1.0);
    final surfaceMap = b.textures['surface_texture'];
    final albedoMap = b.textures['albedo_texture'];
    if (surfaceMap == null || albedoMap == null) return keep;

    final u = v[0];
    final w = v[1];
    final surface = surfaceMap.sample(u, w);
    if (surface.w <= 0.0) return keep;

    final inverse = b.mat4('DecalInfo', 'inverse_view_projection');
    final camera = b.vec4('DecalInfo', 'camera', Vector4.zero());
    final forward = b.vec4('DecalInfo', 'forward', Vector4.zero());
    final view = b.vec4('DecalInfo', 'view', Vector4(0.0, 0.0, 1.0, 1.0));
    final eye = Vector3(camera.x, camera.y, camera.z);
    final axis = Vector3(forward.x, forward.y, forward.z);

    // `WorldAt`, with the target's coordinates taken into the view's.
    Vector3 worldAt(double atU, double atV, double depth) {
      final (:origin, :along) = pixelRay(
        inverse,
        (atU - view.x) / view.z,
        (atV - view.y) / view.w,
      );
      return origin +
          along * ((depth - (origin - eye).dot(axis)) / along.dot(axis));
    }

    final depth = surface.w;
    final at = worldAt(u, w, depth);
    final normal = decodeSurfaceNormal(surface.x, surface.y);

    // `WorldStep`: toward the neighbour nearer in depth.
    Vector3 worldStep(double du, double dv) {
      final ahead = surfaceMap.sample(u + du, w + dv);
      final behind = surfaceMap.sample(u - du, w - dv);
      final aheadGap = ahead.w > 0.0 ? (ahead.w - depth).abs() : 1e30;
      final behindGap = behind.w > 0.0 ? (behind.w - depth).abs() : 1e30;
      if (math.min(aheadGap, behindGap) >= 1e29) return Vector3.zero();
      return aheadGap <= behindGap
          ? worldAt(u + du, w + dv, ahead.w) - at
          : at - worldAt(u - du, w - dv, behind.w);
    }

    final dx = worldStep(params.y, 0.0);
    final dy = worldStep(0.0, params.z);
    final albedoTexel = albedoMap.sample(u, w);
    final albedo = Vector3(
      toLinear(albedoTexel.x),
      toLinear(albedoTexel.y),
      toLinear(albedoTexel.z),
    );

    final painted = albedo.clone();
    var kept = 1.0;
    final laid = Vector3.zero();
    final emitted = Vector3.zero();
    final count = (params.x + 0.5).floor();
    for (var i = 0; i < _maxDecals && i < count; i++) {
      final rowX = b.vec4('DecalInfo', 'axis_x', Vector4.zero(), at: i);
      final rowY = b.vec4('DecalInfo', 'axis_y', Vector4.zero(), at: i);
      final rowZ = b.vec4('DecalInfo', 'axis_z', Vector4.zero(), at: i);
      double row(Vector4 r, Vector3 p) => r.x * p.x + r.y * p.y + r.z * p.z;
      final lx = row(rowX, at) + rowX.w;
      final ly = row(rowY, at) + rowY.w;
      final lz = row(rowZ, at) + rowZ.w;
      if (lx.abs() > 0.5 || ly.abs() > 0.5 || lz.abs() > 0.5) continue;

      final fade = b.vec4('DecalInfo', 'fade', Vector4.zero(), at: i);
      final up = Vector3(rowY.x, rowY.y, rowY.z)..normalize();
      final facing = normal.dot(up);
      final byAngle = ((facing - fade.y) / math.max(fade.z, 1e-4)).clamp(
        0.0,
        1.0,
      );
      final byDepth = fade.w > 0.0
          ? ((0.5 - ly.abs()) / (fade.w * 0.5)).clamp(0.0, 1.0)
          : 1.0;

      final region = b.vec4('DecalInfo', 'region', Vector4.zero(), at: i);
      final pu = region.x + (lx + 0.5) * region.z;
      final pv = region.y + (lz + 0.5) * region.w;

      final slot = fade.x;
      final alongXu = row(rowX, dx) * region.z;
      final alongXv = row(rowZ, dx) * region.w;
      final alongYu = row(rowX, dy) * region.z;
      final alongYv = row(rowZ, dy) * region.w;

      final picture = _sampleSlot(
        b,
        slot,
        pu,
        pv,
        // The sampler picks the level from the larger axis in texels, which
        // is the footprint the GLSL computes by hand.
        du: math.max(alongXu.abs(), alongYu.abs()),
        dv: math.max(alongXv.abs(), alongYv.abs()),
      );
      final tint = b.vec4('DecalInfo', 'color', Vector4.zero(), at: i);
      final color = Vector3(
        toLinear(picture.x) * tint.x,
        toLinear(picture.y) * tint.y,
        toLinear(picture.z) * tint.z,
      );
      final alpha = (picture.w * tint.w * byAngle * byDepth).clamp(0.0, 1.0);
      final glow = b.vec4('DecalInfo', 'emissive', Vector4.zero(), at: i);

      _mixInto(painted, color, alpha);
      kept *= 1.0 - alpha;
      _mixInto(laid, color, alpha);
      _mixInto(
        emitted,
        Vector3(color.x * glow.x, color.y * glow.y, color.z * glow.z),
        alpha,
      );
    }

    final named =
        (math.max(albedo.x, math.max(albedo.y, albedo.z)) / _albedoFloor).clamp(
          0.0,
          1.0,
        );
    double swap(double paint, double was) =>
        1.0 + (paint - was) / math.max(was, _albedoFloor);
    if (factor) {
      final unlit = kept * (1.0 - named);
      return Vector4(
        swap(painted.x, albedo.x) * named + unlit,
        swap(painted.y, albedo.y) * named + unlit,
        swap(painted.z, albedo.z) * named + unlit,
        1.0,
      );
    }
    return Vector4(
      laid.x * (1.0 - named) + emitted.x,
      laid.y * (1.0 - named) + emitted.y,
      laid.z * (1.0 - named) + emitted.z,
      1.0,
    );
  }

  /// `mix(into, color, alpha)`, in place.
  static void _mixInto(Vector3 into, Vector3 color, double alpha) {
    into
      ..x += (color.x - into.x) * alpha
      ..y += (color.y - into.y) * alpha
      ..z += (color.z - into.z) * alpha;
  }

  /// `SampleSlot`: the picture in [slot], or white for none.
  static Vector4 _sampleSlot(
    ShaderBindings b,
    double slot,
    double u,
    double v, {
    required double du,
    required double dv,
  }) {
    final index = slot > 2.5
        ? 3
        : slot > 1.5
        ? 2
        : slot > 0.5
        ? 1
        : slot > -0.5
        ? 0
        : -1;
    final BoundTexture? picture = index < 0
        ? null
        : b.textures['decal_texture_$index'];
    if (picture == null) return Vector4(1.0, 1.0, 1.0, 1.0);
    // The texture's own size is the one the GLSL reads out of `slots`.
    return picture.sample(u, v, du: du, dv: dv);
  }
}
