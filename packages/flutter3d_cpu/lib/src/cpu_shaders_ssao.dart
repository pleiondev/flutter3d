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

  /// `PixelRadius` from `ssao.frag`: how many pixels of this target
  /// [radius] metres span at [point]. The horizon searches step in pixels,
  /// the one unit the projection keeps square; stepped in uv, a radius
  /// measured across the screen reached only height/width of it upwards.
  static double _pixelRadius(
    ShaderBindings b,
    Vector3 point,
    Vector3 view,
    double radius,
  ) {
    final projection = b.mat4('SsaoInfo', 'view_projection');
    final screen = b.vec4('SsaoInfo', 'screen', Vector4.zero());
    Vector2 uvOf(Vector3 at) {
      final Vector4 clip = projection * Vector4(at.x, at.y, at.z, 1.0);
      return Vector2(clip.x / clip.w * 0.5 + 0.5, 0.5 - clip.y / clip.w * 0.5);
    }

    final across = view.cross(
      view.y.abs() < 0.99 ? Vector3(0.0, 1.0, 0.0) : Vector3(1.0, 0.0, 0.0),
    )..normalize();
    final reach = uvOf(point + across * radius) - uvOf(point);
    return Vector2(reach.x / screen.x, reach.y / screen.y).length;
  }

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
    // `EyeWard`: the pixel's ray reversed, which an orthographic camera's
    // parallel rays need where the camera position would tilt off the slice.
    final view = -pixelRay(
      b.mat4('SsaoInfo', 'inverse_view_projection'),
      u,
      w,
    ).along;
    final radius = math.max(params.x, 1e-4);
    final steps = ((params.y + 0.5).floor() ~/ 4).clamp(1, 4);

    final pixelRadius = _pixelRadius(b, point, view, radius);

    final px = (u / screen.x).floorToDouble();
    final py = (w / screen.y).floorToDouble();
    final noise = pixelNoise(b, px, py);

    var visibility = 0.0;
    var slices = 0.0;
    for (var slice = 0; slice < 2; slice++) {
      final phi = (slice + noise) * 1.5707963;
      final dx = math.cos(phi) * screen.x;
      final dy = math.sin(phi) * screen.y;
      final along = worldFrom(u + dx, w + dy, depth) - point;
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
          math.acos((projected.dot(view) / projectedLength).clamp(0.0, 1.0));

      final horizons = <double>[0.0, 0.0];
      for (var side = 0; side < 2; side++) {
        final s = side == 0 ? -1.0 : 1.0;
        var best = -1.0;
        for (var i = 0; i < steps; i++) {
          final t = (i + 0.5 + 0.5 * noise) / steps;
          final au = u + s * dx * pixelRadius * t;
          final av = w + s * dy * pixelRadius * t;
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
      final h1 = n + (horizons[0] - n).clamp(-1.5707963, 1.5707963);
      final h2 = n + (horizons[1] - n).clamp(-1.5707963, 1.5707963);
      double arc(double h) =>
          -math.cos(2.0 * h - n) + math.cos(n) + 2.0 * h * math.sin(n);
      visibility += projectedLength * 0.25 * (arc(h1) + arc(h2));
      slices += 1.0;
    }
    return slices > 0.0 ? (visibility / slices).clamp(0.0, 1.0) : 1.0;
  }

  /// `SrgbToLinearAlbedo` from `ssao.frag`, one channel.
  static double _linear(double c) =>
      c < 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

  /// `MultiBounce` from `ssao.frag` — `L5`: the fit of Jimenez et al. 2016,
  /// per channel of the [srgb] albedo, brought to one number by luma.
  static double _multiBounce(double visible, Vector4 srgb) {
    double channel(double albedo) {
      final a = 2.0404 * albedo - 0.3324;
      final b = -4.7951 * albedo + 0.6417;
      final c = 2.7552 * albedo + 0.6903;
      return math.max(visible, ((visible * a + b) * visible + c) * visible);
    }

    return 0.2126 * channel(_linear(srgb.x)) +
        0.7152 * channel(_linear(srgb.y)) +
        0.0722 * channel(_linear(srgb.z));
  }

  /// `SsilLight` from `ssao.frag` — `L5`: rgb the light bounced onto the
  /// point, a the share of the hemisphere left open.
  static Vector4 _ssil(
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
    // `EyeWard`: the pixel's ray reversed, which an orthographic camera's
    // parallel rays need where the camera position would tilt off the slice.
    final view = -pixelRay(
      b.mat4('SsaoInfo', 'inverse_view_projection'),
      u,
      w,
    ).along;
    final radius = math.max(params.x, 1e-4);
    final thickness = math.max(screen.w, 1e-3);
    final steps = ((params.y + 0.5).floor() ~/ 4).clamp(1, 4);
    final sceneMap = b.textures['scene_texture'];

    final pixelRadius = _pixelRadius(b, point, view, radius);

    final px = (u / screen.x).floorToDouble();
    final py = (w / screen.y).floorToDouble();
    final noise = pixelNoise(b, px, py);

    // The sixteen sectors of `SectorRun`, one where a run takes in a
    // sector's centre.
    List<double> run(double low, double high) => <double>[
      for (var k = 0; k < 16; k++)
        (k + 0.5) / 16.0 >= low && (k + 0.5) / 16.0 <= high ? 1.0 : 0.0,
    ];

    final light = Vector3.zero();
    var open = 0.0;
    var slices = 0.0;
    for (var slice = 0; slice < 2; slice++) {
      final phi = (slice + noise) * 1.5707963;
      final dx = math.cos(phi) * screen.x;
      final dy = math.sin(phi) * screen.y;
      final along = worldFrom(u + dx, w + dy, depth) - point;
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
          math.acos((projected.dot(view) / projectedLength).clamp(0.0, 1.0));

      final covered = List<double>.filled(16, 0.0);
      for (var side = 0; side < 2; side++) {
        final s = side == 0 ? -1.0 : 1.0;
        for (var i = 0; i < steps; i++) {
          final t = (i + 0.5 + 0.5 * noise) / steps;
          final au = u + s * dx * pixelRadius * t;
          final av = w + s * dy * pixelRadius * t;
          if (au < 0.0 || au > 1.0 || av < 0.0 || av > 1.0) continue;
          final sampled = surfaceMap.sample(au, av);
          if (sampled.w <= 0.0) continue;
          final front = worldFrom(au, av, sampled.w) - point;
          if (front.length > radius) continue;
          final toward = front.normalized();
          final back = front - view * thickness;
          final a = s * math.acos(toward.dot(view).clamp(-1.0, 1.0));
          final bb =
              s * math.acos(back.normalized().dot(view).clamp(-1.0, 1.0));
          final m = run(
            (math.min(a, bb) - n + 1.5707963) / 3.1415927,
            (math.max(a, bb) - n + 1.5707963) / 3.1415927,
          );
          var fresh = 0.0;
          for (var k = 0; k < 16; k++) {
            fresh += m[k] * (1.0 - covered[k]);
            covered[k] = math.max(covered[k], m[k]);
          }
          final radiance = sceneMap?.sample(au, av) ?? Vector4.zero();
          // Both ends' cosines: the receiver's, and the sample's back to it.
          final cosine =
              math.max(normal.dot(toward), 0.0) *
              math.max(
                -decodeOctahedral(sampled.x, sampled.y).dot(toward),
                0.0,
              );
          light.addScaled(
            Vector3(radiance.x, radiance.y, radiance.z),
            cosine * fresh / 16.0,
          );
        }
      }
      open += 1.0 - covered.fold(0.0, (sum, k) => sum + k) / 16.0;
      slices += 1.0;
    }
    if (slices <= 0.0) return Vector4(0.0, 0.0, 0.0, 1.0);
    final albedoMap = b.textures['albedo_texture'];
    final Vector3 albedo;
    if (params.z > 0.5 && albedoMap != null) {
      final srgb = albedoMap.sample(u, w);
      albedo = Vector3(_linear(srgb.x), _linear(srgb.y), _linear(srgb.z));
    } else {
      albedo = Vector3.all(0.5);
    }
    final bounced = light / slices
      ..multiply(albedo);
    return Vector4(bounced.x, bounced.y, bounced.z, open / slices);
  }

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final surfaceMap = b.textures['surface_texture'];
    if (surfaceMap == null) return Vector4(1.0, 1.0, 1.0, 1.0);

    final u = v[0];
    final w = v[1];
    final surface = surfaceMap.sample(u, w);

    // Nothing was drawn here: the buffer is cleared to zero, and a zero alpha
    // is the sky rather than a surface on the near plane. Open, and with the
    // indirect method nothing bounces onto it.
    if (surface.w <= 0.0) {
      return b.vec4('SsaoInfo', 'screen', Vector4.zero()).z > 1.5
          ? Vector4(0.0, 0.0, 0.0, 1.0)
          : Vector4(1.0, 1.0, 1.0, 1.0);
    }

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

    // `L5`: the horizon search with its light, as `SsilLight`.
    if (screen.z > 1.5) {
      return _ssil(
        b,
        surfaceMap,
        u,
        w,
        worldFrom(u, w, surface.w),
        normal,
        surface.w,
        worldFrom,
      );
    }

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
      // With the albedo buffer, the bounces too, as `MultiBounce`.
      final albedoMap = b.textures['albedo_texture'];
      final shaded = params.z > 0.5 && albedoMap != null
          ? _multiBounce(visible, albedoMap.sample(u, w))
          : visible;
      return Vector4(shaded, shaded, shaded, shaded);
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

    // All four channels, as the shader since `L5`.
    final centre = ao.sample(v[0], v[1]);
    final taps = params.z;
    if (taps < 1.0) return centre;

    final surface = bindings.textures['surface_texture'];
    if (surface == null) return centre;

    final centreDepth = surface.sample(v[0], v[1]).w;
    final falloff = math.max(params.w, 1e-4);

    final total = Vector4.copy(centre);
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
        total.addScaled(ao.sample(u, w), weight);
        weightSum += weight;
      }
    }

    return total..scale(1.0 / weightSum);
  }
}
