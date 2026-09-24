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
import 'cpu_shaders_reflections.dart' show blueNoise, pixelNoise;

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
/// normal in rg, metres along the view axis in a — because flutter_gpu cannot
/// sample a depth attachment and the whole engine is built around that one
/// fact.
final class SsaoShader implements CpuFragmentShader {
  const SsaoShader();

  /// `GtaoVisibility` from `ssao.frag` — `L5`.
  static double _gtao(
    ShaderBindings b,
    BoundTexture surfaceMap,
    double u,
    double w,
    Vector3 point,
    Vector3 normal,
    double depth,
    Vector3 Function(double, double, double) worldFrom,
  ) {
    final params = b.vec4('SsaoInfo', 'params', Vector4.zero());
    final screen = b.vec4('SsaoInfo', 'screen', Vector4.zero());
    final projection = b.mat4('SsaoInfo', 'view_projection');
    final eye4 = b.vec4('SsaoInfo', 'camera', Vector4.zero());
    final view = (Vector3(eye4.x, eye4.y, eye4.z) - point)..normalize();
    final radius = math.max(params.x, 1e-4);
    final steps = ((params.y + 0.5).floor() ~/ 4).clamp(1, 4);

    Vector2 uvOf(Vector3 at) {
      final Vector4 clip = projection * Vector4(at.x, at.y, at.z, 1.0);
      return Vector2(clip.x / clip.w * 0.5 + 0.5, 0.5 - clip.y / clip.w * 0.5);
    }

    final across = view.cross(
      view.y.abs() < 0.99 ? Vector3(0.0, 1.0, 0.0) : Vector3(1.0, 0.0, 0.0),
    )..normalize();
    final uvRadius = (uvOf(point + across * radius) - uvOf(point)).length;

    final px = (u / screen.x).floorToDouble();
    final py = (w / screen.y).floorToDouble();
    final noise = pixelNoise(b, px, py);

    var visibility = 0.0;
    var slices = 0.0;
    for (var slice = 0; slice < 2; slice++) {
      final phi = (slice + noise) * 1.5707963;
      final dx = math.cos(phi);
      final dy = math.sin(phi);
      final along = worldFrom(u + dx * 1e-3, w + dy * 1e-3, depth) - point;
      final tangent = along - view * along.dot(view);
      final tangentLength = tangent.length;
      if (tangentLength < 1e-6) continue;
      tangent.scale(1.0 / tangentLength);
      final axis = tangent.cross(view)..normalize();
      final projected = normal - axis * normal.dot(axis);
      final projectedLength = projected.length;
      if (projectedLength < 1e-4) continue;
      final n =
          projected.dot(tangent).sign *
          math.acos((projected.dot(view) / projectedLength).clamp(-1.0, 1.0));

      final horizons = <double>[0.0, 0.0];
      for (var side = 0; side < 2; side++) {
        final s = side == 0 ? -1.0 : 1.0;
        var best = -1.0;
        for (var i = 0; i < steps; i++) {
          final t = (i + 0.5 + 0.5 * noise) / steps;
          final au = u + s * dx * uvRadius * t;
          final av = w + s * dy * uvRadius * t;
          if (au < 0.0 || au > 1.0 || av < 0.0 || av > 1.0) continue;
          final d = surfaceMap.sample(au, av).w;
          if (d <= 0.0) continue;
          final toSample = worldFrom(au, av, d) - point;
          final distance = toSample.length;
          if (distance < 1e-5) continue;
          final cosine = toSample.dot(view) / distance;
          final fade = (1.0 - distance * distance / (radius * radius)).clamp(
            0.0,
            1.0,
          );
          best = math.max(best, -1.0 + (cosine + 1.0) * fade);
        }
        horizons[side] = s * math.acos(best.clamp(-1.0, 1.0));
      }
      final h1 = n + math.max(horizons[0] - n, -1.5707963);
      final h2 = n + math.min(horizons[1] - n, 1.5707963);
      double arc(double h) =>
          -math.cos(2.0 * h - n) + math.cos(n) + 2.0 * h * math.sin(n);
      visibility += projectedLength * 0.25 * (arc(h1) + arc(h2));
      slices += 1.0;
    }
    return slices > 0.0 ? (visibility / slices).clamp(0.0, 1.0) : 1.0;
  }

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
    final eye4 = b.vec4('SsaoInfo', 'camera', Vector4.zero());
    final eye = Vector3(eye4.x, eye4.y, eye4.z);
    final forward4 = b.vec4('SsaoInfo', 'forward', Vector4.zero());
    final axis = Vector3(forward4.x, forward4.y, forward4.z);

