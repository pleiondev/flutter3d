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
/// Transcribed including the part that looks wrong: the ray's screen position
/// is `ndc.xy * 0.5 + 0.5` with **no v flip**, where the shadow lookups do
/// flip. Reproducing it exactly is the job here — if the two conventions
/// genuinely disagree that is a finding about the engine, and it is not one a
/// backend gets to decide by quietly picking the other one.
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
    final ndc = Vector4(u * 2.0 - 1.0, w * 2.0 - 1.0, surface.w, 1.0);
    final Vector4 worldH = inverse * ndc;
    final position = Vector3(worldH.x, worldH.y, worldH.z)
      ..scale(1.0 / worldH.w);

    final camera = b.vec4('ReflectionInfo', 'camera', Vector4.zero());
    final toEye = (Vector3(camera.x, camera.y, camera.z) - position)
      ..normalize();
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
      final sv = ny * 0.5 + 0.5;
      if (su < 0.0 || su > 1.0 || sv < 0.0 || sv > 1.0) break;

      final sceneDepth = surfaceMap.sample(su, sv).w;
      if (sceneDepth > 0.0) {
        final difference = nz - sceneDepth;
        if (difference > 0.0 && difference < thickness) {
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
