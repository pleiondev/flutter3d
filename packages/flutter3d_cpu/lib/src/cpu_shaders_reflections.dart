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
    final camera = b.vec4('ReflectionInfo', 'camera', Vector4.zero());
    final eye = Vector3(camera.x, camera.y, camera.z);
    final forward = b.vec4('ReflectionInfo', 'forward', Vector4.zero());
    final axis = Vector3(forward.x, forward.y, forward.z);

    // The two halves of the origin convention, kept next to each other so they
    // cannot drift apart: v runs the other way from clip-space y, and the
    // matrices carry whichever backend this is.
    double vFromNdc(double ndcY) => 0.5 - ndcY * 0.5;

    /// `WorldAt`: the pixel's ray crossed with the plane the stored depth
    /// names, because the buffer holds metres along the view axis rather than a
    /// window depth. Shared with the occlusion pass; see [worldAtDepth].
    Vector3 worldFrom(double uu, double vv, double depth) =>
        worldAtDepth(inverse, eye, axis, uu, vv, depth);

    final position = worldFrom(u, w, surface.w);

    // Back along the ray this pixel looks down, not towards the camera
    // position: the two agree under a perspective camera and do not under an
    // orthographic one, whose rays are parallel. See `PixelRay` in the GLSL.
    final toEye = -pixelRay(inverse, u, w).along;
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
      final su = nx * 0.5 + 0.5;
      final sv = vFromNdc(ny);
      if (su < 0.0 || su > 1.0 || sv < 0.0 || sv > 1.0) break;

      final sceneDepth = surfaceMap.sample(su, sv).w;
      final marchDepth = (march - eye).dot(axis);
      // Behind what was drawn here, then how far behind. The second in the
      // world rather than in depths: the two points sit on one ray, and along a
      // ray running away from the camera a depth difference is shorter than the
      // gap it stands for. Thickness is a size in the world.
      if (sceneDepth > 0.0 && marchDepth > sceneDepth) {
        final seen = worldFrom(su, sv, sceneDepth);
        final behind = march.distanceTo(seen);
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

/// `light_shafts.frag`: volumetric shafts marched through the shadow map —
/// `gfx-33n`.
///
/// Mirrors the GLSL operation for operation, the contract every shader in
/// this package keeps.
final class LightShaftsShader implements CpuFragmentShader {
  const LightShaftsShader();

  /// `BayerCell` from the shader, in [0, 1).
  static double _bayer(double x, double y) {
    const table = <int>[0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];
    final cx = x.floor() % 4;
    final cy = y.floor() % 4;
    final index = ((cy < 0 ? cy + 4 : cy) * 4) + (cx < 0 ? cx + 4 : cx);
    return table[index] / 16.0;
  }

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final sceneTexture = b.textures['scene_texture'];
    if (sceneTexture == null) return Vector4(0.0, 0.0, 0.0, 1.0);
    final scene = sceneTexture.sample(v[0], v[1]);

    final forward = b.vec4('ShaftInfo', 'forward', Vector4.zero());
    final steps = (forward.w + 0.5).floor();
    if (steps < 1) return scene;

    final surfaceTexture = b.textures['surface_texture'];
    final shadow = b.textures['shadow_texture'];
    if (surfaceTexture == null || shadow == null) return scene;

    final inverse = b.mat4('ShaftInfo', 'inverse_view_projection');
    final camera = b.vec4('ShaftInfo', 'camera', Vector4.zero());
    final scatter = b.vec4('ShaftInfo', 'scatter', Vector4.zero());
    final cascades = b.vec4('ShaftInfo', 'cascades', Vector4.zero());

    final ndcX = v[0] * 2.0 - 1.0;
    final ndcY = 1.0 - v[1] * 2.0;
    final nearH = inverse.transformed(Vector4(ndcX, ndcY, 0.0, 1.0));
    final farH = inverse.transformed(Vector4(ndcX, ndcY, 1.0, 1.0));
    final origin = Vector3(nearH.x, nearH.y, nearH.z)..scale(1.0 / nearH.w);
    final farPoint = Vector3(farH.x, farH.y, farH.z)..scale(1.0 / farH.w);
    final along = (farPoint - origin)..normalize();

    final axis = Vector3(forward.x, forward.y, forward.z);
    final surfaceDepth = surfaceTexture.sample(v[0], v[1]).w;
    final cosine = math.max(along.dot(axis), 1e-4);
    final toSurface = surfaceDepth > 0.0 ? surfaceDepth / cosine : 1e9;
    final distance = math.min(camera.w, toSurface);
    if (distance <= 0.0) return scene;

    final stride = distance / steps;
    final offset = _bayer(c.coord.x, c.coord.y) * stride;

    final matrices = <Matrix4>[
      b.mat4('ShaftInfo', 'shadow_matrix'),
      b.mat4('ShaftInfo', 'shadow_matrix_far'),
      b.mat4('ShaftInfo', 'shadow_matrix_farthest'),
    ];
    final cascadeCount = (cascades.z + 0.5).floor();

    double litAt(Vector3 world, double viewDistance) {
      var cascade = 0;
      if (cascadeCount > 1 && viewDistance > cascades.x) cascade = 1;
      if (cascadeCount > 2 && viewDistance > cascades.y) cascade = 2;

      for (var attempt = 0; attempt < 3; attempt++) {
        final which = cascade + attempt;
        if (which >= cascadeCount) break;
        final lightSpace = matrices[which].transformed(
          Vector4(world.x, world.y, world.z, 1.0),
        );
        if (lightSpace.w <= 0.0) continue;
        final candidate = Vector3(lightSpace.x, lightSpace.y, lightSpace.z)
          ..scale(1.0 / lightSpace.w);
        final tileX = candidate.x * 0.5 + 0.5;
        final tileY = 0.5 - candidate.y * 0.5;
        if (tileX < 0.0 || tileX > 1.0 || tileY < 0.0 || tileY > 1.0) continue;
        if (candidate.z > 1.0) continue;
        final stored = shadow.sample((tileX + which) / cascadeCount, tileY).x;
        return candidate.z - cascades.w > stored ? 0.0 : 1.0;
      }
      // Outside the map is lit: a point with nothing recorded about it is not
      // in shadow, and calling it shadow would put a wall of darkness across
      // the far half of every shaft.
      return 1.0;
    }

    var lit = 0.0;
    for (var i = 0; i < steps && i < 64; i++) {
      final travelled = offset + i * stride;
      final at = origin + along * travelled;
      lit += litAt(at, travelled * cosine);
    }

    final share = lit / steps;
    return Vector4(
      scene.x + scatter.x * share,
      scene.y + scatter.y * share,
      scene.z + scatter.z * share,
      scene.w,
    );
  }
}

