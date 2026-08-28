/// `ssao.frag`, screen-space ambient occlusion, marched against the surface
/// buffer. See `cpu_shaders_reflections.dart` for the other ray march over the
/// same buffer, and `cpu_shaders_post.dart` for the composite that reads this
/// pass's output.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';
import 'cpu_shaders_color.dart';

/// The twelve kernel taps of `ssao.frag`, in the same order.
///
/// A table on both sides rather than a hash, and the reason is this file: the
/// cross-backend budgets are measured in hundredths of a per cent, and a float
/// hash agrees between a GPU and this rasteriser nowhere at all.
const List<List<double>> ssaoKernel = <List<double>>[
  <double>[0.5381, 0.1856, 0.4319],
  <double>[0.1379, 0.2486, 0.4430],
  <double>[0.3371, 0.5679, 0.0057],
  <double>[-0.6999, -0.0451, 0.0019],
  <double>[0.0689, -0.1598, -0.8547],
  <double>[0.0560, 0.0069, -0.1843],
  <double>[-0.0146, 0.1402, 0.0762],
  <double>[0.0100, -0.1924, -0.0344],
  <double>[-0.3577, -0.5301, -0.4358],
  <double>[-0.3169, 0.1063, 0.0158],
  <double>[0.0103, -0.5869, 0.0046],
  <double>[-0.0897, -0.4940, 0.3287],
];

/// `ssao.frag`: how much of the sky a point can see.
///
/// The transcription that makes the software rasteriser an oracle for this
/// pass. Everything it needs comes out of the surface buffer — octahedral
/// normal in rg, window depth in a — because flutter_gpu cannot sample a depth
/// attachment and the whole engine is built around that one fact.
final class SsaoShader implements CpuFragmentShader {
  const SsaoShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final surfaceMap = b.textures['surface_texture'];
    if (surfaceMap == null) return Vector4(1.0, 1.0, 1.0, 1.0);

    final u = v[0];
    final w = v[1];
    final surface = surfaceMap.sample(u, w);

    // Nothing was drawn here: the buffer is cleared to zero, and a zero alpha
    // is the sky rather than a surface on the near plane.
    if (surface.w <= 0.0) return Vector4(1.0, 1.0, 1.0, 1.0);

    final params = b.vec4('SsaoInfo', 'params', Vector4.zero());
    final screen = b.vec4('SsaoInfo', 'screen', Vector4.zero());
    final radius = math.max(params.x, 1e-4);
    final samples = (params.y + 0.5).floor().clamp(1, 12);

    final inverse = b.mat4('SsaoInfo', 'inverse_view_projection');
    final projection = b.mat4('SsaoInfo', 'view_projection');

    Vector3 worldFrom(double uu, double vv, double depth) {
      final Vector4 h =
          inverse * Vector4(uu * 2.0 - 1.0, vv * 2.0 - 1.0, depth, 1.0);
      return Vector3(h.x, h.y, h.z)..scale(1.0 / h.w);
    }

    final normal = decodeOctahedral(surface.x, surface.y);
    // Lifted along the normal, in metres: a bias in window depth is a different
    // physical distance at every range.
    final origin = worldFrom(u, w, surface.w)..addScaled(normal, params.w);

    // One of four rotations by the parity of the pixel, which leaves a 2×2
    // pattern that the composite's 2×2 average cancels exactly.
    final px = (u / (screen.x == 0.0 ? 1.0 : screen.x)).floor();
    final py = (w / (screen.y == 0.0 ? 1.0 : screen.y)).floor();
    final oddX = px % 2 != 0;
    final oddY = py % 2 != 0;
    final double rotX, rotY;
    if (oddX && oddY) {
      rotX = -0.7071;
      rotY = -0.7071;
    } else if (oddX) {
      rotX = 0.7071;
      rotY = -0.7071;
    } else if (oddY) {
      rotX = -0.7071;
      rotY = 0.7071;
    } else {
      rotX = 1.0;
      rotY = 0.0;
    }

    var occluded = 0.0;
    for (var i = 0; i < samples; i++) {
      final tap = ssaoKernel[i];
      var spun = Vector3(
        tap[0] * rotX - tap[1] * rotY,
        tap[0] * rotY + tap[1] * rotX,
        tap[2],
      );
      // Flipped into the hemisphere the surface faces rather than built from a
      // tangent frame: this pass has no tangent, and any it invented would
      // rotate along a silhouette and shimmer.
      if (spun.dot(normal) < 0.0) spun = -spun;

      final at = origin + spun * radius;
      final Vector4 clip = projection * Vector4(at.x, at.y, at.z, 1.0);
      if (clip.w <= 0.0) continue;
      final ndcX = clip.x / clip.w;
      final ndcY = clip.y / clip.w;
      final ndcZ = clip.z / clip.w;
      if (ndcX.abs() > 1.0 || ndcY.abs() > 1.0) continue;

      final su = ndcX * 0.5 + 0.5;
      final sv = ndcY * 0.5 + 0.5;
      final there = surfaceMap.sample(su, sv);
      // The sky occludes nothing: a tap that lands on it is looking out of the
      // scene, which is the opposite of being enclosed.
      if (there.w <= 0.0) continue;
      if (there.w >= ndcZ) continue;

      // The range check, without which every silhouette gains a dark outline:
      // a wall four metres behind a railing is nearer to the camera than the
      // taps around the railing and would occlude all of them.
      final seen = worldFrom(su, sv, there.w);
      occluded += smoothstep(
        0.0,
        1.0,
        radius / math.max(seen.distanceTo(origin), 1e-4),
      );
    }

    // Raw, with no strength: the strength belongs to the composite, which is
    // the pass that has to make "off" mean a multiplier of exactly one.
    final ao = (1.0 - occluded / samples).clamp(0.0, 1.0);
    return Vector4(ao, ao, ao, ao);
  }
}
