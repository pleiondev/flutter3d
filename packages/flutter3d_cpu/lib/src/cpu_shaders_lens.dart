/// `lens_flare.frag`: the ghosts and the halo a lens throws from what is
/// bright in the frame, added to the glow — `P2`, line for line.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'cpu_shader.dart';

/// `lens_flare.frag`.
final class LensFlareShader extends CpuFragmentShader {
  const LensFlareShader();

  /// `Falloff`: all of a reflection in the middle, nothing at the corners.
  static double _falloff(double u, double w, double power) {
    final dx = 0.5 - u;
    final dy = 0.5 - w;
    final d = math.sqrt(dx * dx + dy * dy) / 0.70710678;
    return math.pow(math.max(1.0 - d, 0.0), power).toDouble();
  }

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final bloom = b.textures['bloom_texture'];
    if (bloom == null) return Vector4(0.0, 0.0, 0.0, 1.0);
    final params = b.vec4('LensFlareInfo', 'params', Vector4.zero());
    final more = b.vec4('LensFlareInfo', 'more', Vector4.zero());

    // `Fringed`: the glow at (u, w), its channels taken [spread] apart.
    Vector3 fringed(double u, double w, double ax, double ay, double spread) =>
        Vector3(
          bloom.sample(u + ax * spread, w + ay * spread).x,
          bloom.sample(u, w).y,
          bloom.sample(u - ax * spread, w - ay * spread).z,
        );

    final glow = bloom.sample(v[0], v[1]);
    final flippedU = 1.0 - v[0];
    final flippedW = 1.0 - v[1];
    final towardU = (0.5 - flippedU) * params.z;
    final towardW = (0.5 - flippedW) * params.z;
    final reach = math.sqrt(towardU * towardU + towardW * towardW);
    final alongU = reach > 1e-6 ? towardU / reach : 0.0;
    final alongW = reach > 1e-6 ? towardW / reach : 0.0;
    final spread = more.x;

    final flare = Vector3.zero();
    final ghosts = (params.y + 0.5).floor();
    for (var i = 0; i < 8; i++) {
      if (i >= ghosts) break;
      final u = flippedU + towardU * i;
      final w = flippedW + towardW * i;
      flare.add(fringed(u, w, alongU, alongW, spread) * _falloff(u, w, 10.0));
    }

    final aspect = math.max(more.z, 1e-4);
    final haloU = flippedU + alongU / aspect * params.w;
    final haloW = flippedW + alongW * params.w;
    flare.add(
      fringed(haloU, haloW, alongU, alongW, spread) *
          (_falloff(haloU, haloW, 5.0) * more.y),
    );

    final intensity = params.x;
    return Vector4(
      glow.x + flare.x * intensity,
      glow.y + flare.y * intensity,
      glow.z + flare.z * intensity,
      1.0,
    );
  }
}
