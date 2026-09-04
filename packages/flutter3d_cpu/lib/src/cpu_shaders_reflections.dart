/// `reflections.frag`: screen-space reflections, marched against the surface
/// buffer. See `cpu_shaders_ssao.dart` for the other ray march over the same
/// buffer.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';
import 'cpu_shaders_color.dart';

/// `reflections.frag`: screen-space reflections, marched against the surface
/// buffer.
///
/// The part that looked wrong was wrong. This file used to carry a note that
/// the ray's screen position was `ndc.xy * 0.5 + 0.5` with **no v flip**, where
/// the shadow lookups flip — transcribed exactly, because a backend does not
/// get to settle a disagreement between conventions by quietly picking one. It
/// was a disagreement, and the shadow lookup had the right end of it: the march
/// read the surface buffer upside down on every backend whose row zero is at
/// the top, which is Impeller and this one. See `UvFromNdc` in reflections.frag.
final class ReflectionsShader implements CpuFragmentShader {
  const ReflectionsShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final sceneMap = b.textures['scene_texture'];
    final surfaceMap = b.textures['surface_texture'];
    if (sceneMap == null || surfaceMap == null) {
      return Vector4(0.0, 0.0, 0.0, 1.0);
    }
    final u = v[0];
    final w = v[1];

    final surface = surfaceMap.sample(u, w);
    final sampled = sceneMap.sample(u, w);
    final scene = Vector3(sampled.x, sampled.y, sampled.z);

    final screen = b.vec4('ReflectionInfo', 'screen', Vector4.zero());
    final debugOnly = screen.w > 0.5;
    final background = debugOnly ? Vector3.zero() : scene;

    Vector4 done(Vector3 rgb) => Vector4(rgb.x, rgb.y, rgb.z, 1.0);

    if (surface.w <= 0.0) return done(background);

    final normal = decodeOctahedral(surface.x, surface.y);
    final roughness = surface.z;
    final polish = 1.0 - smoothstep(0.18, 0.45, roughness);
    if (polish <= 0.0) return done(background);

    final inverse = b.mat4('ReflectionInfo', 'inverse_view_projection');

    // The two halves of the origin convention, kept next to each other so they
    // cannot drift apart: v runs the other way from clip-space y, and the
    // matrices carry whichever backend this is.
    double vFromNdc(double ndcY) => 0.5 - ndcY * 0.5;
    Vector3 worldFrom(double uu, double vv, double depth) {
      final Vector4 h =
          inverse * Vector4(uu * 2.0 - 1.0, 1.0 - vv * 2.0, depth, 1.0);
      return Vector3(h.x, h.y, h.z)..scale(1.0 / h.w);
    }

    final position = worldFrom(u, w, surface.w);

    final camera = b.vec4('ReflectionInfo', 'camera', Vector4.zero());
    final eye = Vector3(camera.x, camera.y, camera.z);
    final toEye = (eye - position)..normalize();
    final facing = normal.dot(toEye);
    if (facing <= 0.05) return done(background);

    // reflect(-toEye, normal)
    final incident = -toEye;
    final ray = incident - normal * (2.0 * incident.dot(normal));

    final params = b.vec4('ReflectionInfo', 'params', Vector4.zero());
    final steps = params.x.toInt();
    final stride = params.y;
    final thickness = params.z;
    final intensity = params.w;

    final viewProjection = b.mat4('ReflectionInfo', 'view_projection');
    final march = position + normal * 0.02 + ray * stride;
    var hitColour = Vector3.zero();
    var hit = 0.0;

    // Sixty-four is the shader's own ceiling, and it is a real one: GLSL needs
    // a constant bound. Kept so the two loops end in the same place.
    for (var i = 0; i < 64; i++) {
      if (i >= steps) break;
      final Vector4 clip =
          viewProjection * Vector4(march.x, march.y, march.z, 1.0);
      if (clip.w <= 0.0) break;
      final nx = clip.x / clip.w;
      final ny = clip.y / clip.w;
      final nz = clip.z / clip.w;
      final su = nx * 0.5 + 0.5;
      final sv = vFromNdc(ny);
      if (su < 0.0 || su > 1.0 || sv < 0.0 || sv > 1.0) break;

      final sceneDepth = surfaceMap.sample(su, sv).w;
      // Behind what was drawn here, then how far behind in metres — the two
      // halves the GLSL splits, and for the reason written there: a
      // window-depth difference is a different number of metres at every
      // range, so it can only answer the first question.
      if (sceneDepth > 0.0 && nz > sceneDepth) {
        final seen = worldFrom(su, sv, sceneDepth);
        final behind = eye.distanceTo(march) - eye.distanceTo(seen);
        if (behind < thickness) {
          final tex = sceneMap.sample(su, sv);
          hitColour = Vector3(tex.x, tex.y, tex.z);
          final border =
              1.0 - math.max((su * 2.0 - 1.0).abs(), (sv * 2.0 - 1.0).abs());
          hit = smoothstep(0.0, 0.15, border);
          break;
        }
      }
      march.add(ray * stride);
    }

    final fresnel = math.pow(1.0 - facing, 4.0).toDouble();
    final reflection =
        hitColour * (hit * intensity * polish * (0.15 + 0.85 * fresnel));
    return done(debugOnly ? reflection : scene + reflection);
  }
}