    // v runs the other way from clip-space y, as it does in the shadow lookup:
    // `toFramebufferOrigin` puts the backend's convention into the matrices, so
    // the pair below is the same arithmetic everywhere. See `UvFromNdc` in
    // ssao.frag for what marching against a mirrored buffer used to do.
    double vFromNdc(double ndcY) => 0.5 - ndcY * 0.5;

    /// `WorldAtDepth`: the pixel's ray, crossed with the plane the stored depth
    /// names. Shared with the reflections march; see [worldAtDepth].
    Vector3 worldFrom(double uu, double vv, double depth) =>
        worldAtDepth(inverse, eye, axis, uu, vv, depth);

    /// How deep [at] is, in the metres the buffer holds.
    double depthOf(Vector3 at) => (at - eye).dot(axis);

    final normal = decodeOctahedral(surface.x, surface.y);

    // `L5`: the horizon search, as `GtaoVisibility`.
    if (screen.z > 0.5) {
      final visible = _gtao(
        b,
        surfaceMap,
        u,
        w,
        worldFrom(u, w, surface.w),
        normal,
        surface.w,
        worldFrom,
      );
      return Vector4(visible, visible, visible, visible);
    }

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
    // `R3`: an angle from the blue noise while a temporal resolve runs.
    if (b.vec4('NoiseInfo', 'noise', Vector4.zero()).x > 0.5) {
      final angle = 6.2831853 * blueNoise(b, px.toDouble(), py.toDouble());
      rotX = math.cos(angle);
      rotY = math.sin(angle);
    } else if (oddX && oddY) {
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
      if (ndcX.abs() > 1.0 || ndcY.abs() > 1.0) continue;

      final su = ndcX * 0.5 + 0.5;
      final sv = vFromNdc(ndcY);
      final there = surfaceMap.sample(su, sv);
      // The sky occludes nothing: a tap that lands on it is looking out of the
      // scene, which is the opposite of being enclosed.
      if (there.w <= 0.0) continue;
      // Nearer to the eye than the point sampled towards means something stands
      // between them, compared in the metres the buffer holds.
      if (there.w >= depthOf(at)) continue;

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

/// `ssao_blur.frag`: the depth-aware smoothing over what [SsaoShader] drew —
/// `gfx-32n`.
///
/// Mirrors the GLSL operation for operation, the contract every shader in
/// this package keeps: the two are compared by golden images, and a shortcut
/// here would read as a backend disagreeing about the picture.
final class SsaoBlurShader implements CpuFragmentShader {
  const SsaoBlurShader();

  @override
  Vector4? run(Float32List v, ShaderBindings bindings, FragmentContext c) {
    final ao = bindings.textures['ao_texture'];
    if (ao == null) return Vector4(1.0, 1.0, 1.0, 1.0);
    final params = bindings.vec4('SsaoBlurInfo', 'params', Vector4.zero());

    final centre = ao.sample(v[0], v[1]).x;
    final taps = params.z;
    if (taps < 1.0) return Vector4(centre, centre, centre, 1.0);

    final surface = bindings.textures['surface_texture'];
    if (surface == null) return Vector4(centre, centre, centre, 1.0);

    final centreDepth = surface.sample(v[0], v[1]).w;
    final falloff = math.max(params.w, 1e-4);

    var total = centre;
    var weightSum = 1.0;
    // Bounded at eight to each side whatever the uniform says, the same rule
    // the shader keeps and for the same reason.
    for (var i = 1; i <= 8; i++) {
      if (i > taps) break;
      final offset = i.toDouble();
      final steps = <List<double>>[
        <double>[params.x * offset, 0.0],
        <double>[-params.x * offset, 0.0],
        <double>[0.0, params.y * offset],
        <double>[0.0, -params.y * offset],
      ];
      for (final step in steps) {
        final u = v[0] + step[0];
        final w = v[1] + step[1];
        final depth = surface.sample(u, w).w;
        final closeness = math.exp(
          -(depth - centreDepth).abs() /
              (falloff * math.max(centreDepth, 1e-3)),
        );
        final weight = closeness / offset;
        total += ao.sample(u, w).x * weight;
        weightSum += weight;
      }
    }

    final blurred = total / weightSum;
    return Vector4(blurred, blurred, blurred, 1.0);
  }
}