/// `depth_of_field.frag`: a thin lens and a gather — `gfx-34n`.
///
/// Mirrors the GLSL operation for operation, the contract every shader in
/// this package keeps. The golden angle and the `sqrt` on the radius are
/// carried across literally: change either and the same picture stops coming
/// out of the two implementations, which is the only thing keeping this one
/// honest.
final class DepthOfFieldShader implements CpuFragmentShader {
  const DepthOfFieldShader();

  /// `kGolden` from the shader.
  static const double _golden = 2.39996323;

  /// `CircleAt` from the shader: the circle of confusion at [depth] metres,
  /// as a radius in texels.
  ///
  /// **Public so a test can hold it against the thin-lens equation rather
  /// than against a recorded picture.** It is not a second implementation —
  /// it is this one, reachable: the arithmetic the CPU backend actually runs,
  /// and the conformance set is what holds it level with the GLSL.
  static double circleOfConfusion(
    double depth, {
    required double focusDistance,
    required double focalLength,
    required double aperture,
    required double maxRadius,
    required double texelsPerMetre,
  }) {
    if (depth <= 0.0) return 0.0;
    final focus = math.max(focusDistance, 1e-3);
    final focal = math.max(focalLength, 1e-4);
    final fnumber = math.max(aperture, 1e-3);
    final denominator = math.max(fnumber * (focus - focal), 1e-6);
    final diameter =
        (depth - focus).abs() / depth * (focal * focal) / denominator;
    return math.min(diameter * 0.5 * texelsPerMetre, math.max(maxRadius, 0.0));
  }

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final sceneTexture = b.textures['scene_texture'];
    if (sceneTexture == null) return Vector4(0.0, 0.0, 0.0, 1.0);
    final centre = sceneTexture.sample(v[0], v[1]);

    final lens = b.vec4('DofInfo', 'lens', Vector4.zero());
    final samples = (lens.w + 0.5).floor();
    if (samples < 1) return centre;

    final surfaceTexture = b.textures['surface_texture'];
    if (surfaceTexture == null) return centre;

    final params = b.vec4('DofInfo', 'params', Vector4.zero());

    double circleAt(double depth) => circleOfConfusion(
      depth,
      focusDistance: lens.x,
      focalLength: lens.y,
      aperture: lens.z,
      maxRadius: params.z,
      texelsPerMetre: params.w,
    );

    final centreDepth = surfaceTexture.sample(v[0], v[1]).w;
    final radius = circleAt(centreDepth);
    // Inside half a texel the disc is smaller than the pixel it lands on,
    // which is what "in focus" means.
    if (radius < 0.5) return centre;

    var totalX = centre.x;
    var totalY = centre.y;
    var totalZ = centre.z;
    var weight = 1.0;

    for (var i = 1; i <= samples && i <= 64; i++) {
      final t = i / samples;
      final r = math.sqrt(t) * radius;
      final angle = i * _golden;
      final atU = v[0] + math.cos(angle) * r * params.x;
      final atV = v[1] + math.sin(angle) * r * params.y;

      final tap = sceneTexture.sample(atU, atV);
      final tapDepth = surfaceTexture.sample(atU, atV).w;
      final tapRadius = circleAt(tapDepth);

      // Would this sample's own disc have reached here? A sharp background
      // pixel behind a blurred foreground says no.
      if (r > math.max(tapRadius, radius)) continue;
      totalX += tap.x;
      totalY += tap.y;
      totalZ += tap.z;
      weight += 1.0;
    }

    return Vector4(totalX / weight, totalY / weight, totalZ / weight, centre.w);
  }
}

/// `viewport_shade.frag`: shading read out of the surface buffer —
/// `gfx-43n`, `gfx-44n` and `gfx-45n`.
///
/// Mirrors the GLSL branch for branch, the contract every shader in this
/// package keeps. Four modes and a no-op, decided by `params.x` — a number
/// rather than an enum for the same reason the GLSL has one: it is part of a
/// uniform layout four backends read.
final class ViewportShadeShader implements CpuFragmentShader {
  const ViewportShadeShader();

  @override
  Vector4? run(Float32List v, ShaderBindings b, FragmentContext c) {
    final sceneTexture = b.textures['scene_texture'];
    if (sceneTexture == null) return Vector4(0.0, 0.0, 0.0, 1.0);
    final scene = sceneTexture.sample(v[0], v[1]);

    final params = b.vec4('ShadeInfo', 'params', Vector4.zero());
    final mode = (params.x + 0.5).floor();
    final amount = params.y.clamp(0.0, 1.0);
    if (mode < 1 || amount <= 0.0) return scene;

    final surfaceTexture = b.textures['surface_texture'];
    if (surfaceTexture == null) return scene;

    final surface = surfaceTexture.sample(v[0], v[1]);
    final depth = surface.w;
    // Nothing was drawn here, so there is no surface to shade: the background
    // keeps what the scene left. Every mode is a shading of the subject.
    if (depth <= 0.0) return scene;

    final screen = b.vec4('ShadeInfo', 'screen', Vector4.zero());
    final normal = decodeOctahedral(surface.x, surface.y);
    var shaded = Vector3(scene.x, scene.y, scene.z);

    if (mode == 1) {
      shaded = Vector3(
        normal.x * 0.5 + 0.5,
        normal.y * 0.5 + 0.5,
        normal.z * 0.5 + 0.5,
      );
    } else if (mode == 2) {
      final ambient = params.z.clamp(0.0, 1.0);
      final light = b.vec4('ShadeInfo', 'light', Vector4.zero());
      final aim = Vector3(light.x, light.y, light.z);
      if (aim.length2 > 0.0) aim.normalize();
      final lambert = math.max(normal.dot(aim), 0.0);
      final value = ambient + (1.0 - ambient) * lambert;
      shaded = Vector3(value, value, value);
    } else if (mode == 3) {
      final width = math.max(screen.z, 1.0);
      final tx = screen.x * width;
      final ty = screen.y * width;
      var depthEdge = 0.0;
      var normalEdge = 0.0;
      const count = 4;
      for (var i = 0; i < count; i++) {
        final ou = switch (i) {
          0 => tx,
          1 => -tx,
          _ => 0.0,
        };
        final ov = switch (i) {
          2 => ty,
          3 => -ty,
          _ => 0.0,
        };
        final tap = surfaceTexture.sample(v[0] + ou, v[1] + ov);
        if (tap.w <= 0.0) {
          // Against the background: a silhouette, the strongest edge there is.
          depthEdge = 1.0;
          continue;
        }
        depthEdge = math.max(depthEdge, (tap.w - depth).abs());
        normalEdge = math.max(
          normalEdge,
          1.0 - decodeOctahedral(tap.x, tap.y).dot(normal),
        );
      }
      final depthHit = depthEdge >= math.max(params.z, 1e-4) ? 1.0 : 0.0;
      final normalHit = normalEdge >= math.max(params.w, 1e-4) ? 1.0 : 0.0;
      final edge = math.max(depthHit, normalHit);
      shaded = Vector3(
        scene.x * (1.0 - edge),
        scene.y * (1.0 - edge),
        scene.z * (1.0 - edge),
      );
    } else if (mode == 4) {
      Vector3 at(double du, double dv) {
        final tap = surfaceTexture.sample(v[0] + du, v[1] + dv);
        return decodeOctahedral(tap.x, tap.y);
      }

      final right = at(screen.x, 0.0);
      final left = at(-screen.x, 0.0);
      final down = at(0.0, screen.y);
      final up = at(0.0, -screen.y);
      final curvature =
          ((right.x - left.x) + (down.y - up.y)) * math.max(params.z, 0.0);
      final cavity = (-curvature).clamp(0.0, 1.0) * params.w.clamp(0.0, 1.0);
      final ridge = curvature.clamp(0.0, 1.0);
      final value = (0.5 + ridge * 0.5 - cavity).clamp(0.0, 1.0);
      shaded = Vector3(value, value, value);
    }

    return Vector4(
      scene.x + (shaded.x - scene.x) * amount,
      scene.y + (shaded.y - scene.y) * amount,
      scene.z + (shaded.z - scene.z) * amount,
      scene.w,
    );
  }
}
